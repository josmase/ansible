# LINSTOR storage protection and recovery gates

This runbook describes the controls deployed from the Flux repository and the
conditions required before snapshot or backup automation is allowed to run.
The controls fail closed: an unavailable API, LINSTOR satellite, storage pool,
volume-group metadata area, or backup chain holds the corresponding producer.

## Automated controls

- The snapshot reconciler only considers active PVCs using the canonical
  `linstor` StorageClass. It requires at least three connected, diskful
  satellites, at least 20% free in each LINSTOR thin pool, three healthy
  UpToDate replicas for the source, and adequate VG metadata headroom.
- Reconciliation snapshots use `linstor-snapshot-prunable` (`Delete`). Managed
  recovery snapshots use `linstor-snapshot` (`Retain`) and are excluded from
  automatic retention counts and deletion.
- Retention stays at 12 hourly, 7 daily, and 4 weekly snapshots. The oldest
  prunable snapshot is removed before creating a replacement to avoid a
  temporary extra snapshot LV. A pending or failed managed snapshot stops the
  next run.
- LINSTOR backup schedules are reconciled only after both storage and RustFS
  backup gates have been healthy for 24 hours. The legacy Radarr schedule is
  disabled while the gate is closed. CNPG volume-snapshot backups use the same
  gate; its native ScheduledBackup remains suspended.
- Alerts cover protection-gate failures, etcd leadership, master memory, and
  sustained node disk saturation. See the `linstor-control-plane-protection`
  PrometheusRule group in Flux.
- Ansible validation checks at least 64 KiB of free VG metadata area per worker.
  This is a minimum operational floor, separate from the dynamically calculated
  headroom needed for the active snapshot set.
- The Ansible K3s node configuration contains an explicit Go memory-limit
  setting, and the DRBD-aware maintenance message is configured separately.
  Use [K3S master memory guidance](K3S_MASTER_MEMORY.md) to review heap and
  watch counts before changing that limit. The incident's Proxmox I/O caps and
  etcd TLS observations remain investigation items; do not tune VM disk limits
  or replace etcd member state without disk traces and verified member history.

## Calibrate VG metadata before resuming producers

The Flux ConfigMap `linstor-vg-metadata-budget` intentionally has
`calibrated: "false"`. Leave producers held until an operator measures actual
metadata use on every diskful worker after the current LVM/Piraeus configuration
is deployed.

1. Confirm the recovery gates below, then select a disposable test volume with
   three healthy replicas. Do not use a production PVC for calibration.
2. Record `vg_mda_size` and `vg_mda_free` from `vgs` on each worker before the
   test. Create one disposable snapshot and record the values again after the
   snapshot has completed. Remove the disposable snapshot through the supported
   CSI lifecycle and record the final values.
3. Use the largest observed metadata consumption per snapshot LV across the
   workers as `bytesPerSnapshotLv`. Set `snapshotsPerPvcPerRun` to the maximum
   snapshots the scheduled run can create for one PVC (normally 2 at the daily
   or weekly boundary). Keep `safetyMultiplier` at 2 or higher. The resulting
   required free MDA is `max(floorBytes, activePVCs × bytesPerSnapshotLv ×
   snapshotsPerPvcPerRun × safetyMultiplier)`.
4. Update the ConfigMap in Git and set `calibrated: "true"` only with the
   measured values recorded in the change. Reconcile the Flux overlay. The
   independent 24-hour healthy timer starts only after the gate sees that
   configuration and all other checks pass.
5. If measurements vary materially by worker or the MDA headroom is insufficient,
   leave calibration false and resolve the LVM/VG sizing issue first.

## Recovery gates

Before changing the metadata calibration or allowing automated producers to
resume, confirm and record:

1. All intended worker nodes are Ready and at least three diskful LINSTOR
   satellites report `Available=True` with positive capacity.
2. Each LINSTOR thin pool has at least 20% free capacity, and every active source
   volume has three UpToDate replicas with established replication.
3. `vgs` reports sufficient free MDA on every diskful worker for the active
   snapshot set, as calculated by the calibrated budget.
4. RustFS is reachable and the LINSTOR backup remote lists restorable metadata
   for every locally shipped backup chain. A missing remote backup ID or a
   non-restorable chain keeps scheduled backups disabled; do not infer
   restoratability from object presence alone.
5. A LINSTOR database backup has been restored in a drill using the procedure
   documented for the deployed LINSTOR version. Record the backup identifier,
   restore steps, and result.
6. Kubernetes `/readyz` and etcd quorum are stable. Keep monitoring the gate
   status ConfigMap and the protection alerts through the full 24-hour green
   period.

## Stop and rollback

If CSI/API health worsens, a snapshot does not become ready, a backend deletion
does not complete, MDA headroom falls below the computed minimum, or a resource
mapping is ambiguous:

1. Set the snapshot reconciler suspended in Flux and keep the backup gate closed.
2. Do not clear finalizers or bulk-delete LINSTOR resources. Preserve the
   inventory, logs, gate ConfigMap, and before/after VG measurements.
3. Use only the supported VolumeSnapshot lifecycle or the deployed LINSTOR
   version's documented snapshot operation. Stop after each small batch and
   confirm Kubernetes snapshot/content, LINSTOR snapshot, and LV counts.
4. Revert sidecar tuning through Flux if it harms CSI or API health. Preserve
   `linstor-snapshot-prunable` while any VolumeSnapshotContent references it.

The gate and runbook changes do not themselves prove that memory usage will
improve. Measure master RSS/heap, etcd health, watch counts, VG MDA, thin-pool
headroom, and snapshot retry activity before and after rollout.
