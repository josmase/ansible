#!/bin/bash
set -euo pipefail

# nfsStaleRecovery.sh
# ====================
# Node-level NFS recovery agent for Docker hosts (media service).
#
# Runs every 5 minutes via systemd timer. Scans for two NFS failure modes:
#   1. Hung NFS mounts (mount point unresponsive)
#        -> force-unmount to unblock containers stuck on the mount
#   2. Stale NFS file handles (dentry cache referencing deleted/renamed files)
#        -> drop the VFS dentry/inode cache so clients re-fetch from the server
#
# On detecting an issue it recovers and sends a Gotify alert so the failure is
# visible even though the host is Docker-only (no Prometheus).
#
# This is the fast (5-min) companion to the hourly staleFileHandleHandler.

STORAGE_DIR={{ docker_storage_dir }}
GOTIFY_URL={{ nfs_alert_gotify_url | default('https://gotify.local.hejsan.xyz/message') }}
GOTIFY_TOKEN={{ vault_gotify_token | default('') }}
GOTIFY_PRIORITY={{ nfs_alert_gotify_priority | default(5) }}

log() {
    echo "[$(date -Iseconds)] $*"
}

# Send a Gotify notification. Best-effort; never fails the run.
notify() {
    local title="$1"
    local message="$2"
    if [ -n "$GOTIFY_TOKEN" ]; then
        curl -fsS -X POST "$GOTIFY_URL" \
            -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"title\": \"${title}\", \"message\": \"${message}\", \"priority\": ${GOTIFY_PRIORITY}}" \
            >/dev/null 2>&1 || log "WARNING: failed to send Gotify notification"
    else
        log "WARNING: GOTIFY_TOKEN not set; skipping notification"
    fi
}

# Detect a hung NFS mount: the mount point itself is unresponsive.
check_hung_mount() {
    local mount_point="$1"
    local result
    result=$(timeout 5 ls -d "$mount_point" 2>&1) || true
    echo "$result" | grep -qE "Stale file handle|Input/output error|Connection timed out|Host is down"
}

# Detect stale file handles within a mount: entries below the mount point can't
# be stat'd. Uses `find` bounded by depth and timeout, capturing only stderr.
check_stale_handles() {
    local mount_point="$1"
    local err
    err=$(timeout 20 find "$mount_point" -maxdepth 3 2>&1 1>/dev/null | head -50) || true
    echo "$err" | grep -qE "Stale file handle|Input/output error"
}

# Drop the VFS dentry/inode cache to clear stale NFS handles.
drop_dentry_cache() {
    if [ -w /proc/sys/vm/drop_caches ]; then
        echo 2 > /proc/sys/vm/drop_caches 2>/dev/null
    fi
}

# Get the list of NFS mount points on this host.
get_nfs_mounts() {
    grep -E " nfs(4)? " /proc/mounts 2>/dev/null | awk '{print $2}' || true
}

found_issue=false
issues=""

# 1. Hung mount scan
for mount_point in $(get_nfs_mounts); do
    if check_hung_mount "$mount_point"; then
        found_issue=true
        issues="${issues}\n  - HUNG MOUNT: ${mount_point}"
        log "HUNG MOUNT: ${mount_point}"
        if umount -f -l "$mount_point" 2>/dev/null; then
            log "RECOVERED: force-unmounted ${mount_point}. Remounting."
            mount "$mount_point" 2>/dev/null || mount -a 2>/dev/null || true
        else
            log "FAILED: could not unmount ${mount_point} (may need node reboot)"
        fi
    fi
done

# 2. Stale handle scan (deep, bounded)
for mount_point in $(get_nfs_mounts); do
    if check_stale_handles "$mount_point"; then
        found_issue=true
        issues="${issues}\n  - STALE HANDLES: ${mount_point}"
        log "STALE HANDLES: ${mount_point}"
        if drop_dentry_cache; then
            log "RECOVERED: dropped dentry/inode cache"
        else
            log "FAILED: could not drop dentry cache"
        fi
    fi
done

# 3. Storage dir sanity (the media containers bind-mount this)
if check_hung_mount "$STORAGE_DIR"; then
    found_issue=true
    issues="${issues}\n  - STORAGE DIR UNRESPONSIVE: ${STORAGE_DIR}"
    log "STORAGE DIR UNRESPONSIVE: ${STORAGE_DIR}"
fi

if [ "$found_issue" = true ]; then
    notify "NFS stale mount detected on $(hostname)" "Issues found and recovery attempted:${issues}"
else
    log "No NFS issues found"
fi
