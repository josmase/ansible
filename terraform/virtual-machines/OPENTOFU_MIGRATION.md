# OpenTofu Proxmox layout

The native OpenTofu files (`tofu-*.tf`) are now the target VM definition. They
use `bpg/proxmox`, which supports OpenTofu and explicit Proxmox disk blocks.
Workers 204, 205, and 206 share the 250 GiB boot / 750 GiB LINSTOR data layout.

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

1. Create a local tfvars file from `tofu-terraform.tfvars.example`, supplying
   the endpoint, credentials, SSH key, and pinned image checksum.
2. Run `tofu init`, `tofu fmt -check`, and `tofu validate` from this directory.
3. Import existing workers 205 and 206, then require a reviewed plan. A plan
   that replaces either existing VM must be stopped and explicitly approved.
4. Recreate worker 204 only after its backup/staging data and replacement
   window have been confirmed; review the plan before applying.
5. Run the Ansible Kubernetes bootstrap and
   `playbooks/setup/linstor-final-storage.yml`.
6. Validate the node, LINSTOR satellite, CSI provisioning, and workloads before
   removing any old VM backup or staging data.

The legacy CDKTF TypeScript files remain for reference during the transition;
they must not be applied after the OpenTofu state becomes authoritative.
