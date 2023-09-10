#!/bin/bash
#Exit on error
set -e
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade --install \
  --create-namespace --namespace=staging  \
  --values=values-staging.yaml \
  --wait traefik-staging traefik/traefik 

helm upgrade --install \
  --create-namespace --namespace=production  \
  --values=values-prod.yaml \
  --wait traefik-production traefik/traefik 

   
