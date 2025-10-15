#!/bin/bash
SCRIPT_DIR={{ docker_script_dir }}

source "${SCRIPT_DIR}/common.sh"
eval "docker compose ${DOCKER_FILE_COMMAND} pull"