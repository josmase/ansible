# OpenMediaVault VM 101

VM 101 runs OMV with its data drives attached through two PCIe SAS
controllers. The data migration was performed separately.

- Proxmox VM ID: `101`
- Name: `storage`
- Address: `192.168.1.198`
- DNS name: `storage.local.hejsan.xyz`
- Resources: 4 CPU cores, 8 GiB RAM, 64 GiB virtual system disk

## Managed configuration

The OpenTofu resource defines the system disk and passes through PCI devices
`0000:0b:00.0` and `0000:0d:00.0` as `hostpci0` and `hostpci1`. Both use
PCIe with their option ROM disabled because SeaBIOS could not load the Avago
BIOS. All drives attached to these controllers belong to the guest while it
runs.

Set `storage_vm_os_disk_datastore` in the ignored local `tofu.tfvars` file to
the existing system disk datastore. Before any apply, run `tofu fmt -check`,
`tofu validate`, and `tofu plan -var-file=tofu.tfvars`; review the plan for
unexpected disk, VM, or passthrough changes. Do not recreate the existing VM.
The provider requires root username/password authentication for direct PCI IDs;
check provider permissions before applying.

OMV manages the guest filesystems and shares. The legacy storage Ansible roles
configure Ubuntu storage services and must not be run against this OMV guest.
