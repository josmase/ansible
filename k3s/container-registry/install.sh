#!/bin/bash
#Exit on error
set -e

export SHA=$(head -c 16 /dev/urandom | shasum | cut -d " " -f 1)
export USER=admin

#mkdir -p ./auth
#echo $USER > ./auth/registry-creds.txt
#echo $SHA >> ./auth/registry-creds.txt

#docker run --entrypoint htpasswd httpd:2 -Bbn admin $SHA > ./auth/htpasswd

helm upgrade --install \
  --values=values.yaml \
  --set secrets.htpasswd=$(cat ./auth/htpasswd) \
  --set dockerconfigjson.password=$(cat ./auth/htpasswd) \
  --wait container-registry chart