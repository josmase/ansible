#!/bin/bash
SCRIPT_DIR={{ docker_script_dir }}


source "${SCRIPT_DIR}/common.sh"
eval "podman compose ${DOCKER_FILE_COMMAND} down --remove-orphans"