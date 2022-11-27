#!/bin/bash
#Exit on error
set -e

kubectl apply -f ./namespace.yaml
helm repo add jetstack https://charts.jetstack.io && helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.crds.yaml
helm install cert-manager jetstack/cert-manager --namespace cert-manager --values=values.yaml

kubectl apply -f issuers/secret-cf-token.yaml

#Staging only
kubectl apply  -f issues/letesencrypt-staging.yaml  -f certificates/staging/local-hejsan-xyz.yaml
kubectl get challenges


   