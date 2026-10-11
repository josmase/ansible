#!/usr/bin/env python3
"""Measure an Assist text-to-audio run, consuming the actual TTS stream."""
import argparse
import json
import os
import time
import urllib.request

from configure import WebSocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://homeassistant.local.hejsan.xyz:8123')
    parser.add_argument('--pipeline', default='Local Swedish to English')
    parser.add_argument('--text', default='Vad är klockan?')
    parser.add_argument('--count', type=int, default=1)
    args = parser.parse_args()
    token = os.environ['HOME_ASSISTANT_TOKEN']
    ws = WebSocket(args.url, token, True)
    pipeline = next(p for p in ws.command({'type': 'assist_pipeline/pipeline/list'})['pipelines'] if p['name'] == args.pipeline)
    for _ in range(args.count):
        ws = WebSocket(args.url, token, True)
        started = time.monotonic()
        result = {'pipeline': args.pipeline, 'text': args.text, 'tool_calls': []}
        ws._send_json({'id': 1, 'type': 'assist_pipeline/run', 'pipeline': pipeline['id'], 'start_stage': 'intent', 'end_stage': 'tts', 'input': {'text': args.text}, 'conversation_id': None, 'timeout': 60})
        audio_url = None
        while True:
            event = ws._recv_json().get('event', {})
            kind = event.get('type')
            data = event.get('data') or {}
            if kind == 'error':
                raise RuntimeError(data)
            if kind == 'intent-progress':
                result['tool_calls'].extend(data.get('chat_log_delta', {}).get('tool_calls', []))
            if kind == 'intent-end':
                result['intent_seconds'] = round(time.monotonic() - started, 3)
                result['speech'] = data['intent_output']['response']['speech']['plain']['speech']
            if kind == 'tts-end':
                audio_url = data['tts_output']['url']
            if kind == 'run-end':
                break
        if not audio_url:
            raise RuntimeError('No TTS URL returned')
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(args.url.rstrip('/') + audio_url, timeout=60) as response:
            first = response.read(1024)
            result['first_media_bytes_seconds'] = round(time.monotonic() - started, 3)
            result['audio_bytes'] = len(first) + len(response.read())
        result['audio_complete_seconds'] = round(time.monotonic() - started, 3)
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
