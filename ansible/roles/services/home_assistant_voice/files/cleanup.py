#!/usr/bin/env python3
"""Remove only inventoried migration-owned voice entries after pipeline validation."""
import argparse
import json
import os
import re
import time

from configure import WebSocket, http_json

OLLAMA_ENTRY = "01M4KA3R23ENMNCFTWZVA7XHPQ"
LEGACY_SUBENTRIES = {
    "01M4KA7J4E6AK77Z1GREE89HZX", "01M4KYNPFAYGWR2G9GT82N2YX4",
    "01M4KZ3NT5RWQNR0V07RXPDRME", "01M4P2GMDFAABHFWAGDA656TRZ",
    "01M4P2ZYD9SB12YGSETR2X1C6S", "01M4P31272B4FH4BX5HZGNCFAJ",
    "01M4P3P74P1PYJTC4PQEYCQB85",
}
LEGACY_ENTRY = "01M4K5VQFJYFJYRGACRWG09Y7F"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True)
    args = parser.parse_args()
    token = os.environ['HOME_ASSISTANT_TOKEN']
    verify = os.environ.get('HOME_ASSISTANT_VERIFY_SSL', 'true').lower() == 'true'
    ws = WebSocket(args.url, token, verify)
    pipelines = ws.command({'type': 'assist_pipeline/pipeline/list'})
    active = {p['name']: p for p in pipelines['pipelines']}
    for name, voice in [('Local Swedish', 'sv_SE-alma-medium'), ('Local Swedish to English', 'af_heart')]:
        p = active.get(name, {})
        if p.get('tts_voice') != voice or not p.get('conversation_engine'):
            raise RuntimeError(f'Cleanup requires healthy configured pipeline {name}')
    entities = ws.command({'type': 'config/entity_registry/list'})
    entries = ws.command({'type': 'config_entries/get'})
    referenced = {p.get(field) for p in pipelines['pipelines'] for field in ['conversation_engine', 'stt_engine', 'tts_engine']}
    # A fresh HA installation has different IDs and no historical entries.
    subentries = ws.command({'type': 'config_entries/subentries/list', 'entry_id': OLLAMA_ENTRY}) if any(e['entry_id'] == OLLAMA_ENTRY for e in entries) else []
    candidates = []
    for item in subentries:
        owned = item['subentry_id'] in LEGACY_SUBENTRIES or re.fullmatch(r'Local Qwen2\.5 (Swedish|English) \[[0-9a-f]{12}\]', item['title'])
        linked = [e for e in entities if e.get('config_subentry_id') == item['subentry_id']]
        if owned and not any(e['entity_id'] in referenced for e in linked):
            candidates.append(item)
    old_entry = next((e for e in entries if e['entry_id'] == LEGACY_ENTRY and e['domain'] == 'ollama' and e['title'] == 'http://192.168.1.119:11434'), None)
    if old_entry and (old_entry.get('num_subentries') or any(e['entity_id'] in referenced for e in entities if e.get('config_entry_id') == LEGACY_ENTRY)):
        raise RuntimeError('Legacy Ollama integration still referenced; refusing removal')
    if not candidates and not old_entry:
        print('ok'); return
    backup = f'/tmp/home-assistant-voice-cleanup-{time.time_ns()}.json'
    with os.fdopen(os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as handle:
        json.dump({'pipelines': pipelines, 'removed_subentries': candidates, 'removed_entry': old_entry}, handle, indent=2)
    for item in candidates:
        ws.command({'type': 'config_entries/subentries/delete', 'entry_id': OLLAMA_ENTRY, 'subentry_id': item['subentry_id']})
    if old_entry:
        http_json(args.url, token, 'DELETE', f'/api/config/config_entries/entry/{LEGACY_ENTRY}', verify=verify)
    print(f'changed: removed {len(candidates)} legacy agents; backup={backup}')


if __name__ == '__main__':
    main()
