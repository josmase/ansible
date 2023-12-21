#!/bin/bash
#Exit on error
set -e

helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update 
helm upgrade --install \
  --values=values.yaml \
  --wait vault hashicorp/vault 
