#!/usr/bin/env python3
"""Read-only preflight: never bootstrap SSH or install before validating inputs."""
import argparse
import json
from pathlib import Path
from deploy_router import release_fingerprint, validate_acceptance


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--release-manifest',required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--model',required=True)
    parser.add_argument('--acceptance-file',default='')
    parser.add_argument('--promote',type=lambda s:s.lower()=='true',default=False)
    args=parser.parse_args()
    release=json.loads(Path(args.release_manifest).read_text())
    release_fingerprint(release)
    if args.promote:
        validate_acceptance(args.acceptance_file,args.sha256,args.model,release)
    print('Release manifest valid; '+('promotion accepted' if args.promote else 'staging only'))


if __name__=='__main__':
    main()
