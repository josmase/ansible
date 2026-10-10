#!/usr/bin/env python3
"""Configure Home Assistant local voice using its public HTTP/WebSocket APIs."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import sys
import urllib.parse
import urllib.request


PROGRESS_LOG = "/tmp/home-assistant-voice-configure.log"


def progress(message):
    with open(PROGRESS_LOG, "a", encoding="utf-8") as log:
        log.write(message + "\n")


def http_json(base_url: str, token: str, method: str, path: str, payload=None, verify=True):
    url = base_url.rstrip("/") + path
    context = ssl.create_default_context() if verify else ssl._create_unverified_context()
    body = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=context),
    )
    with opener.open(request, timeout=10) as response:
        raw = response.read()
    return json.loads(raw) if raw else None


class WebSocket:
    def __init__(self, base_url: str, token: str, verify: bool):
        parsed = urllib.parse.urlparse(base_url)
        self.sock = socket.create_connection((parsed.hostname, parsed.port or 443), timeout=30)
        if parsed.scheme == "https":
            context = ssl.create_default_context() if verify else ssl._create_unverified_context()
            self.sock = context.wrap_socket(self.sock, server_hostname=parsed.hostname)
        key = base64.b64encode(os.urandom(16)).decode()
        host = parsed.hostname if not parsed.port else f"{parsed.hostname}:{parsed.port}"
        request = (
            f"GET /api/websocket HTTP/1.1\r\nHost: {host}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(request.encode())
        self.buffer = b""
        while b"\r\n\r\n" not in self.buffer:
            self.buffer += self.sock.recv(4096)
        headers, self.buffer = self.buffer.split(b"\r\n\r\n", 1)
        if b" 101 " not in headers:
            raise RuntimeError("Home Assistant WebSocket upgrade failed")
        self._recv_json()
        self._send_json({"type": "auth", "access_token": token})
        auth = self._recv_json()
        if auth.get("type") != "auth_ok":
            raise RuntimeError(f"Home Assistant WebSocket authentication failed: {auth}")
        self.next_id = 1

    def _send_frame(self, data: bytes):
        mask = os.urandom(4)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(data))
        length = len(masked)
        if length < 126:
            header = bytes([0x81, 0x80 | length])
        elif length < 65536:
            header = bytes([0x81, 0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytes([0x81, 0x80 | 127]) + struct.pack("!Q", length)
        self.sock.sendall(header + mask + masked)

    def _recv_frame(self):
        first, second = self._recv_exact(2)
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]
        masked = second & 0x80
        mask = self._recv_exact(4) if masked else b""
        data = self._recv_exact(length)
        if masked:
            data = bytes(value ^ mask[index % 4] for index, value in enumerate(data))
        opcode = first & 0x0F
        if opcode == 0x8:
            raise RuntimeError("Home Assistant WebSocket closed")
        if opcode == 0x9:
            self._send_frame(data)
            return self._recv_frame()
        return data

    def _recv_exact(self, length):
        while len(self.buffer) < length:
            self.buffer += self.sock.recv(4096)
        result, self.buffer = self.buffer[:length], self.buffer[length:]
        return result

    def _send_json(self, payload):
        self._send_frame(json.dumps(payload).encode())

    def _recv_json(self):
        return json.loads(self._recv_frame())

    def command(self, payload):
        payload = dict(payload)
        payload["id"] = self.next_id
        self.next_id += 1
        self._send_json(payload)
        while True:
            response = self._recv_json()
            if response.get("id") == payload["id"]:
                if not response.get("success", False):
                    raise RuntimeError(f"Home Assistant WebSocket command failed: {response}")
                return response.get("result")


def config_flow(base_url, token, handler, data, verify):
    progress(f"GET config entries {handler}")
    entries = http_json(base_url, token, "GET", f"/api/config/config_entries/entry?domain={handler}", verify=verify)
    if handler == "ollama":
        identity = {"url": data["url"]}
        matching = next((entry for entry in entries if all(entry.get("data", {}).get(key) == value for key, value in identity.items())), None)
    elif data.get("_title"):
        # HA redacts Wyoming host/port data in this endpoint. Matching by the
        # service title keeps repeated role runs from creating duplicates.
        matching = next((entry for entry in entries if entry.get("title") == data["_title"]), None)
    else:
        matching = next((entry for entry in entries if all(entry.get("data", {}).get(key) == value for key, value in data.items() if key != "api_key")), None)
    if matching:
        return matching, False
    progress(f"POST config flow {handler}")
    flow = http_json(base_url, token, "POST", "/api/config/config_entries/flow", {"handler": handler}, verify)
    progress(f"received config flow {handler}")
    for step in range(5):
        if flow.get("type") != "form":
            break
        schema_items = flow.get("data_schema", [])
        if isinstance(schema_items, dict):
            schema = set(schema_items)
        else:
            schema = {item["name"] for item in schema_items if "name" in item}
        submitted = {key: value for key, value in data.items() if key in schema}
        missing = schema - submitted.keys()
        if missing:
            raise RuntimeError(f"Config flow {handler} needs unsupported fields: {sorted(missing)}")
        progress(f"POST config flow step {handler} {step + 1} fields={sorted(schema)}")
        flow = http_json(base_url, token, "POST", f"/api/config/config_entries/flow/{flow['flow_id']}", submitted, verify)
    if flow.get("type") == "form":
        errors = flow.get("errors") or {}
        raise RuntimeError(f"Config flow {handler} did not advance after 5 steps: errors={errors}, step={flow.get('step_id')}")
    if flow.get("type") != "create_entry":
        raise RuntimeError(f"Config flow {handler} did not create an entry: {flow}")
    return flow["result"], True


def configure_ollama_subentry(base_url, token, entry, name, model, verify):
    """Create the Ollama conversation subentry used by current HA releases."""
    ws = WebSocket(base_url, token, verify)
    subentries = ws.command({
        "type": "config_entries/subentries/list",
        "entry_id": entry["entry_id"],
    })
    matching = next(
        (item for item in subentries if item.get("subentry_type") == "conversation" and item.get("title") == name),
        None,
    )
    if matching:
        return False

    flow = http_json(
        base_url,
        token,
        "POST",
        "/api/config/config_entries/subentries/flow",
        {"handler": [entry["entry_id"], "conversation"]},
        verify,
    )
    for _ in range(5):
        if flow.get("type") != "form":
            break
        schema_items = flow.get("data_schema", [])
        if isinstance(schema_items, dict):
            schema = set(schema_items)
        else:
            schema = {item["name"] for item in schema_items if "name" in item}
        values = {
            "name": name,
            "model": model,
            "llm_hass_api": ["assist"],
            "num_ctx": 8192,
            "max_history": 20,
            "keep_alive": -1,
            "think": False,
        }
        submitted = {key: values[key] for key in schema if key in values}
        missing = {"name", "model"} - submitted.keys()
        if missing:
            raise RuntimeError(f"Ollama subentry flow needs unsupported fields: {sorted(missing)}")
        flow = http_json(
            base_url,
            token,
            "POST",
            f"/api/config/config_entries/subentries/flow/{flow['flow_id']}",
            submitted,
            verify,
        )
    if flow.get("type") == "form":
        errors = flow.get("errors") or {}
        raise RuntimeError(f"Ollama subentry flow did not advance after 5 steps: errors={errors}")
    if flow.get("type") != "create_entry":
        raise RuntimeError(f"Ollama subentry flow failed: {flow}")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--ollama-url", required=True)
    parser.add_argument("--ollama-model", required=True)
    parser.add_argument("--pipeline-name", required=True)
    parser.add_argument("--conversation-name", required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument("--stt-host", required=True)
    parser.add_argument("--stt-port", required=True, type=int)
    parser.add_argument("--stt-language", required=True)
    parser.add_argument("--tts-host", required=True)
    parser.add_argument("--tts-port", required=True, type=int)
    parser.add_argument("--tts-language", required=True)
    parser.add_argument("--tts-voice", required=True)
    args = parser.parse_args()
    token = os.environ["HOME_ASSISTANT_TOKEN"]
    verify = os.environ.get("HOME_ASSISTANT_VERIFY_SSL", "true").lower() == "true"
    configure_integrations = os.environ.get("HOME_ASSISTANT_CONFIGURE_INTEGRATIONS", "true").lower() == "true"
    configure_pipeline = os.environ.get("HOME_ASSISTANT_CONFIGURE_PIPELINE", "true").lower() == "true"
    progress("checking Home Assistant API")
    http_json(args.url, token, "GET", "/api/", verify=verify)
    progress("configuring Home Assistant internal URL")
    WebSocket(args.url, token, verify).command({
        "type": "config/core/update",
        "internal_url": args.url,
    })
    progress("checking Ollama model")
    ollama_models = http_json(args.ollama_url, "", "GET", "/api/tags", verify=verify)
    if not any(model.get("name") == args.ollama_model for model in ollama_models.get("models", [])):
        raise RuntimeError(f"Ollama model {args.ollama_model} is not available")
    changed = False
    if configure_integrations:
        progress("configuring Ollama integration")
        ollama_entries = http_json(args.url, token, "GET", "/api/config/config_entries/entry?domain=ollama", verify=verify)
        ollama_entry = next((entry for entry in ollama_entries if entry.get("title") == args.ollama_url), None)
        if ollama_entry is None:
            ollama_entry, ollama_created = config_flow(args.url, token, "ollama", {"url": args.ollama_url, "api_key": ""}, verify)
            changed |= ollama_created
        progress("configuring Ollama conversation subentry")
        changed |= configure_ollama_subentry(args.url, token, ollama_entry, args.conversation_name, args.ollama_model, verify)
        progress("configuring Whisper integration")
        _, stt_changed = config_flow(args.url, token, "wyoming", {"host": args.stt_host, "port": args.stt_port, "_title": "faster-whisper"}, verify)
        changed |= stt_changed
        progress("configuring Piper integration")
        _, tts_changed = config_flow(args.url, token, "wyoming", {"host": args.tts_host, "port": args.tts_port, "_title": "piper"}, verify)
        changed |= tts_changed
        # Clear stale generated media after changing TTS backends. HA can
        # otherwise reuse an invalid cached MP3 and fail while adding ID3
        # metadata, leaving Voice satellites stuck in the response phase.
        progress("clearing Home Assistant TTS cache")
        http_json(args.url, token, "POST", "/api/services/tts/clear_cache", {}, verify=verify)
    if configure_pipeline:
        progress("configuring Assist pipeline")
        ws = WebSocket(args.url, token, verify)
        agents = ws.command({"type": "conversation/agent/list", "language": args.language})["agents"]
        stt = ws.command({"type": "stt/engine/list", "language": args.stt_language})["providers"]
        tts = ws.command({"type": "tts/engine/list", "language": args.tts_language})["providers"]
        pipelines = ws.command({"type": "assist_pipeline/pipeline/list"})["pipelines"]
        agent = next((item["id"] for item in agents if item.get("name") == args.conversation_name), None)
        stt_engine = next((item["engine_id"] for item in stt if "whisper" in item["engine_id"] or "wyoming" in item["engine_id"]), None)
        tts_engine = next((item["engine_id"] for item in tts if "piper" in item["engine_id"] or "wyoming" in item["engine_id"]), None)
        # Existing pipelines are a useful compatibility fallback when HA does
        # not return providers for the requested locale (this varies between
        # HA releases and provider integrations).
        local_pipeline = next(
            (
                item for item in pipelines
                if item.get("stt_engine") and item.get("tts_engine")
            ),
            None,
        )
        stt_engine = stt_engine or (local_pipeline or {}).get("stt_engine")
        tts_engine = tts_engine or (local_pipeline or {}).get("tts_engine")
        if not agent or not stt_engine or not tts_engine:
            raise RuntimeError(f"Could not identify local voice engines: agent={agent}, agents={agents}, stt={stt}, tts={tts}")
        if not any(item["name"] == args.pipeline_name for item in pipelines):
            ws.command({
                "type": "assist_pipeline/pipeline/create",
                "name": args.pipeline_name,
                "language": args.language,
                "conversation_engine": agent,
                "conversation_language": args.language,
                "stt_engine": stt_engine,
                "stt_language": args.stt_language,
                "tts_engine": tts_engine,
                "tts_language": args.tts_language,
                "tts_voice": args.tts_voice,
                "wake_word_entity": None,
                "wake_word_id": None,
                "prefer_local_intents": True,
            })
            changed = True
    print("changed" if changed else "ok")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
