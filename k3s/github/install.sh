#!/bin/bash
#Exit on error
set -e

TOKEN=$(cat ./secret/token)

helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller && helm repo update
helm upgrade --install \
  --namespace actions-runner-system --create-namespace\
  --set=authSecret.create=true \
  --set=authSecret.github_token="${TOKEN}" \
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller

kubectl apply -f runners/downloader.yaml