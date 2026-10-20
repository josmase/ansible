# OpenTofu infrastructure

This directory contains the repository's OpenTofu roots. Use OpenTofu 1.13.1
(`tofu`), not Terraform. Each root pins its providers in a committed
`.terraform.lock.hcl` file.

## Roots

- `dns`: Cloudflare DNS records. Copy `tofu.tfvars.example` to the local,
  ignored `tofu.tfvars` file and provide the Cloudflare credentials and zone
  values.
- `virtual-machines`: Proxmox VMs and cloud image. Copy
  `tofu.tfvars.example` to the local, ignored `tofu.tfvars` file and provide
  Proxmox credentials, the image checksum, and the SSH public key.

Run commands from the individual root:

```sh
tofu init -lockfile=readonly
tofu fmt -check
tofu validate
tofu plan -var-file=tofu.tfvars
```

Do not apply a plan until it has been reviewed. The VM root must never replace
or destroy an existing VM during adoption.

Master VM memory is configured per node in `virtual-machines/variables.tf`.
For safe memory reduction, profile K3s first and lower one master allocation
per reviewed plan/apply, verifying etcd quorum and cluster recovery before
continuing. See `../docs/K3S_MASTER_MEMORY.md` for the profile, Go soft-limit,
and acceptance procedure.

## Local state handoff

The previous `terraform/` paths contain ignored local state only; they are not
part of this migration's tracked configuration. Before planning from a new
root, make a backup of its `terraform.tfstate` and `terraform.tfstate.backup`,
then move those files to the matching `opentofu/` root. Run `tofu init` there
and inspect the plan. The existing state already references OpenTofu registry
provider addresses, so do not run `state replace-provider`.
