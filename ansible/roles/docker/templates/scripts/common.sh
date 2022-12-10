DOCKER_COMPOSE_DIR={{ docker_compose_dir }}
DOCKER_FILE_COMMAND=""

for compose_file in $DOCKER_COMPOSE_DIR/*.yml; do
    DOCKER_FILE_COMMAND="${DOCKER_FILE_COMMAND} -f ${compose_file}"
done