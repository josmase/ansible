#!/bin/bash
#Exit on error
set -e

script_dir=$(dirname "$0")


# Check if exactly one parameter is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

# Read the parameter into a variable
environment="$1"

# Check if the parameter is either "staging" or "production"
if [ "$environment" != "staging" ] && [ "$environment" != "production" ]; then
    echo "Invalid environment. Allowed values are 'staging' or 'production'."
    exit 1
fi

helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade --install \
  --create-namespace --namespace=${environment}  \
  --values="${script_dir}/values-${environment}.yaml" \
  --wait traefik-${environment} traefik/traefik 
