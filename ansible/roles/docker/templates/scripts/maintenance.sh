#!/bin/bash
BACKUP_PATH={{ storage_dir }}/backups
APPDATA_PATH={{ appdata_path }}
SCRIPT_DIR={{ script_dir }}
DOWNLOADS_DIR={{ storage_dir }}/downloads

echo =====================  $(date)  ==============================================
source "${SCRIPT_DIR}/update.sh"
source "${SCRIPT_DIR}/stop.sh"

#Create a backup of all appdata
TIME=$(date +%Y-%m-%d_%T)
FILENAME=appdata-$TIME.tar.gz
tar -cvpzf "${BACKUP_PATH}/${FILENAME}" "${APPDATA_PATH}"

#Remove backupos that are older than 1 week
find "${BACKUP_PATH}" -type f -name "appdata-*.tar.gz" -mtime +7 -exec rm {} \;


#Grafana requires UID and GUID 472 since the container doesn't support setting them. This has to be done before starting it.
#chown -R 472:472 "${APPDATA_PATH}/grafana"

source "${SCRIPT_DIR}/start.sh"

#These are to fix permission errors caused by restarting somehting that is writing to downloads. Not sure what.
chown -R {{ main_username }}:{{ main_groupname }} "${DOWNLOADS_DIR}"
chmod -R 755 "${DOWNLOADS_DIR}"

#There is an issue with EasyAudioEncoder and removing all codecs and restarting solves it for a while.
rm -r "${APPDATA_PATH}/plex/Library/Application Support/Plex Media Server/Codecs/*" && docker restart plex

