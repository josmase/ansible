# Mergerfs disk maintenance

`mergerfs_disk_maintenance.yml` performs a full maintenance pass over the nine
physical data disks passed through to storage VM 101. It stops RustFS and NFS,
unmounts the full pool, starts all nine SMART extended tests concurrently,
then runs all nine forced read-only ext4 checks concurrently. It does not
replace disks.

Run from the Ansible jumphost during an approved maintenance window, from
`~/repo/ansible/ansible`:

```sh
ansible-playbook playbooks/maintenance/mergerfs_disk_maintenance.yml \
  --limit storage_servers \
  -e mergerfs_maintenance_window_confirmed=true \
  -e 'mergerfs_maintenance_window_id=CHANGE-123'
```

The longest known SMART extended test estimate is about 23.5 hours for one
large drive. Check the estimates for all nine drives and book enough outage
time for the slowest test, filesystem checks, and recovery validation. The
playbook polls for up to 48 hours for SMART tests and 72 hours for ext4 checks.

If SMART reports a failure, or any new kernel I/O error appears, the play aborts
with the pool unmounted and RustFS/NFS stopped. Do not remount a suspect branch.
This is intentional because this plan excludes disk replacement.

If an ext4 read-only check reports errors, the play aborts before remounting.
Before any repair, preserve and verify every readable non-media file on each
affected branch to independent storage. Movies and series are intentionally
excluded because they can be re-fetched. This exclusion applies only to the
exact pool-relative trees `files/movies/` and `files/series/`; do not exclude
other paths based on names or file types. The excluded media is at risk if its
disk fails, so this plan cannot promise zero loss for that data.

Measure the filtered backup size first; do not assume the full known 13 TiB
branch size is required. The current mergerfs pool is not independent backup
storage and has only about 6.4 TiB free. Use storage outside this pool. With the
pool offline, mount each source branch read-only without journal replay, copy
its protected contents while preserving ownership, ACLs, xattrs, hard links,
and sparse files, then verify a checksummed manifest against the source. Keep
per-branch logs of unreadable files. If any protected file cannot be copied and
verified, or the destination is not independent, stop: do not repair or return
the affected branch to service. Do not copy from the merged pool, which can
read from a different branch and obscure provenance.

After the copy is verified, rerun in a scheduled window and supply explicit
per-branch evidence and approval for every branch with errors:

```yaml
mergerfs_repair_approved: true
mergerfs_verified_backups:
  - source: /dev/mapper/automapped_<uuid-prefix>
    reference: "<independent destination; checksummed manifest and verification log>"
    verified: true
    excluded_paths:
      - files/movies/
      - files/series/
    protected_data_complete: true
```

The procedure will reject evidence that omits the exact media exclusions or
does not attest that all protected data was copied and verified.

A repair uses `e2fsck -f -y` only for branches found inconsistent by the
read-only pass, then requires a clean read-only recheck. Any failed gate keeps
the pool offline for investigation. After all checks pass, verify RustFS
readiness and Proxmox NFS availability. Restore or reconcile the LINSTOR RustFS
remote if needed, create a fresh LINSTOR backup, and verify it before resuming
K3s upgrades.
