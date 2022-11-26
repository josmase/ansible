docker_compose_dir={{ docker_compose_dir }}
file_command=""

for compose_file in $docker_compose_dir/*.yml; do
    file_command="${file_command} -f ${compose_file}"
done