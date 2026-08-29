#!/bin/bash
set -euo pipefail

# staleFileHandleHandler.sh
# ==========================
# Hourly NFS stale-handle / hung-mount handler for Docker hosts.
#
# Detects two NFS failure modes on the node:
#   1. Stale file handles reported by `df` (dentry cache referencing
#      deleted/renamed files on a shared export)
#   2. Hung NFS mounts (mount point unresponsive)
#
# On detection it:
#   - force-unmounts (lazy) the affected mount so it can be remounted cleanly
#   - drops the VFS dentry/inode cache so clients re-fetch from the server
#
# This is the lightweight hourly companion to the 5-minute nfsStaleRecovery
# agent (see nfsStaleRecovery.sh).

STORAGE_DIR={{ docker_storage_dir }}

log() {
    echo "[$(date -Iseconds)] $*"
}

# Drop the VFS dentry/inode cache to clear stale NFS handles.
drop_dentry_cache() {
    if [ -w /proc/sys/vm/drop_caches ]; then
        echo 2 > /proc/sys/vm/drop_caches 2>/dev/null
    fi
}

# Detect a hung mount: the mount point itself is unresponsive.
check_hung_mount() {
    local mount_point="$1"
    local result
    result=$(timeout 5 ls -d "$mount_point" 2>&1) || true
    echo "$result" | grep -qE "Stale file handle|Input/output error|Connection timed out|Host is down"
}

# Detect stale handles reported by df.
check_df_stale() {
    df 2>&1 | grep -q 'Stale file handle'
}

found_issue=false

# 1. Stale handles reported by df
if check_df_stale; then
    found_issue=true
    log "STALE HANDLES: df reports stale file handle(s). Dropping dentry cache."
    drop_dentry_cache || log "FAILED: could not drop dentry cache"
fi

# 2. Hung mount at the storage dir
if check_hung_mount "$STORAGE_DIR"; then
    found_issue=true
    log "HUNG MOUNT: ${STORAGE_DIR} is unresponsive. Force-unmounting."
    if umount -f -l "$STORAGE_DIR" 2>/dev/null; then
        log "RECOVERED: force-unmounted ${STORAGE_DIR}. Remounting."
        mount "$STORAGE_DIR" 2>/dev/null || mount -a 2>/dev/null || true
    else
        log "FAILED: could not unmount ${STORAGE_DIR} (may need node reboot)"
    fi
fi

if [ "$found_issue" = false ]; then
    log "No stale NFS handles or hung mounts found"
fi
