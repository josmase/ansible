# Incident: Kubernetes API timeouts and LINSTOR storage outage

**Date:** 2026-10-18  
**Status:** Unresolved; etcd and API remain intermittent, and LINSTOR/DRBD storage is unavailable.  
**Data handling:** No etcd reset, datastore restore, or persistent-volume deletion was performed. Log files and archived journal entries were cleaned only. No data loss was observed during this work, but storage integrity has not been independently verified.

## Symptoms

- Requests to the Kubernetes API from the jumphost timed out or returned `ServiceUnavailable`.
- Master logs showed etcd peer TLS handshake timeouts, failed linearizable `ReadIndex` calls, `etcdserver: no leader`, and API handler deadlines. A node lookup stalled for about 10 seconds waiting for raft agreement.
- At 21:16 CEST, API readiness on 201 was refused and requests to 202 and 203 timed out. K3s on 201 was still activating with three restarts; 202 had also reached three restarts, and SSH to 203 stalled before its banner. The cluster was not stable at the last check.
- Later checks briefly showed `/readyz` succeeding on 201 and all seven nodes `Ready`, but this did not persist. By 21:38 CEST, 201 had reached 11 K3s restarts, 202 had one restart since its reset, SSH to 203 was timing out, and an etcd metrics sample on 202 showed `has_leader=0`. API requests hung again.

## Findings

1. **Log growth and disk pressure:** Master 201's root filesystem had previously reached 100% use. Its syslog and rotated syslog files had grown to multiple GiB, and etcd defragmentation failed with `no space left on device`. Log cleanup restored space; the most recent reading on 201 was 9.7 GiB free (56% used). Masters 202 and 203 also had multi-GiB syslog files, which were truncated, and archived journals were vacuumed.
2. **Control-plane instability:** The three masters repeatedly lost etcd peer connectivity during this investigation. Proxmox reboots temporarily brought API endpoints back, and one snapshot showed all seven Kubernetes nodes Ready with fresh leases and all three `/readyz` endpoints returning `ok`. That state did not persist; subsequent etcd readiness and API requests failed again.
3. **LINSTOR/DRBD outage:** The LINSTOR controller was in `CrashLoopBackOff` with 246 restarts; the LINSTOR CSI controller had 1,447 restarts and multiple containers in `CrashLoopBackOff`. The `linstor-controller` service had no endpoints, and all four `LinstorSatellite` objects reported `Connected=False`. The previous controller log ended with `Database initialization error` (report `6AD519AD-00000-000000`, exit status 20). The available container log did not expose the underlying database error.
4. **Worker I/O stalls:** Worker 204 had load average near 193 and high I/O pressure; 200 DRBD kernel threads were in uninterruptible `D` state. A sampled DRBD receiver stack was waiting in `drbd_flush_after_epoch`/`receive_Barrier`, and `dumpe2fs -h /dev/drbd1147` was blocked in `blkdev_fsync`. Worker 206 had load average near 130, 130 `D`-state threads, and high I/O pressure; a sampled thread was waiting in `jbd2` for DRBD volume `drbd1138`. These observations establish blocked DRBD I/O, but do not establish the original cause of the etcd failures.
5. **Workload impact:** The API listed failing or unhealthy pods, including the LINSTOR controller/CSI pods and application pods. A Ready node status alone did not indicate that storage-backed workloads were healthy.
6. **Shared Proxmox storage pressure:** The masters' 24 GiB boot disks reside on LVM storage `Kubernetes` on the same Samsung 990 PRO NVMe. The SSD reported no media/data-integrity errors, and the storage pool was about 87% full. Proxmox samples correlated NVMe saturation (about 98–100%) and 1.6–2.1 GB/s read bursts with individual master QEMU processes. Etcd explicitly logged leaders missing 500 ms heartbeats and attributing the delay to slow disk; API linearizable reads stalled for multiple seconds. The read storm moved between 202 and 203 during startup/catch-up. This is strong evidence of disk-contention contribution, though the guest operation causing repeated large reads is not identified.
7. **Peer TLS diagnosis remains unresolved:** All three `peer-ca.crt` files have the same SHA256 (`6cced225…f648ef49`), and each local `peer-server-client.crt` verifies against that CA. Direct mutual-TLS `openssl s_client` handshakes between 201 and 203 succeeded both ways. Nevertheless, etcd corruption-check requests logged `x509: certificate signed by unknown authority`, and servers logged peer connections rejected as `bad certificate`. The peer leaf certificates have different generation dates (201: Aug 4; 202/203: Jun 5, 2026), but their issuers and CA match. Certificate rotation was not attempted.

The LINSTOR failure and DRBD stalls are a serious storage-plane outage and may contribute to workload and API latency. Their relationship to the etcd peer timeouts is not proven. The LINSTOR controller's database initialization error remains the key missing diagnostic.

## Recovery actions taken

- Cleaned oversized syslog files and vacuumed archived systemd journal entries; no application logs or persistent-volume data were deleted.
- Applied the Kubernetes node log-rotation setup on masters 201–203. The change is in commits `4cad743`, `eed12a7`, and `ded72d7`.
- Rebooted master 201 through Proxmox. Graceful reboot of 202 timed out, so it was hard-reset and started again. Graceful reboot of 203 timed out, so it was hard-reset. A later hard reset of 201 restored SSH and briefly restored API readiness. No etcd reset/restore command was run.
- Later, Proxmox root SSH access from the jumphost was used to identify VM 202 as a read-burst source (~1.6–1.75 GB/s). Its graceful shutdown again timed out; only VM 202 was reset. Its QEMU read rate fell to zero, but a similar read burst then moved to VM 203. Proxmox read limits of `iops_rd=2500` were applied to the `scsi0` boot disks of VMs 201, 202, and 203. This reduced the 203 observed read rate from ~1.6 GB/s to ~200 MB/s and NVMe utilization from ~100% to ~28% in one sample. Subsequent samples still showed renewed K3s restarts, loss of etcd leader, and API timeouts, so this is a temporary containment measure rather than recovery.
- A later API snapshot from 201 showed all seven nodes Ready, but LINSTOR controller, affinity controller, CSI controller, and Piraeus operator remained in `CrashLoopBackOff`; all four satellites were `Connected=False`. Controller log retrieval through the Kubernetes API then failed because the node proxy to 192.168.1.119:10250 returned 502. No controller diagnostic helper was deployed, and no LINSTOR/DRBD or etcd data was changed.
- API readiness and all-node Ready status were observed temporarily, but follow-up checks showed renewed etcd readiness failures and API timeouts.

## Follow-up

- Restore stable etcd quorum and verify `/readyz` and node leases across all masters over a sustained period.
- Identify why master startup/catch-up generates very high reads on the shared NVMe; review Proxmox/KVM and guest block I/O traces before changing VM disk limits. The 2500 read IOPS limits are active runtime configuration and may constrain future catch-up; remove or adjust them after the source is understood and the cluster is stable.
- Diagnose the transient etcd peer TLS verification failures and confirm the authoritative member/peer identity before any certificate changes.
- Obtain the detailed LINSTOR report for `6AD519AD-00000-000000`; restore controller database access before attempting changes to LINSTOR resources or DRBD volumes.
- Reconnect the LINSTOR satellites and verify DRBD resource state and persistent-volume integrity before considering worker reboots.
- Re-run the Ansible hygiene playbook on every target node after connectivity is stable. The previous run timed out waiting for privilege escalation on worker 204.
