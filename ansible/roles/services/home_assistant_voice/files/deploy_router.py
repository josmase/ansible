#!/usr/bin/env python3
"""Verified integration deployment and gated pipeline promotion from jumphost."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time
import zipfile
from configure import WebSocket, http_json, config_flow

PRODUCTION = 'Local Swedish to English'
CANDIDATE = PRODUCTION + ' — Router Test'
HOST = 'homeassistant.local.hejsan.xyz'


def private_json(path, data):
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream:
        json.dump(data,stream,indent=2)


def verified_members(archive, expected):
    if hashlib.sha256(Path(archive).read_bytes()).hexdigest()!=expected:
        raise ValueError('Integration archive checksum mismatch')
    with zipfile.ZipFile(archive) as package:
        result=[]
        for item in package.infolist():
            path=Path(item.filename)
            if path.is_absolute() or '..' in path.parts or path.parts[:2]!=('custom_components','bilingual_assist'):
                raise ValueError('Unexpected archive member')
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Archive symlink rejected')
            if item.file_size>1024*1024:
                raise ValueError('Oversized archive member')
            if not item.is_dir(): result.append((str(path.relative_to('custom_components')),package.read(item)))
        if len(result)>100 or not any(name=='bilingual_assist/manifest.json' for name,_ in result):
            raise ValueError('Invalid integration package')
        return result


def install(archive,sha,port):
    members=verified_members(archive,sha)
    ssh=['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-p',str(port),'root@'+HOST]
    remote_sha=subprocess.check_output(ssh+['cat /config/custom_components/bilingual_assist/.release-sha256 2>/dev/null || true'],text=True).strip()
    if remote_sha==sha: return False
    # Tar input is built only from validated ZIP members, never arbitrary paths.
    archive_buffer=io.BytesIO()
    with tarfile.open(fileobj=archive_buffer,mode='w') as tar:
        for name,contents in members:
            item=tarfile.TarInfo(name);item.size=len(contents);item.mode=0o644
            tar.addfile(item,io.BytesIO(contents))
        contents=(sha+'\n').encode()
        item=tarfile.TarInfo('bilingual_assist/.release-sha256');item.size=len(contents);item.mode=0o644
        tar.addfile(item,io.BytesIO(contents))
    stage='/config/.voice-router-stage/'+sha
    subprocess.run(ssh+[f'mkdir -p {stage}; chmod 700 /config/.voice-router-stage {stage}'],check=True)
    subprocess.run(ssh+[f'tar -xf - -C {stage}'],input=archive_buffer.getvalue(),check=True)
    script=f'''set -eu
mkdir -p /config/custom_components /config/.voice-router-backups
chmod 700 /config/.voice-router-backups
if [ -d /config/custom_components/bilingual_assist ]; then
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  mv /config/custom_components/bilingual_assist /config/.voice-router-backups/bilingual_assist-$stamp
fi
mv {stage}/bilingual_assist /config/custom_components/bilingual_assist
'''
    subprocess.run(ssh+['sh -s'],input=script.encode(),check=True)
    return True


def validate_acceptance(path,sha,model):
    data=json.loads(Path(path).read_text())
    required=('hardware_passed','swedish_pipeline_passed','gpu_concurrent_passed','regression_suite_passed')
    if not all(data.get(k) is True for k in required) or data.get('release_sha256')!=sha or data.get('model')!=model:
        raise ValueError('Acceptance report missing, failed, or for another release/model')
    if data.get('whisper_revision')!='08e178d48790749d25932bbc082711ddcfdfbc4f' or not data.get('tested_at'):
        raise ValueError('Acceptance must identify STT revision and test time')
    tested=datetime.fromisoformat(data['tested_at'].replace('Z','+00:00'))
    if tested.tzinfo is None or not 0 <= (datetime.now(timezone.utc)-tested).total_seconds() <= 7*86400:
        raise ValueError('Acceptance report must be timezone-aware and no more than seven days old')
    if type(data.get('regression_questions')) is not int or data['regression_questions']<40:
        raise ValueError('Acceptance requires at least 40 recorded regression questions')
    return data


def conversation_entity_available(agent, states):
    """Conversation entities can be active before HA assigns a state value."""
    return bool(agent) and any(
        state.get('entity_id') == agent and state.get('state') != 'unavailable'
        for state in states
    )


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--url',required=True)
    parser.add_argument('--archive',required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--ssh-port',type=int,default=2222)
    parser.add_argument('--backup-dir',required=True)
    parser.add_argument('--ollama-url',required=True)
    parser.add_argument('--model',required=True)
    parser.add_argument('--acceptance-file',default='')
    parser.add_argument('--promote',type=lambda s:s.lower()=='true',default=False)
    args=parser.parse_args()
    if len(args.sha256)!=64 or any(c not in '0123456789abcdef' for c in args.sha256):
        raise ValueError('Invalid release checksum')
    if args.promote: validate_acceptance(args.acceptance_file,args.sha256,args.model)
    token=os.environ['HOME_ASSISTANT_TOKEN']
    ws=WebSocket(args.url,token,True)
    snapshot=ws.command({'type':'assist_pipeline/pipeline/list'})
    if not any(p['name']=='Local Swedish' and p['tts_voice']=='sv_SE-alma-medium' for p in snapshot['pipelines']):
        raise ValueError('Preserved Swedish/Alma pipeline missing')
    models=http_json(args.ollama_url,'','GET','/api/tags')['models']
    if not any(m['name']==args.model for m in models): raise ValueError('Pinned model is not prepared')
    show=http_json(args.ollama_url,'','POST','/api/show',{'model':args.model})
    if 'tools' not in show.get('capabilities',[]): raise ValueError('Model lacks tested tool-call support')
    backup=Path(args.backup_dir);backup.mkdir(parents=True,exist_ok=True)
    states=http_json(args.url,token,'GET','/api/states')
    selectors=[s for s in states if s['entity_id'] in ['select.home_assistant_voice_096648_assistant','select.home_assistant_voice_096648_assistant_2']]
    snapshot_file=backup/f'pre-router-{args.sha256}.json'
    if not snapshot_file.exists():
        private_json(snapshot_file,{'pipelines':snapshot,'hardware':selectors,'model':args.model})
    changed=install(args.archive,args.sha256,args.ssh_port)
    if changed:
        try: http_json(args.url,token,'POST','/api/services/homeassistant/restart',{})
        except OSError: pass # HA closes the connection during restart.
        deadline=time.monotonic()+120
        time.sleep(3)
        while True:
            try:
                config=http_json(args.url,token,'GET','/api/config')
                if 'bilingual_assist' in config.get('components',[]): break
                # Custom integration becomes a component only after config entry creation.
                if time.monotonic()>deadline: break
                ws=WebSocket(args.url,token,True);break
            except OSError:
                if time.monotonic()>deadline: raise
                time.sleep(2)
    settings={'ollama_url':args.ollama_url,'model':args.model,'search_url':'https://searxng.local.hejsan.xyz',
              'search_username':'assist','search_password':os.environ.get('HOME_ASSISTANT_SEARCH_PASSWORD',''),
              'search_enabled':bool(os.environ.get('HOME_ASSISTANT_SEARCH_PASSWORD')),
              'session_timeout':60,'max_turns':4,'num_ctx':8192,'debug_text':False}
    existing=http_json(args.url,token,'GET','/api/config/config_entries/entry?domain=bilingual_assist')
    if len(existing)>1:
        raise ValueError('Multiple router entries found; resolve ownership before deployment')
    if existing:
        entry,created=existing[0],False
    else:
        entry,created=config_flow(args.url,token,'bilingual_assist',settings,True)
    changed |= created
    entry_id=entry.get('entry_id')
    existing=http_json(args.url,token,'GET','/api/config/config_entries/entry?domain=bilingual_assist')
    if not entry_id and existing: entry_id=existing[0]['entry_id']
    # HA exposes data/options to an admin via the options flow, not config-entry lists.
    flow=http_json(args.url,token,'POST','/api/config/config_entries/options/flow',{'handler':entry_id})
    suggested={f['name']:f.get('default',f.get('description',{}).get('suggested_value')) for f in flow.get('data_schema',[])}
    if any(suggested.get(k)!=v for k,v in settings.items()):
        http_json(args.url,token,'POST','/api/config/config_entries/options/flow/'+flow['flow_id'],settings);changed=True
    else:
        http_json(args.url,token,'DELETE','/api/config/config_entries/options/flow/'+flow['flow_id'])
    for _ in range(30):
        states=http_json(args.url,token,'GET','/api/states')
        registry=WebSocket(args.url,token,True).command({'type':'config/entity_registry/list'})
        agent=next((e['entity_id'] for e in registry if e.get('config_entry_id')==entry_id and e['entity_id'].startswith('conversation.') and not e.get('disabled_by')),None)
        if not conversation_entity_available(agent, states):
            agent=None
        if agent: break
        time.sleep(1)
    if not agent: raise ValueError('Router entity did not become available')
    ws=WebSocket(args.url,token,True)
    pipelines=ws.command({'type':'assist_pipeline/pipeline/list'})['pipelines']
    source=next(p for p in pipelines if p['name']==PRODUCTION)
    name=PRODUCTION if args.promote else CANDIDATE
    current=next((p for p in pipelines if p['name']==name),None)
    wanted={k:source[k] for k in ['stt_engine','stt_language','tts_engine','tts_language','tts_voice','wake_word_entity','wake_word_id']}
    wanted.update(name=name,language='sv',conversation_language='sv',conversation_engine=agent,prefer_local_intents=False)
    if current is None:
        ws.command({'type':'assist_pipeline/pipeline/create',**wanted});changed=True
    elif any(current.get(k)!=v for k,v in wanted.items()):
        ws.command({'type':'assist_pipeline/pipeline/update','pipeline_id':current['id'],**wanted});changed=True
    if args.promote:
        for selector in selectors:
            if selector['state']!=PRODUCTION:
                http_json(args.url,token,'POST','/api/services/select/select_option',{'entity_id':selector['entity_id'],'option':PRODUCTION});changed=True
        if changed: http_json(args.url,token,'POST','/api/services/tts/clear_cache',{})
    print('changed' if changed else 'ok')


if __name__=='__main__': main()
