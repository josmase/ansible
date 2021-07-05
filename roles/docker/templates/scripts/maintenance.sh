#!/bin/bash
backup_path={{ storage_dir }}/backups
appdata_path={{ appdata_path }}
script_dir={{ script_dir }}
downloads_dir={{ storage_dir }}/downloads

echo =====================  $(date)  ==============================================
source "${script_dir}/update.sh"
source "${script_dir}/down.sh"

rsync -aP --delete "${appdata_path}" "${backup_path}"

#Grafana requires UID and GUID 472 since the container doesn't support setting them. This has to be done before starting it.
chown -R 472:472 "${appdata_path}/grafana"

source "${script_dir}/start.sh"

#These are to fix permission errors caused by restarting somehting that is writing to downloads. Not sure what.
chown -R {{ main_username }}:{{ main_groupname }} "${downloads_dir}"
chmod -R 755 "${downloads_dir}"

