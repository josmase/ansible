#!/usr/bin/env bash
# Direct-host migration helper for VM 101's raw LUKS data disks.
# Run as root on Proxmox. The LUKS key is read only from a root-only file in
# /run and is never printed, copied into migration evidence, or added to argv.
set -Eeuo pipefail
umask 077

readonly VMID=101
readonly KEYFILE=/run/mergerfs-unencrypted-migration/luks.key
readonly BASE=/var/lib/mergerfs-unencrypted-migration
readonly MOUNT_ROOT=/mnt/mergerfs-unencrypted-migration/branches
readonly GUEST_ROOT=/mnt/mergerfs-unencrypted-migration/guest

# branch|scsi|serial|luks_uuid|by_id_path|migration_policy
readonly -a DISKS=(
  'rebuild_jehb7zbn|8|JEHB7ZBN|483af58b-f2c1-4236-9c73-a5c9a42d5e46|/dev/disk/by-id/ata-WDC_WD100EFAX-68LHPN0_JEHB7ZBN|candidate'
  'automapped_b06291e1|11|ZVT44KBK|b06291e1-2bcd-46f5-a39a-fc1e88f56e34|/dev/disk/by-id/ata-ST20000NM007D-3DJ103_ZVT44KBK|stage-only'
  'automapped_6738a1a4|12|WVT06A7A|6738a1a4-39ec-48ea-9d74-2b7a62a70f34|/dev/disk/by-id/wwn-0x5000c500f7080cbd|stage-only'
  'automapped_7075cbde|5|VCG4R2VN|7075cbde-2ced-4b76-a4df-352b423e4fc0|/dev/disk/by-id/ata-WDC_WD101EFAX-68LDBN0_VCG4R2VN|candidate'
  'automapped_cd5c9477|3|VCHJAXJP|cd5c9477-0b68-4658-afc8-cd4530059d84|/dev/disk/by-id/ata-WDC_WD102KRYZ-01A5AB0_VCHJAXJP|candidate'
  'automapped_dcade560|10|ZS51280D|dcade560-de46-429a-b0de-efd4ff2a11c0|/dev/disk/by-id/ata-ST10000VN0008-2PJ103_ZS51280D|candidate'
  'automapped_46735ec9|7|1EHU4K8Z|46735ec9-edab-485e-88c1-4b5277d546df|/dev/disk/by-id/ata-WDC_WD100EFAX-68LHPN0_1EHU4K8Z|candidate'
  'automapped_ce3735fb|6|VCGADWYM|ce3735fb-e187-4ea5-b806-f7e8a2aa924e|/dev/disk/by-id/ata-WDC_WD101EMAZ-11G7DA0_VCGADWYM|candidate'
  'rebuild_zl2pm4xc|9|ZL2PM4XC|80170736-a2fa-4899-b39e-91a7d32be950|/dev/disk/by-id/ata-ST16000NE000-2RW103_ZL2PM4XC|conditional'
)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"; }

usage() {
  cat <<'EOF'
Usage: proxmox_storage_unencrypted_migration.sh COMMAND [ARGS]

Commands:
  inventory                 Verify VM raw-disk serial/LUKS mappings (read-only)
  status                    Show VM, mounts, LUKS maps, candidate state, and copy process
  mount-all                 Open and mount LUKS filesystems after VM 101 is stopped
  format-zl2                Erase ZL2's LUKS partition and create plain ext4 (destructive)
  mount-zl2-plain           Mount ZL2 after format-zl2
  exclude-plain-zl2 REASON  Mark formatted ZL2 unstable and keep it unmounted
  retest-plain-zl2          Retry SMART/filesystem write-read checks by serial
  qualify-plain-zl2         Accept a successful post-failure retest for staging
  test-zl2                  Read ZL2 and run a scratch write/fsync/readback test
  capacity-audit BRANCH     Report read-only single-disk staging capacity
  migrate BRANCH [--skip-content-checksum]
                            Stage, format, and restore one candidate. The optional flag
                            uses metadata checks instead of content checksums.
  finalize                  Update VM 101 fstab/crypttab from verified conversions
  start-vm                  Unmount/close host devices, erase temporary key, start VM
  resume-vm                 Restart VM after a no-format migration abort
  exclude BRANCH REASON     Record a branch kept encrypted after a failed gate

Migration candidate names are rebuild_zl2pm4xc (only after test-zl2 passes),
rebuild_jehb7zbn, automapped_7075cbde, automapped_cd5c9477,
automapped_dcade560, automapped_46735ec9, and automapped_ce3735fb.
The two 20 TB branches are stage-only and are never formatted by this helper.
EOF
}

require_root() { [[ ${EUID} -eq 0 ]] || die 'run as root on the Proxmox host'; }
require_vm_stopped() {
  [[ "$(qm status "$VMID" | awk '{print $2}')" == stopped ]] || die "VM $VMID must be stopped"
}
require_key() {
  [[ -f "$KEYFILE" && ! -L "$KEYFILE" ]] || die "temporary key is missing: $KEYFILE"
  [[ "$(stat -c %a "$KEYFILE")" == 600 ]] || die 'temporary key mode must be 0600'
  [[ "$(stat -c %u "$KEYFILE")" == 0 ]] || die 'temporary key must be root-owned'
}

disk_fields() {
  local wanted=$1 row
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    if [[ $branch == "$wanted" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$branch" "$scsi" "$serial" "$luks_uuid" "$by_id" "$policy"
      return 0
    fi
  done
  return 1
}

read_disk() {
  local wanted=$1
  local fields
  fields=$(disk_fields "$wanted") || die "unknown branch: $wanted"
  IFS=$'\t' read -r D_BRANCH D_SCSI D_SERIAL D_LUKS D_DEVICE D_POLICY <<<"$fields"
  [[ -b "$D_DEVICE" ]] || die "$D_DEVICE is not a block device"
  [[ "$(lsblk -dnro SERIAL "$D_DEVICE" | xargs)" == "$D_SERIAL" ]] || die "serial mismatch at $D_DEVICE; expected $D_SERIAL"
  D_PARTITION="${D_DEVICE}-part1"
  [[ -b "$D_PARTITION" ]] || die "expected data partition missing: $D_PARTITION"
  [[ "$(lsblk -nro TYPE "$D_DEVICE" | awk '$1 == "part" {count++} END {print count+0}')" -eq 1 ]] || die "$D_DEVICE must have exactly one data partition"
  grep -Fxq "scsi${D_SCSI}: ${D_DEVICE}," <(qm config "$VMID" | sed -E 's/,size=[^,]+//') || \
    grep -E "^scsi${D_SCSI}: ${D_DEVICE}(,|$)" <(qm config "$VMID") >/dev/null || die "VM $VMID scsi${D_SCSI} mapping does not match $D_DEVICE"
}

check_luks_identity() {
  read_disk "$1"
  cryptsetup isLuks "$D_PARTITION" || die "$D_PARTITION is not currently LUKS"
  [[ "$(cryptsetup luksUUID "$D_PARTITION")" == "$D_LUKS" ]] || die "LUKS UUID mismatch for $D_BRANCH"
}

assert_empty_lost_found() {
  local path=$1
  [[ -d "$path/lost+found" ]] || return 0
  [[ -z "$(find "$path/lost+found" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "non-empty lost+found on $path; preserve and inspect it before migration"
}

mount_path() { printf '%s/%s' "$MOUNT_ROOT" "$1"; }
mapper_name() { printf 'mig_%s' "$1"; }
candidate_state_dir() { printf '%s/state/%s' "$BASE" "$1"; }

inventory() {
  local row actual_luks recorded_uuid
  printf 'VM %s: %s\n' "$VMID" "$(qm status "$VMID" | awk '{print $2}')"
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    if [[ $branch == rebuild_zl2pm4xc && -f "$(candidate_state_dir "$branch")/stability-failed" ]]; then
      log 'skipping ZL2 because its plain ext4 filesystem is marked unstable'
      continue
    fi
    read_disk "$branch"
    if cryptsetup isLuks "$D_PARTITION"; then
      actual_luks=$(cryptsetup luksUUID "$D_PARTITION")
      [[ $actual_luks == "$luks_uuid" ]] || die "LUKS UUID mismatch for $branch"
    elif [[ -f "$(candidate_state_dir "$branch")/plain-format-complete" && $branch == rebuild_zl2pm4xc ]]; then
      actual_luks=plain-ext4
      recorded_uuid=$(sed -n 's/.* ext4_uuid=\([^ ]*\).*/\1/p' "$(candidate_state_dir "$branch")/plain-format-complete")
      [[ $(blkid -s TYPE -o value "$D_PARTITION") == ext4 && $(blkid -s UUID -o value "$D_PARTITION") == "$recorded_uuid" ]] || die 'ZL2 ext4 identity differs from its format record'
    else
      [[ -f "$(candidate_state_dir "$branch")/complete" ]] || die "$branch lost its expected LUKS header without a completed migration record"
      actual_luks=plain-ext4
      [[ "$(blkid -s TYPE -o value "$D_PARTITION")" == ext4 ]] || die "$branch completed disk is not ext4"
    fi
    printf '%-24s scsi%-2s serial=%-10s luks=%s policy=%s\n' \
      "$branch" "$scsi" "$serial" "$actual_luks" "$policy"
  done
}

status() {
  printf 'vm=%s\n' "$(qm status "$VMID" | awk '{print $2}')"
  if pgrep -af 'rsync -aHAXS.*rebuild_jehb7zbn' >/dev/null; then
    pgrep -af 'rsync -aHAXS.*rebuild_jehb7zbn'
  else
    echo 'host_rsync=not-running'
  fi
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    local fs_state=unmounted
    findmnt -rn --mountpoint "$(mount_path "$branch")" >/dev/null 2>&1 && fs_state=mounted
    printf '%-24s %-10s host_fs=%s state=%s\n' "$branch" "$serial" "$policy" "$fs_state"
  done
  for path in "$BASE"/state/*/complete; do [[ -f $path ]] && printf 'completed=%s\n' "$(basename "$(dirname "$path")")"; done
}

mount_all() {
  require_vm_stopped
  require_key
  mkdir -p -m 0700 "$MOUNT_ROOT" "$BASE/state" "$BASE/log"
  local row branch scsi serial luks_uuid by_id policy mapper mpath
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    read_disk "$branch"
    mapper=$(mapper_name "$branch")
    mpath=$(mount_path "$branch")
    mkdir -p -m 0700 "$mpath"
    D_DEVICE=$by_id
    D_PARTITION="${by_id}-part1"
    if cryptsetup isLuks "$D_PARTITION"; then
      if ! cryptsetup status "$mapper" >/dev/null 2>&1; then
        check_luks_identity "$branch"
        cryptsetup open --type luks --key-file "$KEYFILE" "$D_PARTITION" "$mapper"
      fi
      [[ "$(blkid -s TYPE -o value "/dev/mapper/$mapper")" == ext4 ]] || die "$branch is not ext4 inside its LUKS mapping"
      [[ "$(cryptsetup luksUUID "$D_PARTITION")" == "$luks_uuid" ]] || die "LUKS UUID mismatch for $branch"
      if ! findmnt -rn --mountpoint "$mpath" >/dev/null 2>&1; then mount -t ext4 -o noatime "/dev/mapper/$mapper" "$mpath"; fi
    elif [[ $branch == rebuild_zl2pm4xc && -f "$(candidate_state_dir "$branch")/plain-format-complete" ]]; then
      [[ -b $D_PARTITION && $(blkid -s TYPE -o value "$D_PARTITION") == ext4 ]] || die 'ZL2 plain ext4 format record does not match filesystem type'
      local recorded_uuid
      recorded_uuid=$(sed -n 's/.* ext4_uuid=\([^ ]*\).*/\1/p' "$(candidate_state_dir "$branch")/plain-format-complete")
      [[ $(blkid -s UUID -o value "$D_PARTITION") == "$recorded_uuid" ]] || die 'ZL2 plain ext4 UUID differs from its format record'
      if ! findmnt -rn --mountpoint "$mpath" >/dev/null 2>&1; then mount -t ext4 -o noatime "$D_PARTITION" "$mpath"; fi
    else
      [[ -f "$(candidate_state_dir "$branch")/stage-verified" || -f "$(candidate_state_dir "$branch")/stage-metadata-only" ]] || die "$branch is no longer LUKS without a recorded stage copy"
      local part="$D_PARTITION"
      [[ -b $part && "$(blkid -s TYPE -o value "$part")" == ext4 ]] || die "$branch has no recognized converted ext4 partition"
      if ! findmnt -rn --mountpoint "$mpath" >/dev/null 2>&1; then mount -t ext4 -o noatime "$part" "$mpath"; fi
    fi
    log "mounted $branch ($serial)"
  done
}

check_smart() {
  local branch=$1 suffix=${2:-snapshot} device rc=0
  read_disk "$branch"
  device=$D_DEVICE
  smartctl -H -A -l error "$device" >"$BASE/log/${branch}-smart-${suffix}.txt" || rc=$?
  (( rc == 0 )) || die "smartctl reports errors for $branch; inspect $BASE/log/${branch}-smart-${suffix}.txt"
  grep -Eq 'SMART overall-health.*PASSED|SMART Health Status: OK' "$BASE/log/${branch}-smart-${suffix}.txt" || \
    die "SMART health is not passing for $branch"
  if grep -E 'Current_Pending_Sector|Offline_Uncorrectable|Reallocated_Sector_Ct' "$BASE/log/${branch}-smart-${suffix}.txt" | awk '{if ($NF+0 != 0) bad=1} END {exit bad ? 0 : 1}'; then
    die "SMART media error counters are non-zero for $branch"
  fi
}

test_zl2() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc path before after before_epoch after_epoch scratch expected actual i
  [[ ! -f "$(candidate_state_dir "$branch")/stability-failed" ]] || die 'ZL2 is marked unstable; review the failure record before another test'
  path=$(mount_path "$branch")
  findmnt -rn --mountpoint "$path" >/dev/null || die 'run mount-all before test-zl2'
  mkdir -p -m 0700 "$(candidate_state_dir "$branch")"
  check_smart "$branch" before
  before=$(date --iso-8601=seconds)
  before_epoch=$(date +%s)
  : >"$BASE/log/zl2-kernel-before.txt"
  journalctl -k --since '-5 minutes' --no-pager >"$BASE/log/zl2-kernel-before.txt"
  assert_empty_lost_found "$path"
  log 'scanning ZL2 file contents and metadata'
  find "$path" -xdev -type f -print0 | xargs -0 -r sha256sum >/dev/null
  for i in 1; do
    scratch=$(mktemp "$path/.proxmox-zl2-write-test.XXXXXX")
    dd if=/dev/urandom of="$scratch" bs=1M count=64 oflag=direct conv=fdatasync status=none
    expected=$(sha256sum "$scratch" | awk '{print $1}')
    actual=$(dd if="$scratch" bs=1M iflag=direct status=none | sha256sum | awk '{print $1}')
    [[ $actual == "$expected" ]] || die 'ZL2 scratch readback hash mismatch; preserve logs and do not migrate ZL2'
    rm -f -- "$scratch"
    sync -f "$path"
  done
  after=$(date --iso-8601=seconds)
  after_epoch=$(date +%s)
  journalctl -k --since "@$before_epoch" --until "@$after_epoch" --no-pager >"$BASE/log/zl2-kernel-test.txt"
  if grep -Eiq 'I/O error|DID_NO_CONNECT|Synchronize Cache.*failed|mpt3sas.*(reset|remove|error)' "$BASE/log/zl2-kernel-test.txt"; then
    die 'new host I/O or HBA errors during ZL2 test; exclude ZL2 and investigate the controller path'
  fi
  check_smart "$branch" after
  touch "$(candidate_state_dir "$branch")/stability-passed"
  log 'ZL2 read scan and scratch write/read test passed'
}

retest_plain_zl2() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc state path part recorded_uuid before_epoch after_epoch
  local test_dir scratch expected actual mounted=0
  read_disk "$branch"
  state=$(candidate_state_dir "$branch")
  [[ -f "$state/plain-format-complete" && -f "$state/stability-failed" ]] || die 'retest requires formatted ZL2 with a recorded prior stability failure'
  part="${D_DEVICE}-part1"
  [[ $(blkid -s TYPE -o value "$part") == ext4 ]] || die 'ZL2 is not plain ext4'
  recorded_uuid=$(sed -n 's/.* ext4_uuid=\([^ ]*\).*/\1/p' "$state/plain-format-complete")
  [[ $(blkid -s UUID -o value "$part") == "$recorded_uuid" ]] || die 'ZL2 ext4 UUID differs from its format record'
  path=$(mount_path "$branch")
  ! findmnt -rn -S "$part" >/dev/null || die 'ZL2 partition is mounted elsewhere'
  ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1 || die 'ZL2 test mount path is already occupied'
  mkdir -p -m 0700 "$path"
  check_smart "$branch" retest-before
  mount -t ext4 -o noatime "$part" "$path"
  mounted=1
  trap 'if (( mounted )); then umount "$path" || true; fi' EXIT
  before_epoch=$(date +%s)
  journalctl -k --since '-5 minutes' --no-pager >"$BASE/log/zl2-retest-kernel-before.txt"
  log 'retesting plain ext4 ZL2 directory and 64 MiB scratch write/readback'
  find "$path" -xdev -type f -print0 | xargs -0 -r sha256sum >/dev/null
  test_dir="$path/.migration/proxmox-retest-$(date +%s)"
  mkdir -p -m 0700 "$test_dir"
  sync -f "$test_dir"
  scratch="$test_dir/scratch.bin"
  dd if=/dev/urandom of="$scratch" bs=1M count=64 oflag=direct conv=fdatasync status=none
  expected=$(sha256sum "$scratch" | awk '{print $1}')
  actual=$(dd if="$scratch" bs=1M iflag=direct status=none | sha256sum | awk '{print $1}')
  [[ $actual == "$expected" ]] || die 'ZL2 retest scratch readback hash mismatch'
  sync -f "$test_dir"
  rm -f -- "$scratch"
  rmdir "$test_dir"
  sync -f "$path"
  after_epoch=$(date +%s)
  journalctl -k --since "@$before_epoch" --until "@$after_epoch" --no-pager >"$BASE/log/zl2-retest-kernel-test.txt"
  if grep -Eiq 'I/O error|DID_NO_CONNECT|Synchronize Cache.*failed|mpt3sas.*(reset|remove|error)' "$BASE/log/zl2-retest-kernel-test.txt"; then
    printf '%s\t%s\n' "$(date --iso-8601=seconds)" 'kernel reported I/O/HBA error during post-reseat retest' >"$state/stability-failed"
    die 'new host I/O/HBA error during ZL2 retest; keep ZL2 excluded'
  fi
  check_smart "$branch" retest-after
  printf '%s\n' "completed=$(date --iso-8601=seconds) serial=$D_SERIAL ext4_uuid=$recorded_uuid scratch_sha256=$expected" >"$state/retest-passed"
  umount "$path"
  mounted=0
  trap - EXIT
  log 'ZL2 retest passed; previous stability failure remains recorded and staging remains disabled pending review'
}

qualify_plain_zl2() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc state path part recorded_uuid
  read_disk "$branch"
  state=$(candidate_state_dir "$branch")
  [[ -f "$state/retest-passed" && -f "$state/stability-failed" ]] || die 'qualification requires both the earlier failure and a successful post-failure retest record'
  part="${D_DEVICE}-part1"
  [[ $(blkid -s TYPE -o value "$part") == ext4 ]] || die 'ZL2 is not plain ext4'
  recorded_uuid=$(sed -n 's/.* ext4_uuid=\([^ ]*\).*/\1/p' "$state/plain-format-complete")
  [[ -n $recorded_uuid && $(blkid -s UUID -o value "$part") == "$recorded_uuid" ]] || die 'ZL2 ext4 UUID differs from its format record'
  path=$(mount_path "$branch")
  ! findmnt -rn -S "$part" >/dev/null && ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1 || die 'ZL2 must be unmounted before qualification'
  check_smart "$branch" qualify
  mv "$state/stability-failed" "$state/stability-failed-before-post-reseat-retest"
  touch "$state/stability-passed"
  log 'qualified ZL2 for staging after successful post-reseat SMART, mkdir/sync, and scratch write/readback retest'
}

format_zl2() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc path state old_uuid
  read_disk "$branch"
  [[ $D_POLICY == conditional && $D_SERIAL == ZL2PM4XC ]] || die 'ZL2 inventory identity or policy mismatch'
  cryptsetup isLuks "$D_PARTITION" || die 'ZL2 partition is not LUKS; refusing an unexpected format state'
  old_uuid=$(cryptsetup luksUUID "$D_PARTITION")
  [[ $old_uuid == "$D_LUKS" ]] || die 'ZL2 LUKS UUID mismatch'
  ! findmnt -rn -S "$D_PARTITION" >/dev/null && ! findmnt -rn -S "/dev/mapper/$(mapper_name "$branch")" >/dev/null || die 'ZL2 is mounted; unmount it before formatting'
  ! cryptsetup status "$(mapper_name "$branch")" >/dev/null 2>&1 || die 'ZL2 mapper is open; close it before formatting'
  path=$(mount_path "$branch")
  ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1 || die 'ZL2 mount path is busy'
  state=$(candidate_state_dir "$branch")
  mkdir -p -m 0700 "$state" "$BASE/log"
  [[ ! -e "$state/format-started" && ! -e "$state/plain-format-complete" ]] || die 'ZL2 format state already exists; inspect before continuing'
  printf '%s\n' "started=$(date --iso-8601=seconds) serial=$D_SERIAL partition=$D_PARTITION old_luks_uuid=$old_uuid" >"$state/format-started"
  log "ERASING ZL2 LUKS data on $D_PARTITION; GPT on $D_DEVICE is preserved"
  wipefs --all --force "$D_PARTITION"
  mkfs.ext4 -F -m 0 -L ZL2 "$D_PARTITION"
  [[ $(blkid -s TYPE -o value "$D_PARTITION") == ext4 ]] || die 'ZL2 partition did not identify as ext4 after format'
  printf '%s\n' "completed=$(date --iso-8601=seconds) serial=$D_SERIAL ext4_uuid=$(blkid -s UUID -o value "$D_PARTITION")" >"$state/plain-format-complete"
  rm -f -- "$state/format-started" "$state/excluded"
  [[ ! -e "$state/excluded" ]] || die 'failed to clear stale ZL2 exclusion marker'
  log 'ZL2 now contains plain ext4; old LUKS data is erased'
}

mount_zl2_plain() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc path part
  [[ ! -f "$(candidate_state_dir "$branch")/stability-failed" ]] || die 'ZL2 is marked unstable and must remain unmounted'
  read_disk "$branch"
  [[ -f "$(candidate_state_dir "$branch")/plain-format-complete" ]] || die 'ZL2 lacks the explicit plain-format completion record'
  part="${D_DEVICE}-part1"
  [[ $(blkid -s TYPE -o value "$part") == ext4 ]] || die 'ZL2 partition is not ext4'
  path=$(mount_path "$branch")
  mkdir -p -m 0700 "$path"
  if ! findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then mount -t ext4 -o noatime "$part" "$path"; fi
  log "mounted plain ext4 ZL2 ($D_SERIAL)"
}

exclude_plain_zl2() {
  require_vm_stopped
  local branch=rebuild_zl2pm4xc path state recorded_uuid reason
  read_disk "$branch"
  state=$(candidate_state_dir "$branch")
  [[ -f "$state/plain-format-complete" ]] || die 'ZL2 has no authorized plain ext4 format record'
  [[ $(blkid -s TYPE -o value "$D_PARTITION") == ext4 ]] || die 'ZL2 partition no longer identifies as ext4'
  recorded_uuid=$(sed -n 's/.* ext4_uuid=\([^ ]*\).*/\1/p' "$state/plain-format-complete")
  [[ $(blkid -s UUID -o value "$D_PARTITION") == "$recorded_uuid" ]] || die 'ZL2 ext4 UUID differs from its format record'
  path=$(mount_path "$branch")
  if findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then umount "$path"; fi
  reason=${1//$'\n'/ }
  reason=${reason//$'\t'/ }
  [[ -n $reason ]] || die 'provide a concise exclusion reason'
  [[ ! -f "$state/stability-passed" ]] || mv "$state/stability-passed" "$state/stability-passed-before-write-failure"
  printf '%s\t%s\n' "$(date --iso-8601=seconds)" "$reason" >"$state/stability-failed"
  log "excluded plain ext4 ZL2 from staging: $reason"
}

cleanup_initial_guest_stage() {
  local branch path
  require_vm_stopped
  [[ -f "$(candidate_state_dir rebuild_jehb7zbn)/complete" ]] || die 'JEHB must be fully restored and verified before deleting its old guest pre-copy'
  for branch in automapped_46735ec9 automapped_6738a1a4 automapped_7075cbde automapped_b06291e1 automapped_cd5c9477 automapped_ce3735fb automapped_dcade560; do
    path="$(mount_path "$branch")/.migration/jehb"
    findmnt -rn --mountpoint "$(mount_path "$branch")" >/dev/null || die "$branch is not mounted; refusing cleanup"
    if [[ -d $path && ! -L $path ]]; then
      rm -rf --one-file-system -- "$path"
    fi
  done
  log 'abandoned partial guest JEHB pre-copy removed after host-side verification'
}

capacity_gate() {
  local candidate=$1 source used staged=0 row branch scsi serial luks_uuid by_id policy target_avail max_file required staged_here best_branch= best_total=0 best_free=0 state stage fixed=0 fixed_found=0
  state=$(candidate_state_dir "$candidate")
  source=$(mount_path "$candidate")
  used=$(df -B1 --output=used "$source" | tail -n 1 | tr -d ' ')
  if [[ -f "$state/stage-disk" ]]; then
    best_branch=$(cat "$state/stage-disk")
    fixed=1
    [[ $best_branch != "$candidate" ]] || die 'recorded stage disk must differ from its source'
    disk_fields "$best_branch" >/dev/null || die "unknown recorded stage disk: $best_branch"
  fi
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    [[ $branch != "$candidate" ]] || continue
    [[ $policy != conditional || -f "$(candidate_state_dir "$branch")/stability-passed" ]] || continue
    target=$(mount_path "$branch")
    findmnt -rn --mountpoint "$target" >/dev/null || continue
    target_avail=$(df -B1 --output=avail "$target" | tail -n 1 | tr -d ' ')
    if (( fixed )); then
      [[ $branch == "$best_branch" ]] || continue
      fixed_found=1
      best_free=$target_avail
      staged_here=0
      [[ -d "$target/.migration/proxmox-$candidate" ]] && staged_here=$(du -s -B1 "$target/.migration/proxmox-$candidate" | awk '{print $1}')
      staged=$staged_here
    else
      staged_here=0
      [[ -d "$target/.migration/proxmox-$candidate" ]] && staged_here=$(du -s -B1 "$target/.migration/proxmox-$candidate" | awk '{print $1}')
      if (( target_avail + staged_here > best_total )); then
        best_branch=$branch
        best_total=$((target_avail + staged_here))
        best_free=$target_avail
        staged=$staged_here
      fi
    fi
  done
  (( ! fixed || fixed_found )) || die "recorded staging disk $best_branch is not mounted or eligible"
  required=$((used + (used + 9) / 10 + 107374182400))
  [[ -n $best_branch ]] || die 'no eligible single-disk staging filesystem is mounted'
  if [[ ! -f "$state/stage-disk" ]]; then printf '%s\n' "$best_branch" >"$state/stage-disk"; fi
  stage="$(mount_path "$best_branch")/.migration/proxmox-$candidate"
  mkdir -p -m 0700 "$stage"
  [[ -d $stage ]] && staged=$(du -s -B1 "$stage" | awk '{print $1}') || staged=0
  best_free=$(df -B1 --output=avail "$(mount_path "$best_branch")" | tail -n 1 | tr -d ' ')
  printf 'candidate=%s\nused_bytes=%s\nstage_disk=%s\nstage_available_bytes=%s\nalready_staged_bytes=%s\ncapacity_remaining_bytes=%s\nrequired_bytes=%s\n' \
    "$candidate" "$used" "$best_branch" "$best_free" "$staged" "$((best_free + staged))" "$required" | tee "$state/capacity.txt"
  (( best_free + staged >= required )) || die "$candidate fails the single-disk 10% staging-capacity gate"
  (( best_free > 107374182400 )) || die 'chosen staging filesystem has 100 GiB or less free'
  max_file=$((best_free - 107374182400))
  if find "$source" -xdev -type f -size "+${max_file}c" -print -quit | grep -q .; then
    die 'at least one file is larger than the staging filesystem free space minus 100 GiB'
  fi
}

capacity_audit() {
  local candidate=$1 source used required best_branch= best_free=0 row branch scsi serial luks_uuid by_id policy target available staged effective result=FAIL
  require_vm_stopped
  read_disk "$candidate"
  [[ $D_POLICY != stage-only ]] || die "$candidate is a stage-only disk"
  if [[ $D_POLICY == conditional && ! -f "$(candidate_state_dir "$candidate")/stability-passed" ]]; then
    die 'ZL2 failed or has not passed its stability test'
  fi
  source=$(mount_path "$candidate")
  findmnt -rn --mountpoint "$source" >/dev/null || die "$candidate is not mounted"
  used=$(df -B1 --output=used "$source" | tail -n 1 | tr -d ' ')
  required=$((used + (used + 9) / 10 + 107374182400))
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    [[ $branch != "$candidate" ]] || continue
    [[ $policy != conditional || -f "$(candidate_state_dir "$branch")/stability-passed" ]] || continue
    target=$(mount_path "$branch")
    findmnt -rn --mountpoint "$target" >/dev/null || continue
    available=$(df -B1 --output=avail "$target" | tail -n 1 | tr -d ' ')
    staged=0
    [[ -d "$target/.migration/proxmox-$candidate" ]] && staged=$(du -s -B1 "$target/.migration/proxmox-$candidate" | awk '{print $1}')
    effective=$((available + staged))
    printf 'stage_option=%s available_bytes=%s staged_bytes=%s effective_bytes=%s\n' "$branch" "$available" "$staged" "$effective"
    if (( effective > best_free )); then best_branch=$branch; best_free=$effective; fi
  done
  (( best_free >= required )) && result=PASS
  printf 'candidate=%s\nsource_used_bytes=%s\nrequired_bytes=%s\nbest_stage_disk=%s\nbest_effective_bytes=%s\ncapacity_result=%s\n' \
    "$candidate" "$used" "$required" "${best_branch:-none}" "$best_free" "$result"
}

checksum_clean() {
  local source=$1 destination=$2 label=$3
  local output="$BASE/log/checksum-$label.txt"
  local rc=0
  local -a checksum_arg=(--checksum)
  if [[ ${SKIP_CONTENT_CHECKSUM:-0} == 1 ]]; then
    checksum_arg=()
    log "WARNING: $label checks metadata only; file contents are not verified"
  fi
  rsync -aHAXS --numeric-ids "${checksum_arg[@]}" --dry-run --delete --itemize-changes \
    --out-format='%i %n' --exclude='/.migration/' --exclude='/lost+found/' \
    "$source/" "$destination/" >"$output" 2>&1 || rc=$?
  (( rc == 0 )) || die "rsync checksum comparison failed; see $output"
  if grep -E '^(\*deleting|[<>ch.*][fdLDS.]|[.]f|[.]d)' "$output" >/dev/null; then
    die "checksum comparison found differences; see $output"
  fi
}

convert_candidate() {
  local candidate=$1 path stage state source_device part new_uuid stage_disk row branch scsi serial luks_uuid by_id policy
  require_vm_stopped
  read_disk "$candidate"
  [[ $D_POLICY != stage-only ]] || die "$candidate is a 20 TB stage-only disk"
  if [[ $D_POLICY == conditional && ! -f "$(candidate_state_dir "$candidate")/stability-passed" ]]; then
    die 'ZL2 must pass test-zl2 before migration'
  fi
  if [[ $candidate != rebuild_zl2pm4xc && -f "$(candidate_state_dir rebuild_zl2pm4xc)/stability-passed" && ! -f "$(candidate_state_dir rebuild_zl2pm4xc)/complete" && ! -f "$(candidate_state_dir rebuild_zl2pm4xc)/plain-format-complete" ]]; then
    die 'migrate passing ZL2 first so it can provide single-disk staging capacity'
  fi
  path=$(mount_path "$candidate")
  state=$(candidate_state_dir "$candidate")
  mkdir -p -m 0700 "$state"

  if [[ -f "$state/complete" ]]; then
    log "$candidate is already complete"
    return
  fi
  if cryptsetup isLuks "$D_PARTITION"; then
    findmnt -rn --mountpoint "$path" >/dev/null || die "$candidate source filesystem is not mounted"
    capacity_gate "$candidate"
    stage_disk=$(cat "$state/stage-disk")
    stage="$(mount_path "$stage_disk")/.migration/proxmox-$candidate"
    check_luks_identity "$candidate"
    assert_empty_lost_found "$path"
    log "copying $candidate to staging pool"
    rsync -aHAXS --numeric-ids --partial --info=progress2 --exclude='/.migration/' --exclude='/lost+found/' "$path/" "$stage/"
    checksum_clean "$path" "$stage" "${candidate}-source-stage"
    if [[ ${SKIP_CONTENT_CHECKSUM:-0} == 1 ]]; then
      printf '%s\n' "$D_LUKS" >"$state/stage-metadata-only"
    else
      printf '%s\n' "$D_LUKS" >"$state/stage-verified"
    fi
    source_device="$D_PARTITION"
    umount "$path"
    cryptsetup close "$(mapper_name "$candidate")"
    printf '%s\n' "format-started=$(date --iso-8601=seconds) serial=$D_SERIAL luks_uuid=$D_LUKS" >"$state/format-started"
    wipefs --all --force "$source_device"
    part="$source_device"
    [[ -b $part ]] || die "source partition disappeared: $part; stage copy is preserved"
    if cryptsetup isLuks "$source_device"; then die "old LUKS signature remains on $source_device; do not mount it"; fi
    mkfs.ext4 -F "$part"
    new_uuid=$(blkid -s UUID -o value "$part")
    : >>"$BASE/converted.tsv"
    awk -F '\t' -v branch="$candidate" '$1 != branch' "$BASE/converted.tsv" >"$BASE/converted.tsv.tmp"
    printf '%s\t%s\t%s\t%s\n' "$candidate" "$D_SERIAL" "$D_LUKS" "$new_uuid" >>"$BASE/converted.tsv.tmp"
    mv -f "$BASE/converted.tsv.tmp" "$BASE/converted.tsv"
    mount -t ext4 -o noatime "$part" "$path"
    touch "$state/formatted"
  else
    [[ -f "$state/stage-verified" || -f "$state/stage-metadata-only" ]] || die 'disk is no longer LUKS but has no stage marker; stop for recovery'
    if [[ -f "$state/stage-metadata-only" ]]; then
      log 'WARNING: the staging copy was not content-verified before formatting'
    fi
    part="$D_PARTITION"
    [[ -b $part && "$(blkid -s TYPE -o value "$part")" == ext4 ]] || die 'converted target is not a visible ext4 partition'
    stage_disk=$(cat "$state/stage-disk")
    stage="$(mount_path "$stage_disk")/.migration/proxmox-$candidate"
    [[ -d $stage ]] || die 'verified staging copy is missing; do not continue'
    if ! findmnt -rn --mountpoint "$path" >/dev/null; then mount -t ext4 -o noatime "$part" "$path"; fi
    new_uuid=$(blkid -s UUID -o value "$part")
    if ! awk -F '\t' -v branch="$candidate" '$1 == branch {found=1} END {exit !found}' "$BASE/converted.tsv" 2>/dev/null; then
      printf '%s\t%s\t%s\t%s\n' "$candidate" "$D_SERIAL" "$D_LUKS" "$new_uuid" >>"$BASE/converted.tsv"
    fi
  fi

  log "restoring $candidate from staging copy"
  rsync -aHAXS --numeric-ids --partial --info=progress2 --exclude='/lost+found/' "$stage/" "$path/"
  checksum_clean "$stage" "$path" "${candidate}-stage-target"
  if [[ ${SKIP_CONTENT_CHECKSUM:-0} == 1 ]]; then
    touch "$state/completed-without-content-checksum"
    log "$candidate restored; metadata comparison passed, contents were not verified"
  else
    log "$candidate restored and checksum-verified against stage"
  fi
  touch "$state/complete"

  rm -rf --one-file-system -- "$stage"
  rmdir "$(mount_path "$stage_disk")/.migration" 2>/dev/null || true
  log "temporary staging for $candidate removed after the selected comparison"
  [[ $candidate != rebuild_jehb7zbn ]] || cleanup_initial_guest_stage
}

finalize_guest_config() {
  require_vm_stopped
  [[ -f "$BASE/converted.tsv" ]] || die 'no converted filesystem records found'
  local row branch scsi serial luks_uuid by_id policy state
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    [[ $policy != stage-only ]] || continue
    state=$(candidate_state_dir "$branch")
    if [[ -f "$state/complete" ]]; then continue; fi
    if [[ -f "$state/excluded" ]]; then
      cryptsetup isLuks "${by_id}-part1" || die "$branch is marked excluded but is no longer LUKS"
      [[ "$(cryptsetup luksUUID "${by_id}-part1")" == "$luks_uuid" ]] || die "$branch excluded-disk LUKS UUID changed"
      continue
    fi
    die "$branch has no completed or recorded exclusion state"
  done
  mkdir -p -m 0700 "$GUEST_ROOT" "$BASE/backups"
  local osdisk=/dev/Kubernetes/vm-101-disk-0
  [[ -b $osdisk ]] || die "VM OS disk not found: $osdisk"
  if findmnt -rn --mountpoint "$GUEST_ROOT" >/dev/null 2>&1; then die 'guest root mount already exists'; fi
  guestmount --add "$osdisk" -i --rw "$GUEST_ROOT"
  trap 'guestunmount "$GUEST_ROOT" >/dev/null 2>&1 || true' RETURN
  [[ -f "$GUEST_ROOT/etc/fstab" && -f "$GUEST_ROOT/etc/crypttab" ]] || die 'guestmount did not expose expected /etc configuration'
  cp -a "$GUEST_ROOT/etc/fstab" "$BASE/backups/fstab.before"
  cp -a "$GUEST_ROOT/etc/crypttab" "$BASE/backups/crypttab.before"
  python3 - "$GUEST_ROOT" "$BASE/converted.tsv" <<'PY'
import os
import pathlib
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
records = {}
with open(sys.argv[2], encoding="utf-8") as stream:
    for line in stream:
        branch, serial, old_uuid, new_uuid = line.rstrip("\n").split("\t")
        records[branch] = (old_uuid, new_uuid)

crypttab = root / "etc/crypttab"
fstab = root / "etc/fstab"
crypt_lines = crypttab.read_text(encoding="utf-8").splitlines()
fstab_lines = fstab.read_text(encoding="utf-8").splitlines()
for branch, (old_uuid, new_uuid) in records.items():
    matches = [line for line in crypt_lines if line.split()[:1] == [branch]]
    if len(matches) != 1 or f"UUID={old_uuid}" not in matches[0]:
        raise SystemExit(f"crypttab identity mismatch for {branch}; left files unchanged")
    crypt_lines.remove(matches[0])
    mountpoint = f"/mnt/drives/{branch}"
    indexes = [i for i, line in enumerate(fstab_lines) if line and not line.lstrip().startswith("#") and len(line.split()) >= 3 and line.split()[1] == mountpoint]
    if len(indexes) != 1:
        raise SystemExit(f"expected one fstab entry for {mountpoint}; left files unchanged")
    fields = fstab_lines[indexes[0]].split()
    fields[0] = f"UUID={new_uuid}"
    fstab_lines[indexes[0]] = "\t".join(fields)

def replace(path, lines):
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".migration.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write("\n".join(lines) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, path.stat().st_mode & 0o777)
        os.chown(temp, path.stat().st_uid, path.stat().st_gid)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

replace(crypttab, crypt_lines)
replace(fstab, fstab_lines)
PY
  guestunmount "$GUEST_ROOT"
  trap - RETURN
  touch "$BASE/guest-config-updated"
  log 'guest crypttab/fstab updated offline; two 20 TB mappings are retained'
}

release_host_and_start_vm() {
  require_vm_stopped
  local row branch scsi serial luks_uuid by_id policy path
  for row in "${DISKS[@]}"; do
    IFS='|' read -r branch scsi serial luks_uuid by_id policy <<<"$row"
    path=$(mount_path "$branch")
    if findmnt -rn --mountpoint "$path" >/dev/null 2>&1; then umount "$path"; fi
    if cryptsetup status "$(mapper_name "$branch")" >/dev/null 2>&1; then cryptsetup close "$(mapper_name "$branch")"; fi
  done
  local target
  qm start "$VMID"
  [[ "$(qm status "$VMID" | awk '{print $2}')" == running ]] || die "VM $VMID did not start"
  rm -f -- "$KEYFILE"
  rmdir /run/mergerfs-unencrypted-migration 2>/dev/null || true
  log "started VM $VMID; verify all mounts and services before deleting evidence"
}

start_vm() {
  [[ -f "$BASE/guest-config-updated" ]] || die 'finalize guest config before starting VM'
  release_host_and_start_vm
}

resume_vm() {
  local state
  [[ ! -s "$BASE/converted.tsv" ]] || die 'converted disks exist; finalize guest config before starting VM'
  for state in "$BASE"/state/*/format-started; do
    [[ ! -e $state ]] || die 'format has started; use recovery/finalize instead of resuming unchanged'
  done
  release_host_and_start_vm
}

main() {
  require_root
  local command=${1:-help}
  [[ $# -gt 0 ]] && shift || true
  case "$command" in
    mount-all|format-zl2|mount-zl2-plain|exclude-plain-zl2|retest-plain-zl2|qualify-plain-zl2|test-zl2|migrate|finalize|start-vm|resume-vm|exclude|cleanup-old-guest-jehb-stage)
      mkdir -p -m 0700 "$BASE/log"
      exec > >(tee -a "$BASE/log/host-migration.log") 2>&1
      ;;
  esac
  case "$command" in
    help|-h|--help) usage ;;
    inventory) inventory ;;
    status) status ;;
    mount-all) mount_all ;;
    format-zl2) format_zl2 ;;
    mount-zl2-plain) mount_zl2_plain ;;
    exclude-plain-zl2)
      [[ $# == 1 ]] || die 'exclude-plain-zl2 requires one concise reason'
      exclude_plain_zl2 "$1"
      ;;
    retest-plain-zl2) retest_plain_zl2 ;;
    qualify-plain-zl2) qualify_plain_zl2 ;;
    test-zl2) test_zl2 ;;
    capacity-audit) [[ $# == 1 ]] || die 'capacity-audit requires one branch name'; capacity_audit "$1" ;;
    migrate)
      [[ $# == 1 || ( $# == 2 && $2 == --skip-content-checksum ) ]] || die 'migrate requires a branch and optional --skip-content-checksum'
      SKIP_CONTENT_CHECKSUM=0
      [[ $# == 1 ]] || SKIP_CONTENT_CHECKSUM=1
      convert_candidate "$1"
      ;;
    finalize) finalize_guest_config ;;
    start-vm) start_vm ;;
    resume-vm) resume_vm ;;
    cleanup-old-guest-jehb-stage) cleanup_initial_guest_stage ;;
    exclude)
      [[ $# == 2 ]] || die 'exclude requires a branch and a concise reason'
      read_disk "$1"
      [[ $D_POLICY != stage-only ]] || die 'cannot exclude a stage-only disk from the migration scope'
      [[ ! -f "$(candidate_state_dir "$1")/format-started" ]] || die 'format has started; use recovery, not exclusion'
      cryptsetup isLuks "$D_PARTITION" || die 'excluded source must still be LUKS'
      [[ "$(cryptsetup luksUUID "$D_PARTITION")" == "$D_LUKS" ]] || die 'excluded source UUID mismatch'
      mkdir -p -m 0700 "$(candidate_state_dir "$1")"
      reason=${2//$'\n'/ }
      reason=${reason//$'\t'/ }
      printf '%s\t%s\n' "$(date --iso-8601=seconds)" "$reason" >"$(candidate_state_dir "$1")/excluded"
      ;;
    *) usage >&2; die "unknown command: $command" ;;
  esac
}

main "$@"
