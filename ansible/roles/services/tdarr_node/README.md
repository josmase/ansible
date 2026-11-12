# Tdarr Node

Deploys the external Tdarr Node, its media NFS mount, and its Compose service.

## Docker mode

`tdarr_docker_mode` selects the daemon. It defaults to `rootful`.

- `rootful` runs `container/docker_setup`, manages the system Docker service,
  and uses `/var/run/docker.sock`.
- `rootless` skips the system Docker setup, enables linger for
  `tdarr_docker_user`, starts that user's `docker.service`, and connects to
  `/run/user/<tdarr_docker_uid>/docker.sock`.

Rootless mode expects Docker's rootless packages and user service unit to
already be installed. Set `tdarr_docker_user` and `tdarr_docker_uid` to the
account that owns that daemon. The Tdarr playbook selects rootless mode for the
external 3080 host in `inventory/group_vars/tdarr_external_nodes.yml`.

## Media mount

The role mounts the OMV NFS export `storage.local.hejsan.xyz:/files` at
`/mnt/storage/files` and exposes it to the container at `/media/files`.
Override `tdarr_nfs_source` if another host uses a different export.

## Paths and credentials

The compose file defaults to `/opt/docker/tdarr-node.yml`; application data
defaults to `/opt/appdata/tdarr-node`; transcode cache defaults to
`/mnt/storage/tdarr-transcode`. Provide `tdarr_api_key` through Ansible Vault.
