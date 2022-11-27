#!/bin/bash
#Exit on error
set -e

export SHA=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)
export USER=admin

mkdir -p ./auth
echo $USER > ./auth/registry-creds.txt
echo $SHA >> ./auth/registry-creds.txt

docker run --entrypoint htpasswd httpd:2 -Bbn admin $SHA > ./auth/htpasswd

helm repo add twuni https://helm.twun.io && helm repo update
helm install -f values.yaml docker-registry twuni/docker-registry --set secrets.htpasswd=$(cat ./auth/htpasswd)
kubectl rollout status deploy/docker-registry
kubectl apply -f ./ingress.yaml