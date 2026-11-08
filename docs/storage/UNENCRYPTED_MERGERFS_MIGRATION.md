# Tracked runbook: migrate data disks from LUKS to plain ext4

## Objective

Convert eligible 10 TB disks from LUKS-backed ext4 to plain ext4. Keep both
20 TB disks encrypted. ZL2 was reformatted as plain ext4 at the user’s request,
and its prior contents were intentionally erased. A staging-directory write previously failed with physical-device I/O errors.
After physical inspection and a host reboot, ZL2 passed a serial-checked SMART
short test and a repeat of the failing directory/write-read test; it is now
qualified for staging. No MergerFS mount or package is used in this migration.

The client-facing identity remains unchanged throughout this phase:

- VM 101 / `192.168.1.102` / `storage.local.hejsan.xyz`
- NFS export `storage.local.hejsan.xyz:/`
- SMB share `public`
- RustFS endpoint on the storage VM

## Current status

| Date | State | Evidence / next action |
| --- | --- | --- |
| 2026-11-05 | Inventory captured | Nine whole disks are attached to VM 101 and all data branches are LUKS-backed ext4. The active pool is 91 TB total, 76 TB used, 11 TB available. |
| 2026-11-06 | ZL2 stability check required | Prior guest scan failed at `/mnt/drives/rebuild_zl2pm4xc/files/movies/5`; prior host SMART passed. The new direct-host check will decide whether ZL2 is migrated or excluded. |
| 2026-11-05 | Audit passed | Audit-only playbook verified all nine LUKS UUID/guest-SCSI mappings and nine Proxmox raw-disk assignments. Projected staging: 22,534,932,557,824 bytes available; 20,065,554,256,281 bytes required for largest branch plus 10% headroom. No remote evidence bundle was written. |
| 2026-11-06 | Migration scope confirmed | Keep both 20 TB branches encrypted. Test ZL2 directly on Proxmox; migrate it first if stable, then use its 16 TB filesystem as the single staging disk for the 10 TB candidates. |
| 2026-11-06 | JEHB candidate audit passed | Source-excluded free space: 4,671,756,836,864 bytes; JEHB used: 3,770,587,815,936 bytes; 110% requirement: 4,147,646,597,529 bytes. Oversized-file scan passed. Evidence ID: `2026-11-06-jehb-capacity`. No data was copied or formatted. |
| 2026-11-06 | JEHB initial copy started | Hidden staging pool mounted at `/mnt/migration/jehb`; online `rsync -aHAXS --numeric-ids` job PID `136824`, log `/var/lib/mergerfs-unencrypted-migration/2026-11-06-jehb-capacity/rsync-initial.log`. Source and services remain online. This is only a pre-copy; outage sync and checksum verification are still mandatory. |
| 2026-11-06 | JEHB copy still running | VM process check at 10:15 elapsed confirmed PID `136824` in sleep state; staging pool had 4.3 TB free, and RustFS, SMB, and NFS were active. Exact byte progress is not visible to the Ansible account because the PID and log are root-only; root SSH and guest-agent access were unavailable. |
| 2026-11-06 | JEHB copy rechecked | At 54:16 elapsed, PID `136824` is still running; staging pool reports 4.2 TB free; RustFS, SMB, and NFS remain active. Exact byte progress remains unavailable from the Ansible account. |
| 2026-11-06 | JEHB copy rechecked | At 1:21:47 elapsed, PID `136824` is still running; staging pool reports 4.2 TB free; RustFS, SMB, and NFS remain active. Exact byte progress remains unavailable from the Ansible account. |
| 2026-11-06 | Host migration selected | Keyfile is `/home/ubuntu/keyfile` (root-only, mode 0600). Proxmox has raw disk access, `cryptsetup`, `rsync`, `wipefs`, `mkfs.ext4`, and `guestmount`; no MergerFS staging will be used. The controller playbook streams the key into Proxmox `/run` without writing a local copy. |
| 2026-11-06 | Host identity check corrected | Proxmox exposes each data disk as GPT with one LUKS partition. JEHB serial and partition LUKS UUID match the inventory. The helper now checks and formats the partition, preserving the existing GPT table. VM remains running. |
| 2026-11-06 | Previous online copy pending shutdown | Last observed PID `136824` was running at 1:53:17 elapsed; the guest staging union had 4.2 TB free and RustFS/SMB/NFS were active. Clean VM shutdown will stop this pre-copy. Its partial files are not used by the host copy and will be removed only after JEHB is restored and checksum-verified. |
| 2026-11-06 | ZL2 erased and reformatted by request | VM 101 was force-stopped after remaining at its initramfs LUKS prompt. Confirmed serial `ZL2PM4XC`, partition LUKS UUID `80170736-a2fa-4899-b39e-91a7d32be950`, and expected VM `scsi9` mapping immediately before formatting. Preserved GPT; erased the LUKS signatures and created plain ext4, UUID `7bb92e49-48b0-467c-9a65-0e42bd61f67d`. No ZL2 contents were preserved. |
| 2026-11-06 | ZL2 scratch retest passed, staging write failed | SMART passed and counters remained zero; a 64 MiB random write/fsync/readback hash initially passed. The first JEHB staging attempt then failed creating the staging directory with `Input/output error`, before rsync started. Kernel logs for physical device `sdi` show SCSI `Not Ready`, failed writes, ext4 journal I/O errors, and cache sync `DID_NO_CONNECT`. A read-only `e2fsck -fn` returned 0 after unmount; this does not clear the device-path failure. ZL2 was marked unstable and unmounted. |
| 2026-11-06 | Capacity audits before physical inspection | All six candidates passed capacity only with ZL2, but the following ZL2 staging write failed; those earlier audit results were not used to start a copy. |
| 2026-11-07 | Post-inspection ZL2 retest passed | After host shutdown/restart, by-id resolves ZL2 serial `ZL2PM4XC` to `/dev/sdf` (16 TB; current SCSI path `8:0:4:0`). A SMART short test completed without error. The exact previously failing `.migration/...` directory creation and sync succeeded, followed by a 64 MiB direct write/read SHA-256 test. No new ZL2 or HBA I/O errors appeared during the retest. The earlier failure remains recorded as history; ZL2 was requalified. |
| 2026-11-07 | Fresh capacity audits passed | All six candidates selected ZL2, with 15.87 TB free. Requirements were 4.28 TB for JEHB and 9.73–9.82 TB for each other candidate. |
| 2026-11-07 | JEHB stage copy started | Rsync began from encrypted JEHB to ZL2 at 01:12 local time. At 01:28 it reached about 20% (225 GB) at roughly 170–185 MB/s; the current estimate is about 1 h 20 min. Stage checksum, source formatting, restore, and final checksum are still pending. |
| 2026-11-07 | Post-inspection drive retest passed; JEHB staging continues | After the host was powered back on, ZL2 was identified by serial (now `/dev/sdf`) and retested: SMART short test passed, nested directory create/sync passed, and a 64 MiB scratch write/read/fsync hash matched. No new ZL2/HBA errors appeared during the test. At 01:36, JEHB staging reached about 23% (253 GB), roughly 164–168 MB/s, with about 1 h 22 min estimated for the copy. JEHB remains encrypted; stage checksum and restore steps are pending. |
| 2026-11-07 | JEHB stage copy progress | At 01:47 local time, rsync reports about 33% (366 GB) copied, current throughput around 147–160 MB/s, and roughly 1 h 15–20 min remaining. No copy error has been reported; JEHB remains encrypted. |
| Current | JEHB stage checksum running; source remains encrypted; VM stopped | The fixed helper is deployed to Proxmox and syntax-checked. The previous stage directory is present and the restart's initial rsync transferred 0 bytes. The source-to-stage checksum dry run is now active and has read data from the source; JEHB remains LUKS, VM 101 is stopped, and `stage-verified`, `format-started`, `formatted`, and `complete` are still absent. Percent/ETA are unavailable during this checksum phase. |

Update this table after every playbook run, including the audit directory,
branch result, validation outcome, and any exception. Never commit keys,
credentials, raw RustFS configuration, or full file manifests.

### Hourly migration snapshots

The hourly Codex monitor appends a timestamped row here using read-only status
checks. “Drives left” counts eligible source disks not yet completed, including
the current drive; stage-only disks and ZL2 are excluded. If live progress or ETA
cannot be measured, record `unknown` rather than estimating from stale values.

| Timestamp (local) | Drives left | Current drive | Progress | ETA | Notes |
| --- | ---: | --- | ---: | --- | --- |
| 2026-11-07 01:54 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 38% (about 431 GB transferred) | about 1 h 15 min | Rsync stage copy active; source remains encrypted/intact; no errors reported. Five other eligible source drives remain after JEHB; two 20 TB drives are stage-only and excluded. |
| 2026-11-07 02:53 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 84% (about 1.04 TB transferred) | about 18 min | Rsync stage copy active; source remains encrypted/intact; no errors reported. Five other eligible source drives remain after JEHB; two 20 TB drives are stage-only and excluded. |
| 2026-11-07 03:55 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 51% stage-copy progress (about 1.68 TB) | about 2 h 20 min | Initial copy from encrypted JEHB to ZL2 was still running; source intact; no rsync errors reported. |
| 2026-11-07 04:52 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 70% stage-copy progress (about 2.29 TB) | about 1 h 40 min | Initial copy from encrypted JEHB to ZL2 was still running; source intact; no rsync errors reported. |
| 2026-11-07 05:51 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 90% stage-copy progress (about 2.94 TB) | about 35 min | Initial copy from encrypted JEHB to ZL2 was still running; source intact; no rsync errors reported. |
| 2026-11-07 06:56 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | 60% stage-copy progress (about 3.67 TB transferred) | about 3 h 40 min | Rsync revised its progress estimate while discovering files; copy was still running. JEHB remained encrypted and intact; no rsync I/O errors reported. |
| 2026-11-07 07:56 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Stage-copy rsync finished (`to-chk=0`; stage directory about 3.79 TB) | n/a; helper exited | The initial rsync reached its file-list completion, then `checksum_clean` exited with `label: unbound variable` before running the source-to-stage checksum. JEHB remained LUKS; formatting had not begun. Stage exists but is not verified. |
| 2026-11-07 10:24 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Stage copy present (~3.79 TB); source-stage checksum not run | n/a; migration stopped | Read-only Proxmox inspection confirms JEHB LUKS, stage directory present at 3,792,451,432,448 bytes, and `stage-verified`, `format-started`, `formatted`, and `complete` absent. No rsync is running. Source intact; five other eligible disks remain untouched and encrypted. |
| 2026-11-07 11:50 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Initial stage rsync unchanged (0 bytes recopied); checksum in progress | unknown | Fixed helper deployed and syntax-checked on Proxmox. Source-to-stage checksum dry run is active (about 15 GB read after 1m17s at first sample); JEHB remains LUKS and all format/completion markers remain absent. |
| 2026-11-07 11:52 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum in progress; percent unknown | unknown | Checksum dry-run remains active and has read about 30.8 GB; no writes. JEHB is still LUKS, and all format/completion markers remain absent. No error reported. |
| 2026-11-07 12:00 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum in progress; percent unknown | unknown | Read-only check finds checksum rsync active for 11m24s, with about 124 GB read and zero bytes written. JEHB partition remains LUKS and mounted; stage is present at 3,792,451,432,448 bytes. `stage-verified`, `format-started`, `formatted`, and `complete` remain absent. VM 101 is stopped. |
| 2026-11-07 12:51 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum in progress; percent unknown | unknown | Checksum rsync remains active after 1h02m and has read about 635 GB with zero bytes written. JEHB remains LUKS; stage remains 3,792,451,432,448 bytes; all format/completion markers are absent. VM 101 is stopped and no error is reported. |
| 2026-11-07 14:15 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Initial recopy 3% (about 75 GB transferred) | about 3 h 17 min (live rsync estimate) | All eight source `downloads` folders, four legacy `.migration/jehb/downloads` caches, and JEHB's staged `downloads` copy are empty. JEHB remains LUKS; stage checksum is pending; no format marker. VM 101 is stopped. The separate movie unlink on WVT06A7A remains in uninterruptible ext4 metadata I/O wait; SMART passes and no recent kernel I/O errors are reported. |
| 2026-11-07 14:17 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Initial recopy 4% (about 87.5 GB transferred) | about 3 h 20 min (live rsync estimate) | JEHB remains LUKS and mounted; stage recopy is active, checksum verification is pending, and no format marker exists. VM 101 is stopped. All downloads roots checked are empty. The separate WVT06A7A movie unlink remains in uninterruptible ext4 metadata I/O wait; its read counter increased, SMART passes, and no recent kernel I/O errors appeared. |
| 2026-11-07 15:23 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Stage rsync stopped at 89% (about 1.916 TB transferred) | halted; last live estimate about 17 min remaining | Rsync exited with code 24: files vanished before transfer. The non-AV1 deletion process has now ended, and read-only manifest verification found 0 of 10,826 selected paths remaining. This is consistent with the copy/delete race. JEHB is still LUKS; stage verification and all format markers are absent. Stage directory is about 349 GB by `du`; source branch about 201 GB. No recent kernel I/O errors. |
| 2026-11-07 15:27 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum dry-run in progress; unknown | unknown | After deletion completed, the incomplete stage tree was reconciled to the current LUKS source; both report about 201 GB by `du`. Helper resumed and is running its checksum dry-run. JEHB remains LUKS; `stage-verified`, `format-started`, `formatted`, and `complete` are absent. VM 101 is stopped; no active disk errors reported. |
| 2026-11-07 15:31 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum dry-run in progress; unknown | unknown | Rsync checksum counters show about 25.7 GB read on the source side and 8.5 GB on stage; no bytes written. JEHB remains LUKS and no format marker exists. The checksum process is active in an I/O wait; no recent kernel errors reported. |
| 2026-11-07 16:00 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Checksum dry-run; percent unknown (about 204.5 GB source and 200.9 GB stage read) | unknown for current gate | JEHB remains LUKS; stage verification is still pending and no format marker exists. Allocated data across the six eligible candidates is about 1.66 TB after cleanup. Extrapolated whole-migration ETA is roughly 12–16 hours if recent I/O rates persist; this is a broad estimate, not a live helper ETA. No recent kernel errors. |
| 2026-11-07 21:31 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum dry-run restarted; percent unknown | unknown | Previous checksum stopped on three content mismatches. All three files were confirmed AV1 and retained; their source copies were synced to the stage (about 21.2 GB). The helper is rerunning the full checksum gate; about 0.4 GB read per side at the latest sample, with no writes. JEHB remains LUKS and no format marker exists. |
| 2026-11-07 22:05 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum dry-run active; percent/ETA unknown | unknown | JEHB remains LUKS; no `stage-verified`, `format-started`, `formatted`, or `complete` marker. The current retry's checksum log lists three content mismatches (Alien Covenant, Devil's Knot, Enough Said); the pass is still running and has not produced a final result. Source/stage counters are near 215 GB each; no recent kernel errors. The single stage repair/retry has already been used. |
| 2026-11-07 22:07 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Checksum completed with differences; migration halted | n/a | The one authorized stage-only repair/retry failed. Final checksum log still lists three content mismatches: Alien Covenant, Devil's Knot, and Enough Said. JEHB remains LUKS and intact; stage verification and format markers are absent. VM 101 is stopped, no rsync is running, source/stage are each about 201 GB by `du`, and no recent kernel I/O errors were found. No further automatic repair is authorized. |
| 2026-11-07 22:21 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum dry-run restarted; percent/ETA unknown | unknown | At user direction, the three checksum-mismatched AV1 files were removed from both the JEHB source and incomplete stage (19,412,270,487 bytes from each). All three paths are absent. JEHB remains LUKS; stage verification is pending and no format marker exists. VM 101 is stopped; helper checksum is running and its log has no differences so far. |
| 2026-11-07 22:58 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Stage-only checksum reconciliation in progress; percent/ETA unknown | unknown | The helper stopped at a single checksum mismatch in retained AV1 file `Fly Me to the Moon (2024)`. Source and stage file sizes/timestamps match; JEHB remains LUKS, VM 101 is stopped, and no competing rsync/deletion process or kernel I/O errors were found. The one authorized stage-only reconciliation is active; about 5.5 GB read on each side at last sample. No format marker exists. |
| 2026-11-07 23:25 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Stage-only checksum reconciliation still active; percent/ETA unknown | unknown | Source and stage trees are about 183 GB by `du`. Rsync has read about 181 GB from source and 175 GB from stage, with no writes yet. JEHB remains LUKS; stage is unverified and format markers are absent. VM 101 is stopped; no competing writer or recent kernel I/O/HBA errors. |
| 2026-11-07 23:54 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum retry active; percent/ETA unknown | unknown | The stage-only reconciliation finished, then the helper restarted its gated checksum. About 0.45 GB source-side and 0.40 GB stage-side read at the latest sample, with no writes. JEHB remains LUKS; `stage-verified` and format markers are absent. VM 101 is stopped; no recent kernel I/O/HBA errors. |
| 2026-11-08 00:24 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Source-stage checksum retry active; percent/ETA unknown | unknown | JEHB remains LUKS; stage is unverified and no format marker exists. The active checksum log currently lists two content mismatches (Alice Through the Looking Glass and Casper); the retry has not finished. VM 101 is stopped and no recent kernel I/O/HBA errors appeared. The single stage repair/retry has already been used; no further automatic repair is authorized. |
| 2026-11-08 00:54 CET | 6 | JEHB7ZBN (`rebuild_jehb7zbn`) | Checksum retry ended with differences; migration halted | n/a | Helper exited with checksum differences after the single permitted stage repair/retry. The final log lists Alice Through the Looking Glass, Casper, and a RustFS/Linstor backup blob (`.../part.38`). JEHB remains LUKS/intact; stage is unverified; no format markers exist. VM 101 is stopped, no rsync is running, and no recent kernel I/O/HBA errors were found. Further automatic repair is not authorized. |

### User-requested media and downloads cleanup (2026-11-07)

The codec scan selected 10,816 confirmed non-AV1 movie/series files plus the
10 files whose codec probes failed, for 10,826 source paths and
79,346,854,563,959 bytes of apparent file size. A further 7,159,326,646-byte
file with no primary video stream was excluded from deletion because its codec
could not be established. The unlink process has ended, and a read-only check
confirmed all 10,826 selected source paths are absent. The ZL2 stage copies
matching the JEHB media targets were removed before source unlinking. The
subsequent JEHB staging rsync exited with code 24 because files vanished while
being transferred; this is consistent with the overlap with the authorized
deletion. JEHB remains LUKS and the incomplete stage has not been verified.

All eight source `downloads` directories, four older
`.migration/jehb/downloads` caches, and the JEHB downloads copy in the ZL2
staging tree were emptied. Source and legacy-cache downloads had
6,724,898,331,009 bytes of apparent file size across 9,009 entries; the staged
duplicate had 3,260,194,149,305 bytes across 3,408 entries. Apparent sizes
include hardlinks and duplicate stage paths and are not a prediction of net
physical space freed. All downloads directories remain as empty roots.

### Failure analysis: source-to-stage checksum wrapper

The run stopped after the initial JEHB-to-ZL2 staging `rsync`, at the first
source-to-stage checksum call. Proxmox confirms JEHB is still LUKS and that the
`stage-verified` and `format-started` markers are absent, so no source formatting
or restore occurred. The stage directory exists but is not checksum-verified.

The helper declared `source`, `destination`, `label`, and `output` in one
`local` command, with the `output` initializer expanding `$label`. With Bash
nounset enabled (`set -u`), that expansion raised `label: unbound variable`
even though the caller supplied all three arguments. A minimal function-shaped
reproduction with three arguments fails the same way. The helper now assigns
`output` in a second `local` command; the fix has been deployed and syntax-checked
on Proxmox. The same candidate has resumed: its initial rsync recopied 0 bytes,
then it entered the required source-to-stage checksum. No format marker is
present, and JEHB remains LUKS while verification runs.

## Verified live inventory

| Branch | Guest SCSI | Proxmox disk serial | LUKS UUID | Size | Used | Policy |
| --- | ---: | --- | --- | ---: | ---: | --- |
| `rebuild_zl2pm4xc` | `scsi9` | `ZL2PM4XC` | plain ext4 UUID `7bb92e49-48b0-467c-9a65-0e42bd61f67d` | 16 TB | stage copy active | qualified after post-inspection retest; prior fault retained in history |
| `rebuild_jehb7zbn` | `scsi8` | `JEHB7ZBN` | `483af58b-f2c1-4236-9c73-a5c9a42d5e46` | 10 TB | 3.79 TB at host audit | still LUKS; stage copy present but source-stage checksum pending |
| `automapped_b06291e1` | `scsi11` | `ZVT44KBK` | `b06291e1-2bcd-46f5-a39a-fc1e88f56e34` | 20 TB | 18.24 TB | keep encrypted; insufficient staging space |
| `automapped_6738a1a4` | `scsi12` | `WVT06A7A` | `6738a1a4-39ec-48ea-9d74-2b7a62a70f34` | 20 TB | 18.24 TB | keep encrypted; insufficient staging space |
| `automapped_7075cbde` | `scsi5` | `VCG4R2VN` | `7075cbde-2ced-4b76-a4df-352b423e4fc0` | 10 TB | 8.83 TB | eligible after JEHB completes |
| `automapped_cd5c9477` | `scsi3` | `VCHJAXJP` | `cd5c9477-0b68-4658-afc8-cd4530059d84` | 10 TB | 8.82 TB | eligible after JEHB completes |
| `automapped_dcade560` | `scsi10` | `ZS51280D` | `dcade560-de46-429a-b0de-efd4ff2a11c0` | 10 TB | 8.77 TB | eligible after JEHB completes |
| `automapped_46735ec9` | `scsi7` | `1EHU4K8Z` | `46735ec9-edab-485e-88c1-4b5277d546df` | 10 TB | 8.75 TB | eligible after JEHB completes |
| `automapped_ce3735fb` | `scsi6` | `VCGADWYM` | `ce3735fb-e187-4ea5-b806-f7e8a2aa924e` | 10 TB | 8.74 TB | eligible after JEHB completes |

The helper matches the physical serial, LUKS UUID, and VM SCSI assignment
before opening or formatting a device. Guest `/dev/sdX` letters are not used.
ZL2’s former LUKS UUID is retained in the ledger; its current ext4 UUID is
validated against the host format record, and the unstable marker prevents
automatic mounting or staging.

## Direct Proxmox workflow

VM 101 exposes the data disks as raw `/dev/disk/by-id` devices. Proxmox already
has `cryptsetup`, `rsync`, `sgdisk`, `mkfs.ext4`, and `guestmount`; no MergerFS
package, temporary pool, or data rebalancing is required.

1. Run the controller playbook in `prepare` phase while VM 101 is running. It
   compares the root-only guest keyfile against the encrypted Ansible value,
   streams the key directly to Proxmox `/run`, installs the host helper, and
   validates disk serials, LUKS UUIDs, and VM SCSI mappings. The key is not
   written to the controller or repository.
2. Run the playbook in `stop` phase for a clean shutdown. This stops the online
   JEHB pre-copy and all storage services. Its partial data remains in the
   seven guest stage directories, but the host migration uses a separate
   single-disk stage path. Remove the abandoned partial copy only after JEHB's
   host-side restore passes verification.
3. ZL2’s first staging attempt failed with SCSI and ext4 journal errors. After
   physical inspection and reboot, its serial, full 16 TB capacity, SMART short
   test, staging-directory creation, fsync, and scratch readback all passed.
   The retest had no new kernel I/O/HBA errors. The old failure stays recorded.
4. All six fresh capacity audits pass using ZL2. JEHB’s copy is in progress.
   Do not format JEHB until the source-to-stage checksum comparison is clean.
5. For each candidate, the helper requires 110% of measured source usage on
   one staging disk and at least 100 GiB remaining there. It rsyncs with
   metadata, hard links, ACLs, xattrs, sparse files, numeric IDs, and partial
   transfer support. A checksum dry run must be clean before LUKS metadata is
   erased. It formats the existing partition as ext4, then restores and checksum-verifies before
   deleting that candidate's stage copy.
6. Once eligible candidates finish, update the VM OS disk's `fstab` and
   `crypttab` offline, retaining entries for both 20 TB disks and any excluded
   disk. Unmount and close all host mappings, remove the temporary key, start
   VM 101, and verify mounts and services.

## Required gates

- Current storage services are stopped and no client has the pool mounted.
- A planned maintenance-window identifier is recorded.
- Each target matches its expected LUKS UUID, guest SCSI serial, and Proxmox
  raw-disk mapping.
- SMART and host/guest kernel logs show no new I/O or controller errors.
- The selected single staging filesystem has at least 110% of the candidate's
  measured used bytes, plus 100 GiB free after staging, and can hold every
  individual file.
- Every source-to-stage and stage-to-restored-target checksum comparison is
  clean. Any mismatch leaves services stopped for investigation.

## Tooling

The controller playbook can stage the previously verified vault key without
requiring the stopped VM (`stage-vault-key`), and controls VM lifecycle:

```sh
ansible-playbook playbooks/maintenance/proxmox_storage_unencrypted_migration.yml \
  --limit storage_servers -e proxmox_mergerfs_migration_phase=prepare
ansible-playbook playbooks/maintenance/proxmox_storage_unencrypted_migration.yml \
  --limit storage_servers -e proxmox_mergerfs_migration_phase=stage-vault-key
ansible-playbook playbooks/maintenance/proxmox_storage_unencrypted_migration.yml \
  --limit storage_servers -e proxmox_mergerfs_migration_phase=stop
```

On Proxmox, run the installed helper as root:

```sh
/usr/local/sbin/proxmox_storage_unencrypted_migration.sh inventory
/usr/local/sbin/proxmox_storage_unencrypted_migration.sh mount-all
/usr/local/sbin/proxmox_storage_unencrypted_migration.sh status
/usr/local/sbin/proxmox_storage_unencrypted_migration.sh exclude-plain-zl2 "reason for exclusion"
```

The current state is JEHB staging in progress on ZL2. The helper logs
sanitized state under `/var/lib/mergerfs-unencrypted-migration/`; the key remains
only in Proxmox `/run`. Finalize and start only after all selected candidates
have a `complete` state:

```sh
/usr/local/sbin/proxmox_storage_unencrypted_migration.sh finalize
ansible-playbook playbooks/maintenance/proxmox_storage_unencrypted_migration.yml \
  --limit storage_servers -e proxmox_mergerfs_migration_phase=start
```

The older guest-side audit playbook remains read-only and is not part of the
host migration workflow.

```sh
ansible-playbook playbooks/maintenance/mergerfs_unencrypted_migration.yml \
  --limit storage_servers \
  -e mergerfs_unencrypted_migration_phase=audit \
  -e mergerfs_unencrypted_write_audit=true \
  -e 'mergerfs_unencrypted_audit_id=2026-11-05-baseline'
```

The stored evidence is under `/var/lib/mergerfs-unencrypted-migration/` on VM
101. It is not used to perform the host-side conversion.

## Rollback

Before a branch is formatted, rollback is simply restoring its previous fstab
and crypttab entry and remounting it. After formatting, rollback means
restoring the verified staging copy to the newly created plain ext4 filesystem;
LUKS is intentionally not recreated. A failed data verification is not a
reason to restart services or continue with another branch.


## Current recovery boundary

On 2026-11-08, independent SHA-256 reads confirmed the reported RustFS
`part.38` differs between JEHB and its ZL2 stage: each copy produced a stable
but different hash on two consecutive reads. Both are 33,555,456 bytes; a byte
comparison found 16 differing bytes beginning at offset 23,125,600. The rsync
checksum gate therefore detected a real difference in this file. The cause and
which copy is correct remain undetermined. No repair or migration was started.

At 10:27 CET on 2026-11-08, a read-only byte comparison found the two movies
previously reported as mismatches now identical; the backup file still differs
in 16 consecutive bytes. A targeted rsync checksum dry run reported only the
backup file. The movies' source and stage ctimes predate the failed checksum;
no intervening file modification is evident, so transient reads or checksum
calculation remain possible but unproven. JEHB uses AES-XTS; a 16-byte difference
is consistent with an encrypted block but does not identify its cause or which
copy is correct. Both drives report SMART passed, with zero pending,
uncorrectable and interface CRC counts. JEHB's latest extended test passed at
64,206 power-on hours (current 64,487); ZL2's last completed test was a short
test. JEHB has four old ATA errors, latest at 15,380 hours. No current-boot
storage I/O or memory machine-check errors were found. SMBIOS reports no memory
error correction. Historical ZL2 disconnects remain relevant.

ZL2 was formatted and its old content is unrecoverable by design. It passed a targeted post-inspection retest and is mounted as JEHB’s staging filesystem. If any SCSI or ext4 I/O error recurs, stop the copy; JEHB remains encrypted until staging and checksum verification finish.
