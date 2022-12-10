#!/bin/bash
SCRIPT_DIR={{ SCRIPT_DIR }}

source "${SCRIPT_DIR}/common.sh"
echo "$DOCKER_FILE_COMMAND"
eval "docker-compose ${DOCKER_FILE_COMMAND} up -d --remove-orphans"

docker image prune -fa
docker volume prune -f