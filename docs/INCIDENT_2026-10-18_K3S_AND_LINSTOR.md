# Incident: Kubernetes API timeouts and LINSTOR storage outage

**Date:** 2026-10-18  
**Status:** Unresolved; cluster API and storage are still intermittent.  
**Data handling:** No etcd reset, datastore restore, or persistent-volume deletion was performed. Log files and archived journal entries were cleaned only. No data loss was observed during this work, but storage integrity has not been independently verified.

## Symptoms

- Requests to the Kubernetes API from the jumphost timed out or returned `ServiceUnavailable`.
- Master logs showed etcd peer TLS handshake timeouts, failed linearizable `ReadIndex` calls, `etcdserver: no leader`, and API handler deadlines. A node lookup stalled for about 10 seconds waiting for raft agreement.
- At 21:15 CEST, master 201 reported failed etcd readiness; requests to masters 202 and 203 timed out, and SSH to master 203 stalled before its banner. K3s had restarted twice on 201 and three times on 202. The cluster was not stable at the last check.

## Findings

1. **Log growth and disk pressure:** Master 201's root filesystem had previously reached 100% use. Its syslog and rotated syslog files had grown to multiple GiB, and etcd defragmentation failed with `no space left on device`. Log cleanup restored space; the most recent reading on 201 was 9.7 GiB free (56% used). Masters 202 and 203 also had multi-GiB syslog files, which were truncated, and archived journals were vacuumed.
2. **Control-plane instability:** The three masters repeatedly lost etcd peer connectivity during this investigation. Proxmox reboots temporarily brought API endpoints back, and one snapshot showed all seven Kubernetes nodes Ready with fresh leases and all three `/readyz` endpoints returning `ok`. That state did not persist; subsequent etcd readiness and API requests failed again.
3. **LINSTOR/DRBD outage:** The LINSTOR controller was in `CrashLoopBackOff` with 246 restarts; the LINSTOR CSI controller had 1,447 restarts and multiple containers in `CrashLoopBackOff`. The `linstor-controller` service had no endpoints, and all four `LinstorSatellite` objects reported `Connected=False`. The previous controller log ended with `Database initialization error` (report `6AD519AD-00000-000000`, exit status 20). The available container log did not expose the underlying database error.
4. **Worker I/O stalls:** Worker 204 had load average near 193 and high I/O pressure; 200 DRBD kernel threads were in uninterruptible `D` state. A sampled DRBD receiver stack was waiting in `drbd_flush_after_epoch`/`receive_Barrier`, and `dumpe2fs -h /dev/drbd1147` was blocked in `blkdev_fsync`. Worker 206 had load average near 130, 130 `D`-state threads, and high I/O pressure; a sampled thread was waiting in `jbd2` for DRBD volume `drbd1138`. These observations establish blocked DRBD I/O, but do not establish the original cause of the etcd failures.
5. **Workload impact:** The API listed failing or unhealthy pods, including the LINSTOR controller/CSI pods and application pods. A Ready node status alone did not indicate that storage-backed workloads were healthy.

The LINSTOR failure and DRBD stalls are a serious storage-plane outage and may contribute to workload and API latency. Their relationship to the etcd peer timeouts is not proven. The LINSTOR controller's database initialization error remains the key missing diagnostic.

## Recovery actions taken

- Cleaned oversized syslog files and vacuumed archived systemd journal entries; no application logs or persistent-volume data were deleted.
- Applied the Kubernetes node log-rotation setup on masters 201–203. The change is in commits `4cad743`, `eed12a7`, and `ded72d7`.
- Rebooted master 201 through Proxmox. Graceful reboot of 202 timed out, so it was hard-reset and started again. Graceful reboot of 203 timed out, so it was hard-reset. A later hard reset of 201 restored SSH and briefly restored API readiness. No etcd reset/restore command was run.
- API readiness and all-node Ready status were observed temporarily, but follow-up checks showed renewed etcd readiness failures and API timeouts.

## Follow-up

- Restore stable etcd quorum and verify `/readyz` and node leases across all masters over a sustained period.
- Obtain the detailed LINSTOR report for `6AD519AD-00000-000000`; restore controller database access before attempting changes to LINSTOR resources or DRBD volumes.
- Reconnect the LINSTOR satellites and verify DRBD resource state and persistent-volume integrity before considering worker reboots.
- Re-run the Ansible hygiene playbook on every target node after connectivity is stable. The previous run timed out waiting for privilege escalation on worker 204.

