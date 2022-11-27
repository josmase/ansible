#!/bin/bash
#Exit on error
set -e

export SHA=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)
export USER=admin

mkdir -p ./auth
echo $USER > ./auth/registry-creds.txt
echo $SHA >> ./auth/registry-creds.txt

docker run --entrypoint htpasswd httpd:2 -Bbn admin $SHA > ./auth/htpasswd

cat ./auth/htpasswd
echo "Put the above secret inteo secret-dashboard. Then press any key to continue"
read -n 1 -s

kubectl apply -f ./namespace.yaml

helm repo add traefik https://helm.traefik.io/traefik && helm repo update
helm upgrade --install \
  --create-namespace --namespace=traefik  \
  --values=values.yaml \
  --wait traefik traefik/traefik 

kubectl apply -f default-headers.yaml -f dashboard/secret-dashboard.yaml -f dashboard/middleware.yaml -f ingress.yaml

   