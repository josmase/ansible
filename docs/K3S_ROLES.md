# K3s roles and workflows

Run Ansible commands from the repository's `ansible/` directory. Configure each node in `inventory/production.ini` and the relevant `group_vars` and `host_vars`. Check the live cluster version, DNS, access and recovery plan before a change. Use a single-host `--limit` for installation and node hygiene.

| Purpose | Role | Entry point |
|---|---|---|
| Install or join a fresh server | `platform/k3s_node_install` | `playbooks/k3s-cluster.yml` |
| Install or join a fresh worker | `platform/k3s_node_install` | `playbooks/setup/kubernetes-worker-onboarding.yml` |
| Kubelet, sysctl and runtime hygiene | `platform/k3s_node_config`, plus host hygiene roles | `playbooks/setup/kubernetes-node-hygiene.yml` |
| Optional worker zram | `platform/memory_compression` | `playbooks/setup/kubernetes-worker-memory-compression.yml` |
| Rolling K3s and kube-vip upgrade | `platform/k3s_rolling_upgrade` | `playbooks/maintenance/k3s_upgrade_preflight.yml`, then `playbooks/maintenance/k3s_rolling_upgrade.yml` |
| Application preparation and restoration for a maintenance window | `platform/k3s_application_maintenance` | `playbooks/maintenance/k3s_application_maintenance.yml` |
| GPU driver and runtime configuration | `platform/kubernetes_gpu_setup` and its prerequisites | `playbooks/setup-gpu-kubernetes-node.yml` after the node joins |
| One-time legacy MetalLB handoff | `platform/metallb_flux_handoff` | `playbooks/maintenance/metallb_flux_handoff.yml`; only for the documented migration |

The installer is the only K3s install/join implementation. It writes `config.yaml.d/20-ansible-node.yaml`; runtime tuning owns `config.yaml`. Existing unowned K3s installations are rejected rather than adopted. Read the [installer README](../ansible/roles/platform/k3s_node_install/README.md) for required inputs, secure tokens, recovery gates and the storage policy checks. The [runtime role README](../ansible/roles/platform/k3s_node_config/README.md) describes its restart guard.

For a fresh worker, review inventory and the target, run the worker entry point with `--limit <host>`, and verify the node and its scheduling/storage policy. Apply optional hygiene or GPU configuration separately after reviewing their scope. The `platform/kubernetes` role used by base and GPU setup manages storage prerequisites, including tasks that can restart services or reboot; it is not the K3s join role and should not be included automatically for every new worker.

For an upgrade, follow the [rolling-upgrade README](../ansible/roles/platform/k3s_rolling_upgrade/README.md), including its snapshot and one-node-at-a-time safeguards. Once the control plane is verified at the new version, update the shared `k3s_node_install_version` inventory value before onboarding or checking nodes with the installer. The installer records the original install version in its ownership marker and checks the current release against inventory and the upstream binary checksum; do not edit the marker manually.
