# K3s node installation

Installs a fresh K3s server or agent. The role refuses to adopt unowned K3s binaries, services, configuration, or data. It never performs upgrades or automatically changes an existing node's lifecycle configuration. Runtime tuning remains owned by `platform/k3s_node_config` in `config.yaml`; this role uses `config.yaml.d/20-ansible-node.yaml`.

## Inventory inputs

Set `k3s_node_install_mode` explicitly to `server_init`, `server_join`, or `agent_join`. Supply `k3s_node_install_version`, `k3s_node_install_name`, `k3s_node_install_ip`, `k3s_node_install_interface`, and `k3s_node_install_token` (from Ansible Vault). For joins, supply `k3s_node_install_server_url` and `k3s_node_install_verify_host`, an existing control plane accessible to Ansible. The role authenticates the endpoint against the verification host CA, checks all control-plane node versions before joining, and waits for the node to become Ready. Joins require a secure `K10<CA SHA256>::<credentials>` token for a self-signed K3s server CA; short tokens are rejected. The production vault contains the secure form; do not print or commit plaintext credentials. Server settings include `k3s_node_install_tls_sans` and `k3s_node_install_disabled_components`, `k3s_node_install_cluster_cidr`, `k3s_node_install_service_cidr`, `k3s_node_install_cluster_dns`, and `k3s_node_install_cluster_domain`. Additional server-only K3s options can be passed as `k3s_node_install_server_settings` (a mapping); lifecycle-owned keys and reset are rejected. Configure labels and taints using `k3s_node_install_labels` and `k3s_node_install_taints`.

Example:

```yaml
k3s_node_install_mode: agent_join
k3s_node_install_version: v1.37.2+k3s1
k3s_node_install_name: worker-example
k3s_node_install_ip: 192.0.2.10
k3s_node_install_interface: eth0
k3s_node_install_server_url: https://192.0.2.1:6443
k3s_node_install_verify_host: control-plane-example
k3s_node_install_token: "{{ k3s_token }}"
```

A server inventory example (replace all values with the actual cluster settings):

```yaml
k3s_node_install_mode: server_join
k3s_node_install_version: v1.37.2+k3s1
k3s_node_install_name: server-example
k3s_node_install_ip: 192.0.2.11
k3s_node_install_interface: eth0
k3s_node_install_server_url: https://192.0.2.1:6443
k3s_node_install_verify_host: existing-server
k3s_node_install_token: "{{ k3s_token }}"
k3s_node_install_tls_sans: [192.0.2.1]
k3s_node_install_disabled_components: [servicelb, traefik, local-storage]
```

For a new cluster, set `server_init` and `k3s_node_install_allow_cluster_init: true` only on the initial server and provide the shared token. Set `server_join` for later servers and supply the same cluster settings and endpoint. Check the live cluster's critical server settings and recovery procedures before any changes. The role does not install kube-vip, add-ons, or operating-system network/DNS configuration.

Run from `ansible/` and always use a single-host `--limit`. Review inventory, DNS, version and recovery readiness first. `--syntax-check` and `--check --diff` are useful previews; check mode cannot establish that installation or readiness will succeed. An interrupted install retains an `in_progress` marker and fails closed on a rerun. Inspect its data and cluster registration and follow a reviewed recovery plan; do not simply delete the marker. A completed installation can be checked again only when its identity, binary checksum, service, fragments and supported runtime configuration match and its service is already running; the role will not restart it. Use the separate rolling-upgrade process to change versions. The marker retains the original installation release; a later release is accepted only after inventory is updated and the current binary checksum and control-plane version are verified.

The role does not adopt existing nodes. To migrate existing installations, first capture their full effective configuration and a verified recoverable snapshot; design and review a separate migration that preserves service and data. Never remove existing K3s state to make this role pass.

Node 213 is a verified diskless worker in the production cluster and worker aggregates. It can mount remote LINSTOR volumes but is excluded from local replica placement. Its Ubuntu 26.04 sudo prompt uses the repository `sudo_wrapped` become plugin, configured in host variables.

Example entry points, run from `ansible/` only after reviewing the target and inventory:

```sh
ansible-playbook playbooks/setup/kubernetes-worker-onboarding.yml --limit kubernetes-213.local.hejsan.xyz
ansible-playbook playbooks/k3s-cluster.yml --limit server-example
```

Before joining an agent or server, the role rejects a node name already registered in the cluster. After starting the service it waits for a Ready node with the requested internal IP and version. A stale or incomplete prior join must be investigated rather than removed automatically.

## Server join recovery gate

Server joins require `k3s_node_install_allow_server_join: true`, a recent regular snapshot file on `k3s_node_install_verify_host`, its SHA-256 in `k3s_node_install_recovery_snapshot_sha256`, and the same digest in `k3s_node_install_recovery_restore_verified_sha256` as an explicit operator attestation that this exact snapshot was restored and verified independently. Set `k3s_node_install_recovery_snapshot_path`; the default maximum file age is 24 hours. The role verifies file age, digest, inventory, node readiness and etcd leader/proposal metrics before and after the join. It cannot verify the claimed restore test or off-host backup independently. Keep the snapshot and corresponding server token backed up securely.

The role blocks a join resulting in an even number of etcd members unless `k3s_node_install_confirm_even_etcd_members: true` is explicitly supplied after reviewing the quorum and replacement plan. Inventory must list the target plus exactly the currently healthy control-plane and etcd members; the preflight excludes the target when checking current membership. K3s self-signed CA fingerprints are supported; custom CA chains require a separately reviewed implementation.

## Full storage exclusion gate

`k3s_node_install_storage_exclusion_label` fully excludes a node from Piraeus: cluster and daemonset affinity must exclude it, and postflight requires no Piraeus pods. Use `k3s_node_install_storage_replica_exclusion_label` for a diskless client that may attach remote LINSTOR volumes but cannot host local replicas. Every Piraeus storage-pool affinity alternative must exclude the marker before K3s starts; postflight then waits for the satellite to become Available and Configured. These modes are mutually exclusive. If readiness or policy verification fails after a fresh join, the role attempts to cordon the node; verify the cordon succeeded and inspect the storage state. Cordon does not stop running pods or necessarily prevent DaemonSets. A policy change between checks remains possible, so monitor the cluster during onboarding.

The etcd health checks use `127.0.0.1:2381` on each server. K3s serves etcd metrics on loopback by default; `etcd-expose-metrics` additionally exposes metrics on the client interface and is not required for these checks. Keep the default unless external access is deliberately configured and secured.

For the full map of K3s installation, runtime configuration, upgrade and maintenance roles, see [K3s roles and workflows](../../../../docs/K3S_ROLES.md).
