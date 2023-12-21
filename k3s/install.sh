#!/bin/bash
#Exit on error
set -e
scp ubuntu@192.168.0.201:~/.kube/config ~/.kube/config

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash