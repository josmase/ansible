# MergerFS disk reset and likely HBA path issue

**Observed:** 2026-10-26

## Summary

During the rebuild of the intentionally discarded 16 TB disk (`ZL2PM4XC`), the guest received an I/O error while `mkfs.ext4` was writing filesystem accounting data. The disk later recovered after a VM restart and the same path passed a direct encrypted write/read test and a second ext4 format.

The evidence points to a transient storage-path interruption involving the HBA, SAS expander/backplane, slot, or connection. It does **not** currently point to media failure on the disk itself.

## Disk and VM identity

- Storage VM: Proxmox VM `101` (`nfs-server`), guest `192.168.1.102`
- Proxmox host: `192.168.1.100`
- Failed target: serial `ZL2PM4XC`, Seagate IronWolf Pro `ST16000NE000-2RW103`
- Guest assignment: VM `scsi9`
- Rebuilt 10 TB disk: serial `JEHB7ZBN`, guest `scsi8`

## Failure evidence

Guest `dmesg` recorded an aborted write and cache flush:

```text
I/O error, dev sde, sector 0 ... WRITE
Sense Key : Aborted Command
Add. Sense: I/O process terminated
CDB: Synchronize Cache(10)
```

Proxmox host `dmesg` recorded the corresponding device path reset:

```text
sd 9:0:6:0: device_block, handle(0x000d)
sd 9:0:6:0: device_unblock and setting to running
[sda] ... hostbyte=DID_NO_CONNECT
Synchronize Cache(10) failed: hostbyte=DID_NO_CONNECT
mpt3sas_cm1: ... port_remove: removed
mpt3sas_cm1: removing handle(0x000d)
...
mpt3sas_cm1: handle(0xd) ...
scsi 9:0:7:0: Direct-Access ATA ST16000NE000-2RW
[sdi] Attached SCSI disk
```

The physical disk disappeared from the HBA path and reappeared after a reset, with a changed Linux device name. Proxmox then reported VM 101 in `io-error` and the guest became unreachable until the VM was force-stopped and restarted.

## SMART evidence

After the reset, SMART for `ZL2PM4XC` reported:

- Overall health: `PASSED`
- Reallocated sectors: `0`
- Current pending sectors: `0`
- Offline uncorrectable: `0`
- UDMA CRC errors: `0`
- SMART error log: no errors logged
- Recorded self-test: completed without error

The rebuilt 10 TB disk `JEHB7ZBN` also reported passed SMART health, zero reallocated/pending/uncorrectable/CRC counters, and an extended test completed without error.

## Reproduction and recovery

After the VM restart and boot-volume unlock:

1. The target LUKS mapper opened successfully.
2. A 64 MiB direct write with `conv=fsync` completed at approximately 115 MB/s.
3. Reading the written block returned the expected zero data.
4. A second `mkfs.ext4` completed successfully.
5. The target mounted and joined the MergerFS pool.
6. No new target HBA reset or I/O error appeared after the restart.

## Likely causes, in order

1. SAS expander or backplane link reset affecting the disk slot.
2. HBA port/link instability or transient controller reset.
3. Drive carrier, power, or data connection intermittency.
4. Less likely: a disk firmware or electronics event that did not yet produce SMART media counters.
5. Unlikely based on current evidence: filesystem or LUKS corruption; the failure occurred below ext4 while flushing block I/O.

## What was ruled out

- The target did not show SMART media defects.
- The target did not show pending or uncorrectable sectors.
- The target did not show UDMA CRC errors.
- A direct post-restart encrypted write/read succeeded.
- The ext4 formatter succeeded after the path was reattached.
- The seven pre-existing MergerFS branches remained mounted and healthy.

## Recommended investigation in a separate maintenance window

Do not start with another destructive filesystem operation. First collect:

1. HBA firmware, driver, and link error counters (`mpt3sas_cm1`, SAS PHY events).
2. Expander/backplane event logs and the physical slot mapping for enclosure slot 7.
3. Proxmox host journal around the reset and current `scsi9` device identity.
4. SMART extended error, self-test, SATA PHY event, and NCQ logs for `ZL2PM4XC`.
5. Whether other disks in the same enclosure path show resets or link errors.
6. A controlled read/write test with the VM and services isolated, while watching host `dmesg` live.
7. If possible, reseat or move the carrier/cable to another known-good slot/path; record the slot change before testing.

Any physical reseat or slot move must preserve the serial-to-VM mapping and must be verified by serial before changing VM configuration.

## Current state

- `ZL2PM4XC` is formatted as a new encrypted ext4 MergerFS branch.
- `JEHB7ZBN` is formatted as a new encrypted ext4 MergerFS branch.
- Both branches are mounted and included in `/mnt/storage`.
- NFS and RustFS are active.
- VM 101 is running normally after the restart.
- No Kubernetes pods are Pending and Flux Kustomizations are Ready.
- This note documents the reset evidence; it does not claim the underlying HBA path issue is fixed.
