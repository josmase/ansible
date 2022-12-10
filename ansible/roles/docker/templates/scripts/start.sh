#!/bin/bash
SCRIPT_DIR={{ script_dir }}

source "${SCRIPT_DIR}/common.sh"
echo "$DOCKER_FILE_COMMAND"
eval "docker-compose ${DOCKER_FILE_COMMAND} up -d --remove-orphans"

docker image prune -fa
docker volume prune -f