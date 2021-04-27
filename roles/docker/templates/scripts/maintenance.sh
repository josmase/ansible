#!/bin/bash
backup_path={{ storage_dir }}/backups
appdat_path={{ appdata_path }}
script_dir={{ script_dir }}
downloads_dir={{ storage_dir }}/downloads

echo =====================  $(date)  ==============================================
source "${script_dir}}/}update.sh"
source "${script_dir}/down.sh"

#rsync -aP --delete "${appdat_path}" "${backup_path}"
#snapraid -c ../snapraid.conf sync

source "${script_dir}/start.sh"

chown -R {{ main_username }}:{{ main_groupname }} "${downloads_dir}"
chmod -R 755 "${downloads_dir}"