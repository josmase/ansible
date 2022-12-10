#!/bin/bash
SCRIPT_DIR={{ SCRIPT_DIR }}

source "${SCRIPT_DIR}/common.sh"
eval "docker-compose ${DOCKER_FILE_COMMAND} pull"