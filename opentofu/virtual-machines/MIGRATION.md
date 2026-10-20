# OpenTofu Proxmox layout

The native OpenTofu files are the sole VM definition and use `bpg/proxmox`.
They manage masters 201–203, workers 204–206, and media VM 105.
Workers 204, 205, and 206 share the 250 GiB boot / 750 GiB LINSTOR data layout.
The masters are allocated 7 GiB each; workers are allocated 13 GiB each.

## Provisioning model

The configuration imports the current Ubuntu Noble cloud image directly into
the `Kubernetes` Proxmox datastore with `proxmox_download_file`, then imports
that image into each VM's 250 GiB boot disk. No Proxmox VM template is
required. The second 750 GiB disk is presented as the LINSTOR data disk.

Before the first apply, enable the `Import` content type on the target
datastore and set the SHA-256 for the exact Ubuntu image in
`ubuntu_image_sha256`. Keep credentials and the SSH key in a local, ignored
tfvars file (never commit them).

## Safe rollout

1. Make a backup of the legacy local `terraform.tfstate` and
   `terraform.tfstate.backup`, then move them into this directory. The current
   state already uses OpenTofu provider addresses; do not run
   `tofu state replace-provider`.
2. Create the local, ignored `tofu.tfvars` file from `tofu.tfvars.example`, supplying
   the endpoint, credentials, SSH key, and pinned image checksum.
3. Run `tofu init -lockfile=readonly`, `tofu fmt -check`, and `tofu validate`
   from this directory.
4. Require a reviewed `tofu plan -var-file=tofu.tfvars`. No existing VM may be replaced or destroyed as
   part of adoption; do not apply as part of this migration.

Memory changes require a guest restart. Apply one VM at a time and wait for
both guest health and Kubernetes readiness before proceeding to the next VM;
OpenTofu's `-parallelism=1` only serializes provider operations and does not
guarantee that a restarted guest or its workloads are healthy before the next
operation begins. Keep masters strictly one-at-a-time to preserve etcd quorum.

CDKTF has been removed. Do not reintroduce a second VM definition or apply a
legacy state against these VMs.

## LINSTOR worker expansion

The new `scsi2` disks use serials `linstor-expand-204/205/206` and sizes 1,
96, and 160 GiB on the existing `Kubernetes` datastore. The full plan should
show only three in-place worker updates, each adding its one disk. Refresh the
Proxmox free-space reading before every apply and require at least 200 GiB to
remain after the planned disk is allocated. Current measured free space was
about 476.6 GiB; all three additions together leave about 219.5 GiB.

Apply one VM instance at a time in order 204, 205, 206. For each worker, create
and review a targeted plan for only `proxmox_virtual_environment_vm.worker["N"]`,
apply that saved plan, and verify the guest sees the expected serial and size
before preparing the next worker. Do not apply the un-targeted three-worker
plan. Perform LVM changes with `ansible/playbooks/setup/linstor-final-expand.yml`
only after the isolated metadata rehearsal, off-cluster backups, replica
health checks, and exact per-host confirmation have passed. Never shrink the
thin pool or detach an expansion disk.
