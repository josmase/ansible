#!/bin/bash
script_dir={{ script_dir }}


source "${script_dir}/common.sh"
eval "docker-compose ${file_command} down --remove-orphans"