#!/bin/bash
script_dir={{ script_dir }}

source "${script_dir}/common.sh"
echo "$file_command"
eval "docker compose ${file_command} up -d --remove-orphans"

docker image prune -fa
docker volume prune -f