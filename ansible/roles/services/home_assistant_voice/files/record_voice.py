#!/usr/bin/env python3
"""Capture one Voice-hardware utterance through Home Assistant, safely.

The recording-only conversation entity is selected just for this capture. It
cannot run an intent, call an LLM, or change a device. The prior hardware
selection is restored even if capture fails or is interrupted.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import sys
import wave

from configure import WebSocket, http_json
from deploy_router import RECORDING

SELECTORS=('select.home_assistant_voice_096648_assistant',
           'select.home_assistant_voice_096648_assistant_2')
DEVICE_ID='cc6254926e3770b5d9b833ba3bc043ae'


def private_json(path: Path, data: dict) -> None:
    descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w',encoding='utf-8') as stream:
        json.dump(data,stream,ensure_ascii=False,indent=2)
        stream.write('\n')


def parse_args():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',required=True)
    parser.add_argument('--output',required=True,help='New .wav path; existing files are never overwritten.')
    parser.add_argument('--expected',required=True,help='Phrase to say; stored only beside the recording.')
    parser.add_argument('--timeout',type=float,default=30)
    parser.add_argument('--device-id',default=DEVICE_ID)
    args=parser.parse_args()
    if not 1 <= args.timeout <= 60: parser.error('--timeout must be between 1 and 60 seconds')
    output=Path(args.output).expanduser().resolve()
    if output.suffix.lower()!='.wav': parser.error('--output must end in .wav')
    if output.exists() or output.with_suffix('.json').exists(): parser.error('Refusing to overwrite an existing recording')
    return args,output


def main():
    args,output=parse_args()
    token=os.environ['HOME_ASSISTANT_TOKEN']
    states=http_json(args.url,token,'GET','/api/states')
    selection={state['entity_id']:state['state'] for state in states if state['entity_id'] in SELECTORS}
    if set(selection)!=set(SELECTORS): raise RuntimeError('Expected Voice assistant selectors were not found')
    ws=WebSocket(args.url,token,True)
    pipelines=ws.command({'type':'assist_pipeline/pipeline/list'})['pipelines']
    if not any(p['name']==RECORDING for p in pipelines): raise RuntimeError('The isolated recording pipeline is not configured')
    try:
        for entity_id in SELECTORS:
            http_json(args.url,token,'POST','/api/services/select/select_option',{'entity_id':entity_id,'option':RECORDING})
        capture_id=ws.next_id; ws.next_id+=1
        ws._send_json({'id':capture_id,'type':'assist_pipeline/device/capture','device_id':args.device_id,'timeout':args.timeout})
        while True:
            response=ws._recv_json()
            if response.get('id')==capture_id and not response.get('success',False): raise RuntimeError('Capture rejected: '+str(response))
            if response.get('id')==capture_id and response.get('success',False): break
        print('Recording is armed. Wake the Voice hardware and say exactly: '+args.expected,flush=True)
        chunks=[];audio_format=None;overflow=False
        while True:
            event=ws.event(capture_id)
            if event.get('type')=='audio':
                current=(event['rate'],event['width'],event['channels'])
                if audio_format and current!=audio_format: raise RuntimeError('Audio format changed mid-capture')
                audio_format=current; chunks.append(base64.b64decode(event['audio'],validate=True))
            elif event.get('type')=='end': overflow=bool(event.get('overflow')); break
        if overflow: raise RuntimeError('Capture queue overflowed; recording discarded')
        if not chunks or not audio_format: raise RuntimeError('No microphone audio was captured')
        output.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        descriptor=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(descriptor,'wb') as raw, wave.open(raw,'wb') as wav:
            rate,width,channels=audio_format
            wav.setnchannels(channels); wav.setsampwidth(width); wav.setframerate(rate); wav.writeframes(b''.join(chunks))
        private_json(output.with_suffix('.json'),{'expected':args.expected,'device_id':args.device_id,
            'sample_rate':audio_format[0],'sample_width':audio_format[1],'channels':audio_format[2],
            'bytes':sum(map(len,chunks)),'pipeline':RECORDING})
        print('Captured '+str(output),flush=True)
    finally:
        for entity_id,option in selection.items():
            try: http_json(args.url,token,'POST','/api/services/select/select_option',{'entity_id':entity_id,'option':option})
            except Exception as error:
                print('CRITICAL: could not restore '+entity_id+': '+str(error),file=sys.stderr)
                raise


if __name__=='__main__': main()
