# Network Share Setup Role

This role configures network sharing services (NFS and Samba) on storage servers.

## Requirements

- Ansible 2.9 or higher
- A Linux system with NFS and Samba packages installed (handled by dependencies)

## Role Variables

```yaml
smb_exports:       # List of Samba shares to configure
  - name: share_name
    content: |
      [share_name]
      path = /path/to/share
      ...
```

## Dependencies

- geerlingguy.samba
- geerlingguy.nfs

## Example Playbook

```yaml
- hosts: storage_servers
  roles:
    - geerlingguy.samba
    - geerlingguy.nfs
    - storage/network_share_setup
  vars:
    smb_exports:
      - name: public
        content: |
          [public]
          path = /srv/storage
          read only = no
          guest ok = yes
```