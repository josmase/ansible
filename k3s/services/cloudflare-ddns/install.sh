#!/bin/bash

kubectl create secret generic cloudflare-ddns --from-env-file=secrets/secrets.env
kubectl apply -f deployment.yaml