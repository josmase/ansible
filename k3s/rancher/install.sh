#!/bin/bash
#Exit on error
set -e

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable


kubectl apply -f ./namespace.yaml
helm install rancher rancher-stable/rancher --namespace cattle-system -f values.yaml
