#!/bin/bash
BACKUP_PATH={{ docker_storage_dir }}/backups
APPDATA_PATH={{ docker_data_dir }}
SCRIPT_DIR={{ docker_script_dir }}
DOWNLOADS_DIR={{ docker_storage_dir }}/downloads

echo =====================  $(date)  ==============================================
source "${SCRIPT_DIR}/update.sh"
source "${SCRIPT_DIR}/stop.sh"

#Create a backup of all appdata
TIME=$(date +%Y-%m-%d_%T)
FILENAME=appdata-$TIME.tar.gz
tar -cvpzf "${BACKUP_PATH}/${FILENAME}" "${APPDATA_PATH}"

#Remove backupos that are older than 1 week
find "${BACKUP_PATH}" -type f -name "appdata-*.tar.gz" -mtime +7 -exec rm {} \;

source "${SCRIPT_DIR}/start.sh"
