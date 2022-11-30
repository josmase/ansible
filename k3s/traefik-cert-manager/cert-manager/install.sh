#!/bin/bash
#Exit on error
set -e

helm repo add jetstack https://charts.jetstack.io && helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.crds.yaml
helm upgrade --install \
  --create-namespace --namespace=cert-manager \
  --values=values.yaml \
  --wait cert-manager jetstack/cert-manager

kubectl apply -f issuers/secret-cf-token.yaml

#Dont create the prod cert before validating that the staging one is working
kubectl apply  -f issuers/letsencrypt-staging.yaml -f issuers/letsencrypt-production.yaml -f certificates/staging/local-hejsan-xyz.yaml
kubectl get challenges


   