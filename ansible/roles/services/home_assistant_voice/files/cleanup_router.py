#!/usr/bin/env python3
"""Preview or remove explicitly inventoried legacy voice objects after promotion.

An ownership manifest is mandatory. Names or regexes alone never imply ownership.
Backups are retained; this command deliberately has no automatic purge mode.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from configure import WebSocket, http_json
from deploy_router import HOST, PRODUCTION, DOMAIN, private_json, validate_acceptance


def candidates(manifest, pipelines, entities, entries, subentries, states):
    referenced = {p.get(field) for p in pipelines for field in
                  ('conversation_engine', 'stt_engine', 'tts_engine', 'wake_word_entity')}
    protected_names = {PRODUCTION}
    hardware_names = {s['state'] for s in states if s['entity_id'].startswith('select.')
                      and 'assistant' in s['entity_id']}
    removals = {'pipelines': [], 'subentries': [], 'entries': []}
    for owned in manifest.get('pipelines', []):
        current = next((p for p in pipelines if p['id'] == owned['id']), None)
        if current is None:
            continue
        if current['name'] != owned['name'] or current['name'] in protected_names | hardware_names:
            raise ValueError('Pipeline identity changed or still selected')
        removals['pipelines'].append(current)
    # Even slated-for-removal pipelines still protect their agents on this run.
    # Run the preview again after deleting them, rather than assuming deletion.
    for owned in manifest.get('subentries', []):
        current = next((s for s in subentries.get(owned['entry_id'], [])
                        if s['subentry_id'] == owned['subentry_id']), None)
        if current is None:
            continue
        if current['title'] != owned['title']:
            raise ValueError('Subentry identity changed')
        linked = [e for e in entities if e.get('config_entry_id') == owned['entry_id']
                  and e.get('config_subentry_id') == owned['subentry_id']]
        if any(e['entity_id'] in referenced for e in linked):
            raise ValueError('Legacy agent is still referenced by a pipeline')
        removals['subentries'].append({**current, 'entry_id': owned['entry_id']})
    for owned in manifest.get('entries', []):
        current = next((e for e in entries if e['entry_id'] == owned['entry_id']), None)
        if current is None:
            continue
        if current['domain'] != owned['domain'] or current['title'] != owned['title']:
            raise ValueError('Config entry identity changed')
        if current['domain'] not in ('ollama', 'wyoming', 'bilingual_assist'):
            raise ValueError('Only voice integrations can be removed')
        linked = [e for e in entities if e.get('config_entry_id') == current['entry_id']]
        if current.get('num_subentries') or any(e['entity_id'] in referenced for e in linked):
            raise ValueError('Config entry still has subentries or pipeline references')
        removals['entries'].append(current)
    return removals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--backup-dir', required=True)
    parser.add_argument('--acceptance-file', default='')
    parser.add_argument('--sha256', default='')
    parser.add_argument('--model', default='')
    parser.add_argument('--release-manifest', required=True)
    parser.add_argument('--ssh-port', type=int, default=2222)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    token = os.environ['HOME_ASSISTANT_TOKEN']
    manifest = json.loads(Path(args.manifest).read_text())
    ws = WebSocket(args.url, token, True)
    snapshot = ws.command({'type': 'assist_pipeline/pipeline/list'})
    entities = ws.command({'type': 'config/entity_registry/list'})
    entries = ws.command({'type': 'config_entries/get'})
    states = http_json(args.url, token, 'GET', '/api/states')
    subentries = {}
    for owned in manifest.get('subentries', []):
        entry_id = owned['entry_id']
        if entry_id not in subentries and any(e['entry_id'] == entry_id for e in entries):
            subentries[entry_id] = ws.command({'type': 'config_entries/subentries/list', 'entry_id': entry_id})
    removals = candidates(manifest, snapshot['pipelines'], entities, entries, subentries, states)
    if not args.apply:
        print(json.dumps({'preview': removals}, indent=2))
        return
    validate_acceptance(args.acceptance_file, args.sha256, args.model,
                        json.loads(Path(args.release_manifest).read_text()))
    production = next(p for p in snapshot['pipelines'] if p['name'] == PRODUCTION)
    router_entities = {e['entity_id'] for e in entities if e.get('platform') == DOMAIN}
    if production['conversation_engine'] not in router_entities or production.get('prefer_local_intents') is not False:
        raise ValueError('Router has not been promoted; cleanup refused')
    if snapshot.get('preferred_pipeline') != production['id']:
        raise ValueError('Accepted router is not preferred; cleanup refused')
    if not any(removals.values()):
        print('ok')
        return
    backup = Path(args.backup_dir)
    backup.mkdir(mode=0o700, parents=True, exist_ok=True)
    stem = 'router-cleanup-' + str(time.time_ns())
    # HA API redacts credentials. Preserve actual storage privately before writes.
    storage = backup / (stem + '.storage.tar')
    with os.fdopen(os.open(storage, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as stream:
        subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                        '-p', str(args.ssh_port), 'root@' + HOST,
                        'tar -cf - -C /config .storage'], stdout=stream, check=True)
    private_json(backup / (stem + '.json'), {'snapshot': snapshot, 'removed': removals,
                'hardware': [s for s in states if s['entity_id'].startswith('select.')],
                'acceptance': json.loads(Path(args.acceptance_file).read_text())})
    for item in removals['pipelines']:
        ws.command({'type': 'assist_pipeline/pipeline/delete', 'pipeline_id': item['id']})
    for item in removals['subentries']:
        ws.command({'type': 'config_entries/subentries/delete', 'entry_id': item['entry_id'],
                    'subentry_id': item['subentry_id']})
    for item in removals['entries']:
        http_json(args.url, token, 'DELETE', '/api/config/config_entries/entry/' + item['entry_id'])
    print('changed: removed inventoried voice objects; retained private rollback backups')


if __name__ == '__main__':
    main()
