#!/bin/bash
#Exit on error
set -e

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable && helm repo update

helm upgrade --install \
  --create-namespace  --namespace cattle-system \
  --values=values.yaml \
  --wait rancher rancher-stable/rancher

kubectl -n cattle-system rollout status deploy/rancher


#Reset password
#kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
