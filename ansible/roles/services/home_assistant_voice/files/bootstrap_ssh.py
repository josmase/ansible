#!/usr/bin/env python3
"""Configure the installed SSH add-on through HA's authenticated Supervisor WS."""
import argparse
import os
from pathlib import Path
from configure import WebSocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True)
    parser.add_argument('--public-key-file', required=True)
    parser.add_argument('--port', type=int, default=2222)
    args = parser.parse_args()
    key = Path(args.public_key_file).read_text().strip()
    if not key.startswith(('ssh-rsa ', 'ssh-ed25519 ', 'ecdsa-sha2-')) or '\n' in key:
        raise ValueError('Expected one SSH public key')
    ws = WebSocket(args.url, os.environ['HOME_ASSISTANT_TOKEN'], True)
    def api(endpoint, method='get', data=None):
        command = {'type':'supervisor/api', 'endpoint':endpoint, 'method':method, 'timeout':60}
        if data is not None:
            command['data'] = data
        return ws.command(command)
    addons = api('/addons')['addons']
    if not any(a['slug'] == 'core_ssh' for a in addons):
        api('/addons/core_ssh/install', 'post')
    info = api('/addons/core_ssh/info')
    options = info['options']
    keys = options.get('authorized_keys', [])
    wanted_keys = keys if key in keys else keys + [key]
    network = {**(info.get('network') or {}), '22/tcp':args.port}
    wanted = {**options, 'authorized_keys':wanted_keys, 'password':''}
    changed = options != wanted or info.get('network') != network or info.get('boot') != 'auto'
    if changed:
        api('/addons/core_ssh/options', 'post', {'options':wanted, 'network':network, 'boot':'auto'})
        api('/addons/core_ssh/restart' if info['state'] == 'started' else '/addons/core_ssh/start', 'post')
    elif info['state'] != 'started':
        api('/addons/core_ssh/start', 'post'); changed = True
    print('changed' if changed else 'ok')


if __name__ == '__main__':
    main()
