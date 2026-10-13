#!/usr/bin/env python3
"""Verified integration deployment and gated pipeline promotion from jumphost."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import time
import zipfile
from configure import WebSocket, http_json, config_flow

PRODUCTION = 'Local Swedish to English'
CANDIDATE = PRODUCTION + ' — Validation'
RECORDING = 'Swedish voice evaluation — No actions'
HOST = 'homeassistant.local.hejsan.xyz'
DOMAIN = 'bilingual_assist_v2'


def private_json(path, data):
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream:
        json.dump(data,stream,indent=2)


def verified_members(archive, expected, domain='bilingual_assist'):
    if domain not in ('bilingual_assist', DOMAIN):
        raise ValueError('Unsupported integration domain')
    if hashlib.sha256(Path(archive).read_bytes()).hexdigest()!=expected:
        raise ValueError('Integration archive checksum mismatch')
    with zipfile.ZipFile(archive) as package:
        result=[]
        for item in package.infolist():
            path=Path(item.filename)
            if path.is_absolute() or '..' in path.parts or path.parts[:2]!=('custom_components',domain):
                raise ValueError('Unexpected archive member')
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Archive symlink rejected')
            if item.file_size>1024*1024:
                raise ValueError('Oversized archive member')
            if not item.is_dir(): result.append((str(path.relative_to('custom_components')),package.read(item)))
        if len(result)>100 or not any(name==domain+'/manifest.json' for name,_ in result):
            raise ValueError('Invalid integration package')
        if len({name for name,_ in result}) != len(result):
            raise ValueError('Duplicate archive member')
        manifest=json.loads(next(data for name,data in result if name==domain+'/manifest.json'))
        if manifest.get('domain') != domain:
            raise ValueError('Integration manifest domain mismatch')
        return result


def install(archive,sha,port,domain=DOMAIN):
    members=verified_members(archive,sha,domain)
    ssh=['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-p',str(port),'root@'+HOST]
    remote_sha=subprocess.check_output(ssh+[f'cat /config/custom_components/{domain}/.release-sha256 2>/dev/null || true'],text=True).strip()
    if remote_sha==sha: return False
    # Tar input is built only from validated ZIP members, never arbitrary paths.
    archive_buffer=io.BytesIO()
    with tarfile.open(fileobj=archive_buffer,mode='w') as tar:
        for name,contents in members:
            item=tarfile.TarInfo(name);item.size=len(contents);item.mode=0o644
            tar.addfile(item,io.BytesIO(contents))
        contents=(sha+'\n').encode()
        item=tarfile.TarInfo(domain+'/.release-sha256');item.size=len(contents);item.mode=0o644
        tar.addfile(item,io.BytesIO(contents))
    stage='/config/.voice-router-stage/'+sha
    subprocess.run(ssh+[f'mkdir -p {stage}; chmod 700 /config/.voice-router-stage {stage}'],check=True)
    subprocess.run(ssh+[f'tar -xf - -C {stage}'],input=archive_buffer.getvalue(),check=True)
    script=f'''set -eu
mkdir -p /config/custom_components /config/.voice-router-backups
chmod 700 /config/.voice-router-backups
if [ -d /config/custom_components/{domain} ]; then
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  mv /config/custom_components/{domain} /config/.voice-router-backups/{domain}-$stamp
fi
mv {stage}/{domain} /config/custom_components/{domain}
'''
    subprocess.run(ssh+['sh -s'],input=script.encode(),check=True)
    return True


def release_fingerprint(release):
    """Bind acceptance to every tested binary/model and non-secret setting."""
    required = ('stt_revision', 'stt_image', 'tts_image', 'model_digest', 'configuration')
    if any(not release.get(k) for k in required):
        raise ValueError('Release manifest must pin STT, TTS, model and configuration')
    for key in ('stt_image', 'tts_image'):
        if not re.search(r'@sha256:[0-9a-f]{64}$', release[key]):
            raise ValueError('Release images must be digest-pinned')
    if not re.fullmatch(r'[0-9a-f]{40}', release['stt_revision']):
        raise ValueError('STT revision must be immutable')
    if not re.fullmatch(r'[0-9a-f]{64}', release['model_digest']):
        raise ValueError('Model digest must be immutable')
    config=release['configuration']
    if 'search_password' in config.get('router',{}):
        raise ValueError('Credentials must not be stored in the release manifest')
    required_router={'ollama_url','model','search_url','search_username','search_enabled',
                     'session_timeout','max_turns','num_ctx','debug_text','recovery_enabled','classify_questions'}
    if set(config.get('router',{})) != required_router:
        raise ValueError('Release manifest must include the complete router configuration')
    required_pipeline={'stt_engine','stt_language','tts_engine','tts_language','tts_voice',
                       'wake_word_entity','wake_word_id'}
    if set(config.get('pipeline',{})) != required_pipeline:
        raise ValueError('Release manifest must include the complete pipeline configuration')
    return hashlib.sha256(json.dumps(release,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def validate_acceptance(path,sha,model,release=None):
    data=json.loads(Path(path).read_text())
    # A human can explicitly promote a release without the recording corpus,
    # but the exception must still be bound to this exact immutable release.
    # This is intentionally distinct from a successful test acceptance: it
    # cannot be mistaken for one or used without an explicit checked-in record.
    if data.get('operator_override') is True:
        if (not isinstance(data.get('reason'),str) or not data['reason'].strip()
                or data.get('release_sha256')!=sha or data.get('model')!=model
                or release is None or data.get('release_fingerprint') != release_fingerprint(release)):
            raise ValueError('Operator override is incomplete or for another release/model')
        return data
    required=('hardware_passed','gpu_concurrent_passed','regression_suite_passed',
              'search_passed','idempotency_passed','playback_passed')
    if not all(data.get(k) is True for k in required) or data.get('release_sha256')!=sha or data.get('model')!=model:
        raise ValueError('Acceptance report missing, failed, or for another release/model')
    if release is None or data.get('release_fingerprint') != release_fingerprint(release):
        raise ValueError('Acceptance must match the complete release manifest')
    tested=datetime.fromisoformat(data['tested_at'].replace('Z','+00:00'))
    if tested.tzinfo is None or not 0 <= (datetime.now(timezone.utc)-tested).total_seconds() <= 7*86400:
        raise ValueError('Acceptance report must be timezone-aware and no more than seven days old')
    metrics=data.get('metrics',{})
    minimums={'recorded_utterances':80,'held_out_utterances':40,'ordinary_accuracy':0.95,
              'recovery_accuracy':0.90,'concurrency_minutes':30,'idle_free_vram_mib':2048,
              'concurrent_free_vram_mib':1024}
    maximums={'unsafe_executions':0,'duplicate_actions':0,'duplicate_responses':0,
              'ooms':0,'playback_failures':0,'ordinary_median_seconds':2.5,
              'ordinary_p95_seconds':4,'recovery_p95_seconds':6}
    import math
    for key,limit in {**minimums,**maximums}.items():
        value=metrics.get(key)
        if type(value) not in (int,float) or not math.isfinite(value) or value<0:
            raise ValueError('Missing or invalid acceptance metric: '+key)
        if (key in minimums and value<limit) or (key in maximums and value>limit):
            raise ValueError('Acceptance gate failed: '+key)
    return data


def configure_pipeline(ws, url, token, agent, selectors, pipeline, promote=False, name=None):
    """Staging never selects hardware, including on a fresh installation."""
    snapshot=ws.command({'type':'assist_pipeline/pipeline/list'})
    name=name or (PRODUCTION if promote else CANDIDATE)
    current=next((p for p in snapshot['pipelines'] if p['name']==name),None)
    selected_names={s['state'] for s in selectors}
    if not promote and current and (current['id']==snapshot.get('preferred_pipeline') or name in selected_names):
        raise ValueError('Candidate is currently selected; unselect it before replacing its configuration')
    wanted={**pipeline,'name':name,'language':'sv','conversation_language':'sv',
            'conversation_engine':agent,'prefer_local_intents':False}
    changed=False
    if current is None:
        ws.command({'type':'assist_pipeline/pipeline/create',**wanted});changed=True
    elif any(current.get(k)!=v for k,v in wanted.items()):
        ws.command({'type':'assist_pipeline/pipeline/update','pipeline_id':current['id'],**wanted});changed=True
    if not promote:
        return changed
    updated=ws.command({'type':'assist_pipeline/pipeline/list'})
    selected=next(p for p in updated['pipelines'] if p['name']==name)
    if updated.get('preferred_pipeline')!=selected['id']:
        ws.command({'type':'assist_pipeline/pipeline/set_preferred','pipeline_id':selected['id']});changed=True
    for selector in selectors:
        if selector['state']!=name:
            http_json(url,token,'POST','/api/services/select/select_option',
                      {'entity_id':selector['entity_id'],'option':name});changed=True
    return changed


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
    parser.add_argument('--release-manifest',required=True)
    parser.add_argument('--acceptance-file',default='')
    parser.add_argument('--promote',type=lambda s:s.lower()=='true',default=False)
    args=parser.parse_args()
    if len(args.sha256)!=64 or any(c not in '0123456789abcdef' for c in args.sha256):
        raise ValueError('Invalid release checksum')
    release=json.loads(Path(args.release_manifest).read_text())
    release_fingerprint(release)
    if args.promote: validate_acceptance(args.acceptance_file,args.sha256,args.model,release)
    token=os.environ['HOME_ASSISTANT_TOKEN']
    ws=WebSocket(args.url,token,True)
    snapshot=ws.command({'type':'assist_pipeline/pipeline/list'})
    config=release['configuration']
    pipeline=config['pipeline']
    settings={**config['router'],'search_password':os.environ.get('HOME_ASSISTANT_SEARCH_PASSWORD','')}
    if settings['ollama_url']!=args.ollama_url or settings['model']!=args.model:
        raise ValueError('Role model/URL differ from release manifest')
    if settings['search_enabled']:
        if not settings['search_password']: raise ValueError('Search enabled but credentials missing')
        from urllib.request import Request, urlopen
        import base64
        auth=base64.b64encode((settings['search_username']+':'+settings['search_password']).encode()).decode()
        request=Request(settings['search_url']+'/search?q=Home+Assistant&format=json',
                        headers={'Authorization':'Basic '+auth})
        with urlopen(request,timeout=10) as response:
            if not json.load(response).get('results'): raise ValueError('Authenticated search returned no results')
    models=http_json(args.ollama_url,'','GET','/api/tags')['models']
    if not any(m['name']==args.model for m in models): raise ValueError('Pinned model is not prepared')
    show=http_json(args.ollama_url,'','POST','/api/show',{'model':args.model})
    if 'tools' not in show.get('capabilities',[]): raise ValueError('Model lacks tested tool-call support')
    installed=next(m for m in models if m['name']==args.model)
    if installed.get('digest')!=release['model_digest']:
        raise ValueError('Ollama model digest differs from the tested release')
    backup=Path(args.backup_dir);backup.mkdir(parents=True,exist_ok=True)
    states=http_json(args.url,token,'GET','/api/states')
    selectors=[s for s in states if s['entity_id'] in ['select.home_assistant_voice_096648_assistant','select.home_assistant_voice_096648_assistant_2']]
    # Installing code affects every pipeline using this domain, not only the
    # candidate. Refuse staging over an active v2 instance before any writes.
    registry=ws.command({'type':'config/entity_registry/list'})
    our_agents={e['entity_id'] for e in registry if e.get('platform')==DOMAIN}
    active_names={s['state'] for s in selectors}
    if not args.promote and any(p.get('conversation_engine') in our_agents and
        (p['id']==snapshot.get('preferred_pipeline') or p['name'] in active_names)
        for p in snapshot['pipelines']):
        raise ValueError('Cannot stage over an active v2 integration')
    for field in ('stt_engine','tts_engine'):
        if not any(s['entity_id']==pipeline[field] and s['state']!='unavailable' for s in states):
            raise ValueError('Configured voice engine is unavailable: '+pipeline[field])
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
                ha_config=http_json(args.url,token,'GET','/api/config')
                if DOMAIN in ha_config.get('components',[]): break
                # Custom integration becomes a component only after config entry creation.
                if time.monotonic()>deadline: break
                ws=WebSocket(args.url,token,True);break
            except OSError:
                if time.monotonic()>deadline: raise
                time.sleep(2)
    existing=http_json(args.url,token,'GET','/api/config/config_entries/entry?domain='+DOMAIN)
    if len(existing)>1:
        raise ValueError('Multiple router entries found; resolve ownership before deployment')
    if existing:
        entry,created=existing[0],False
    else:
        entry,created=config_flow(args.url,token,DOMAIN,settings,True)
    changed |= created
    entry_id=entry.get('entry_id')
    existing=http_json(args.url,token,'GET','/api/config/config_entries/entry?domain='+DOMAIN)
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
        agent=next((e['entity_id'] for e in registry if e.get('config_entry_id')==entry_id and
                    e.get('unique_id')==entry_id and not e.get('disabled_by')),None)
        if not conversation_entity_available(agent, states):
            agent=None
        if agent: break
        time.sleep(1)
    if not agent: raise ValueError('Router entity did not become available')
    ws=WebSocket(args.url,token,True)
    changed |= configure_pipeline(ws,args.url,token,agent,selectors,pipeline,args.promote)
    if not args.promote:
        recorder=next((e['entity_id'] for e in registry if e.get('config_entry_id')==entry_id and
                       e.get('unique_id')==entry_id+'_recorder' and not e.get('disabled_by')),None)
        if not recorder: raise ValueError('No-action recording agent is unavailable')
        changed |= configure_pipeline(ws,args.url,token,recorder,selectors,pipeline,name=RECORDING)
    if changed and args.promote: http_json(args.url,token,'POST','/api/services/tts/clear_cache',{})
    print('changed' if changed else 'ok')


if __name__=='__main__': main()
