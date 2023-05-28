#!/bin/bash
#Exit on error
set -e

helm repo add jetstack https://charts.jetstack.io && helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.1/cert-manager.crds.yaml
helm upgrade --install \
  --create-namespace --namespace=cert-manager \
  --values=values.yaml \
  --wait cert-manager jetstack/cert-manager

kubectl delete secret cloudflare \
     -n cert-manager \
    --ignore-not-found

kubectl create secret generic cloudflare \
    -n cert-manager \
    --from-env-file='./auth/cf.token'

#Dont create the prod cert before validating that the staging one is working
kubectl apply  -f issuers -f certificates/staging/local-hejsan-xyz.yaml
kubectl get challenges


   