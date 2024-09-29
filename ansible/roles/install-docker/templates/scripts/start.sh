#!/bin/bash
SCRIPT_DIR={{ docker_script_dir }}

source "${SCRIPT_DIR}/common.sh"
echo "$DOCKER_FILE_COMMAND"
eval "podman compose ${DOCKER_FILE_COMMAND} up -d --remove-orphans"

podman image prune -fa
podman volume prune -f