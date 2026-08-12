<!-- Context: project-intelligence/technical | Priority: critical | Version: 1.0 | Updated: 2026-08-13 -->

# Technical Domain

**Purpose**: Tech stack, architecture, and configuration patterns for the josmase Ansible infrastructure repo.
**Last Updated**: 2026-08-13

## Quick Reference

**Update Triggers**: Stack changes | New roles/playbooks | Inventory changes | Vault schema changes
**Audience**: Developers, AI agents

## Primary Stack

| Layer        | Technology                            | Version      | Rationale                                                        |
| ------------ | ------------------------------------- | ------------ | ---------------------------------------------------------------- |
| Config mgmt  | Ansible (community)                   | latest (apk) | server provisioning + config; installed in Alpine devcontainer    |
| Inventory    | INI format (`inventory/production.ini`)| —            | single prod inventory; host/group vars, children groups           |
| Secrets      | Ansible Vault (AES256)                | —            | `vault.yml` files; `vault_password_file = $PWD/.vault_pass`       |
| Orchestration| K3s cluster (3 masters, 3 nodes)      | —            | provisioned via k3s-ansible; Flux manages workloads on top        |
| GPU node     | NVIDIA driver / CUDA / container-toolkit | 570 / 12.1 / 3.16.0 | Jellyfin transcode + GPU k8s node           |
| Containers   | Docker + containerd                   | —            | `container/docker_setup` role; systemd maintenance timers         |
| Monitoring   | DCGM Exporter                         | 3.4.4        | Prometheus GPU metrics (`install_dcgm_exporter`)                  |
| Collections  | community.general, ansible.posix, community.docker, kewlfft.aur | docker>=4.0.0 | `collections/requirements.yml` |
| Galaxy roles | geerlingguy.nfs, geerlingguy.samba, gantsign.antigen, sdarwin.vnc | — | third-party roles |
| IaC (aux)    | Terraform + Cloudflare provider       | ~>5.0        | `terraform/dns/` A/CNAME records                                  |
| IaC (aux)    | CDKTF (TypeScript) on Proxmox         | ^0.21.0      | `terraform/virtual-machines/` VM provisioning                     |
| Dev env      | Alpine devcontainer + Oh My Zsh       | 3.23.4       | `curl,git,zsh,python3,ansible,kubectl,k9s,flux,terraform,tofu`    |

## Code Patterns

### Role entry point (`include_tasks` + conditionals)

```yaml
# roles/platform/kubernetes_gpu_setup/tasks/main.yaml
- name: "Check GPU hardware availability"
  include_tasks: check-gpu-hardware.yaml

- name: "Install NVIDIA drivers"
  include_tasks: install-nvidia-drivers.yaml
  when: gpu_type == "nvidia"

- name: "Configure containerd for GPU support"
  include_tasks: configure-containerd-gpu.yaml
  when:
    - gpu_type == "nvidia"
    - containerd_gpu_config | bool
```

### Resilient task (retries + check-mode guard)

```yaml
# roles/platform/kubernetes_gpu_setup/tasks/install-nvidia-drivers.yaml
- name: "Install NVIDIA drivers from Ubuntu repositories"
  apt:
    name:
      - "nvidia-driver-{{ nvidia_driver_version }}"
      - "nvidia-utils-{{ nvidia_driver_version }}"
      - "libnvidia-common-{{ nvidia_driver_version }}"
      - "libnvidia-gl-{{ nvidia_driver_version }}"
    state: present
  become: true
  register: nvidia_driver_install
  until: nvidia_driver_install is succeeded
  retries: 3
  delay: 10
  when: not ansible_check_mode
```

### Distribution-agnostic package install

```yaml
# roles/core/base_setup/tasks/main.yml
- name: Install packages (Distribution-agnostic)
  ansible.builtin.package:
    name: "{{ packages }}"
    state: present
```

## Naming Conventions

| Type       | Convention                       | Example                                  |
| ---------- | -------------------------------- | ---------------------------------------- |
| Files      | lowercase + underscores, `.yml`  | `setup-gpu-kubernetes-node.yml`, `install-nvidia-drivers.yaml` |
| Variables  | snake_case, role-prefixed        | `nfs_mount_point`, `docker_compose_dir`, `nvidia_driver_version` |
| Roles      | domain/role_name                 | `platform/kubernetes_gpu_setup`, `services/ffmpeg_rffmpeg_server` |
| Groups     | function-based, `_` separated    | `k3s_masters`, `storage_servers`, `printer_infrastructure` |
| Vault vars | `vault_` prefix (sensitive)      | `vault_default_sudo_pass`, `vault_docker_registry_password` |

## Code Standards

- Role independence: self-contained, all vars defaulted, never rely on other roles' vars (AGENTS.md)
- Variable precedence: `-e` > playbook vars > host_vars > group_vars > role defaults
- Distribution-agnostic: use `ansible.builtin.package` / `ansible_os_family` conditionals (Debian vs Archlinux)
- Idempotent tasks: `state: present` explicit; use `creates`/`stat` checks; prefer package modules over `command`
- YAML dictionary syntax for tasks; descriptive `name:` on every task; `include_tasks`/`import_tasks` for splitting
- `when` conditions at task level, not play level; `changed_when`/`failed_when` to control status
- Handlers for service restarts; systemd calendar timers for scheduled maintenance
- Validate before run: `ansible-playbook --syntax-check`, `--check`, `--diff`, `--limit`

## Security Requirements

- Secrets only in `vault.yml` (encrypted); `ansible.cfg` points `vault_password_file = $PWD/.vault_pass`
- Never commit unencrypted sensitive data; use vault IDs (`--vault-id prod@prompt`)
- Reference vault via `vars_files` with absolute `{{ playbook_dir }}` paths, not relative
- Separate sensitive/non-sensitive: `group_vars/all/main.yml` references `vault_*` vars, values live in vault
- Explicit `mode`/`owner`/`group` on files; restrictive permissions on sensitive files (e.g. kubeconfig `0600`)
- `ansible_sudo_pass` sourced from vault; kubeconfig fetched from master and rewritten (`127.0.0.1:6443` → master IP)

## 📂 Codebase References

**Implementation**:

- `AGENTS.md` — best-practices guide (directory structure, naming, role independence, vault)
- `ansible/ansible.cfg` — config: inventory, vault_password_file, `become`, pipelining
- `ansible/inventory/production.ini` — prod inventory (k3s, storage, media, GPU, printer, workstation groups)
- `ansible/inventory/group_vars/all/main.yml` — global non-sensitive vars (user, domain, docker, timers)
- `ansible/inventory/group_vars/all/vault.yml` — global encrypted vars (sudo pass, email, domain)
- `ansible/collections/requirements.yml` — Galaxy roles + collection dependencies
- `ansible/playbooks/site.yml` — entry point (validation → setup → maintenance)
- `ansible/playbooks/setup-gpu-kubernetes-node.yml` — NVIDIA GPU k8s node (drivers, containerd, kubeconfig, taints)
- `ansible/playbooks/setup-jellyfin-transcode.yml` — rffmpeg transcode server
- `ansible/playbooks/{setup,maintenance,services}/` — base/storage/printer, updates/reboot, unifi
- `ansible/roles/core/base_setup/` — distro-agnostic packages + zsh config
- `ansible/roles/container/docker_setup/` — Docker + NFS + systemd timers + AppArmor
- `ansible/roles/platform/kubernetes_gpu_setup/` — NVIDIA drivers/container-toolkit/containerd/DCGM
- `ansible/roles/services/ffmpeg_rffmpeg_server/` — Jellyfin FFmpeg 7.1.3 + rffmpeg SSH + hw accel
- `ansible/roles/storage/` — filesystem/mergerfs/snapraid, NFS/SMB client, network shares
- `terraform/dns/main.tf` — Cloudflare A/CNAME records (`*.local`, `media.local`, `gpu.local`, …)
- `terraform/virtual-machines/main.ts` — CDKTF Proxmox VM definitions (k8s masters/nodes, media-server)
- `.devcontainer/Dockerfile` — Alpine toolchain (ansible, terraform/tofu, kubectl, k9s, flux)

## Potential Improvements

- `AGENTS.md` directory-structure example references `inventory/staging.ini`, which does not exist (only `production.ini` is present) — align the doc with the actual inventory

## Related Files

- Business Domain: `AGENTS.md`
- Operations Guide: `ansible/README.md`, role `README.md` files
- Flux cluster: managed in a sibling repo (this repo provisions the underlying nodes)
