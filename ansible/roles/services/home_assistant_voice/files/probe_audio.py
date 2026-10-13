#!/usr/bin/env python3
"""Run a complete audio-to-TTS Assist pipeline test from a WAV recording.

The recording stays on the Ansible host. It is streamed as PCM to Home
Assistant's documented Assist WebSocket protocol and no device service calls
are made. The JSON result deliberately contains only timings, transcript, and
spoken reply; it never prints the access token or audio.
"""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import urllib.request
import wave

from configure import WebSocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--wav', required=True)
    parser.add_argument('--url', default='http://homeassistant.local.hejsan.xyz:8123')
    parser.add_argument('--pipeline', default='Local Swedish to English')
    parser.add_argument('--debug', action='store_true', help='Log pipeline stage names to stderr')
    parser.add_argument('--trace-file', help='New private file for safe protocol stage tracing')
    args = parser.parse_args()
    trace_path = Path(args.trace_file) if args.trace_file else None
    if trace_path and trace_path.exists():
        raise ValueError('Refusing to overwrite trace file')

    def trace(message):
        if args.debug:
            print(message, file=sys.stderr, flush=True)
        if trace_path:
            with trace_path.open('a', encoding='utf-8') as trace_output:
                trace_output.write(message + '\n')

    with wave.open(args.wav, 'rb') as audio:
        if audio.getsampwidth() != 2 or audio.getnchannels() != 1:
            raise ValueError('Expected 16-bit mono PCM WAV input')
        sample_rate = audio.getframerate()
        pcm = audio.readframes(audio.getnframes())

    token = os.environ['HOME_ASSISTANT_TOKEN']
    ws = WebSocket(args.url, token, True)
    pipeline = next(p for p in ws.command({'type': 'assist_pipeline/pipeline/list'})['pipelines']
                    if p['name'] == args.pipeline)
    started = time.monotonic()
    run_id = ws.next_id
    ws.next_id += 1
    ws._send_json({
        'id': run_id,
        'type': 'assist_pipeline/run',
        'pipeline': pipeline['id'],
        'start_stage': 'stt',
        'end_stage': 'tts',
        'input': {'sample_rate': sample_rate},
        'conversation_id': None,
        'timeout': 60,
    })
    trace('sent=assist_pipeline/run')

    result = {'pipeline': args.pipeline, 'sample_rate': sample_rate}
    binary_handler = None
    audio_sent = False
    audio_url = None
    while True:
        response = ws._recv_json()
        trace(f"message={response.get('type')} success={response.get('success')} error={response.get('error')}")
        if response.get('id') == run_id and not response.get('success', True):
            raise RuntimeError(response.get('error', 'Assist pipeline run was rejected'))
        event = response.get('event', {})
        kind = event.get('type')
        data = event.get('data') or {}
        if kind:
            trace(f'event={kind}')
        if kind == 'error':
            raise RuntimeError(data)
        if kind == 'run-start':
            binary_handler = data.get('runner_data', {}).get('stt_binary_handler_id')
        elif kind == 'stt-start':
            if not isinstance(binary_handler, int) or not 0 <= binary_handler <= 255:
                raise RuntimeError('No valid STT binary handler was provided')
            for offset in range(0, len(pcm), 8192):
                ws._send_binary(bytes([binary_handler]) + pcm[offset:offset + 8192])
            ws._send_binary(bytes([binary_handler]))
            audio_sent = True
        elif kind == 'stt-end':
            result['transcript'] = data['stt_output']['text']
            result['stt_seconds'] = round(time.monotonic() - started, 3)
        elif kind == 'intent-end':
            result['speech'] = data['intent_output']['response']['speech']['plain']['speech']
            result['intent_seconds'] = round(time.monotonic() - started, 3)
        elif kind == 'tts-end':
            audio_url = data['tts_output']['url']
        elif kind == 'run-end':
            break

    if not audio_sent or not audio_url:
        raise RuntimeError('Pipeline did not complete STT and TTS')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(args.url.rstrip('/') + audio_url, timeout=60) as response:
        first = response.read(1024)
        result['first_media_bytes_seconds'] = round(time.monotonic() - started, 3)
        result['audio_bytes'] = len(first) + len(response.read())
    result['audio_complete_seconds'] = round(time.monotonic() - started, 3)
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
