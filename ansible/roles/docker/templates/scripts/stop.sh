#!/bin/bash
SCRIPT_DIR={{ script_dir }}


source "${SCRIPT_DIR}/common.sh"
eval "docker-compose ${DOCKER_FILE_COMMAND} down --remove-orphans"