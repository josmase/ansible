#!/bin/bash
set -euo pipefail
SCRIPT_DIR={{ docker_script_dir }}
STORAGE_DIR={{ docker_storage_dir }}

source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Pre-flight NFS mount health check
# ---------------------------------------------------------------------------
# The media containers bind-mount ${STORAGE_DIR} (an NFS mount). If the mount
# is stale/hung, `docker compose up` will start containers that immediately
# fail with "Stale file handle" / "Input/output error". Check the mount first
# and attempt recovery before starting anything.
check_nfs_mount() {
    local result
    result=$(timeout 5 ls -d "$STORAGE_DIR" 2>&1) || true

    if echo "$result" | grep -qE "Stale file handle|Input/output error|Connection timed out|Host is down"; then
        echo "[$(date -Iseconds)] STALE: ${STORAGE_DIR} is stale/hung. Attempting recovery..."
        if umount -f -l "$STORAGE_DIR" 2>/dev/null; then
            echo "[$(date -Iseconds)] RECOVERED: force-unmounted ${STORAGE_DIR}. Remounting..."
            mount "$STORAGE_DIR" 2>/dev/null || mount -a 2>/dev/null || true
        else
            echo "[$(date -Iseconds)] FAILED: could not unmount ${STORAGE_DIR}. Aborting start."
            exit 1
        fi
    elif [ -z "$result" ]; then
        echo "[$(date -Iseconds)] WARNING: ${STORAGE_DIR} is empty or inaccessible"
    else
        echo "[$(date -Iseconds)] OK: ${STORAGE_DIR} is healthy"
    fi
}

check_nfs_mount

echo "$DOCKER_FILE_COMMAND"
eval "docker compose ${DOCKER_FILE_COMMAND} up -d --remove-orphans"

docker image prune -fa
docker volume prune -fa
docker system prune -fa