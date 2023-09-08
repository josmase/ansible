#!/bin/bash
#Exit on error
set -e

export PASSWORD=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)
export USER=admin

sudo apt-get update && sudo apt-get install apache2-utils

echo $USER > auth/credentials
echo $PASSWORD >> auth/credentials

export CREDENTIALS=$(htpasswd -nb $USER $PASSWORD | openssl base64)

echo $CREDENTIALS
echo "Put the above secret inteo secret-dashboard. Then press any key to continue"
read -n 1 -s

helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade --install \
  --create-namespace --namespace=staging  \
  --values=values.yaml \
  --wait traefik traefik/traefik 

kubectl apply -f default-headers.yaml -f dashboard

   
