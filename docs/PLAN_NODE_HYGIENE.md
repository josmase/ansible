# Plan: Bring Node Runtime/Hygiene Config Under Ansible Management

Closes the gap exposed by the 2026-08-24 work session: several node-level configs were
applied manually (via SSH chains) during incident response and the Jellyfin PVC migration.
They currently exist **only on the machines** — a rebuilt node loses them, and there is no
idempotent enforcement. This plan folds them into this repo following existing conventions.

Related docs (flux repo): `docs/INCIDENT_2026-08-23_GPU_NODE_STORAGE.md`,
`docs/PREVENTION_PLAN_GPU_NODE_STORAGE.md`.

---

## 1. Unmanaged state inventory (as applied by hand)

| Config | File(s) | Hosts | Already codified here? |
|---|---|---|---|
| Journald caps (500M/128M) | `/etc/systemd/journald.conf.d/size.conf` | all Ubuntu servers (9) | ✅ **Committed 2026-08-24** — `core/logging_setup` (+ its `base.yml` wiring) had existed only as untracked WIP on the desktop and was absent from the jumphost checkout; now in Git. First real execution against k3s hosts still pending (§4) |
| Kubelet args (eviction-hard, image-GC 80/70) | `/etc/rancher/k3s/config.yaml` | all 7 k8s nodes | ❌ No |
| Inotify sysctls (watches 524288, queued 65536) | `/etc/sysctl.d/99-inotify.conf` | all 7 k8s nodes | ❌ No |
| apt autoclean / snap retain / docker prune | not yet applied anywhere | — | ❌ No (prevention plan Phase 3 leftovers) |

## 2. Current repo coverage map

| Playbook / role | Hosts today | Notes |
|---|---|---|
| `playbooks/setup/base.yml` → `core/logging_setup` | `all_servers` | journald+logrotate+docker logging; runtime quirk prevents k3s-host execution (§4) |
| `base.yml` play "Kubernetes storage configuration" → `platform/kubernetes` | `k3s_nodes` only | masters & gpu node NOT covered by this play |
| `playbooks/setup-gpu-kubernetes-node.yml` → `platform/kubernetes` + `kubernetes_gpu_setup` | gpu node | one-shot GPU provisioning |
| masters (201–203) | nothing k8s-related | gap |

## 3. Target design

### 3.1 Extend `platform/kubernetes` role (k8s-node runtime config)

New task files, included from `tasks/main.yaml`:

**`tasks/kubelet-config.yaml`**
```yaml
---
- name: Ensure k3s config dir exists
  ansible.builtin.file:
    path: /etc/rancher/k3s
    state: directory
    mode: "0755"

- name: Manage k3s kubelet args
  ansible.builtin.template:
    src: k3s-config.yaml.j2
    dest: /etc/rancher/k3s/config.yaml
    mode: "0644"
    backup: true          # safety net if a bad template ever breaks a node's k3s
  notify: Restart k3s
```

> **Recovery note:** if a pushed template ever prevents k3s from starting, the pre-change
> file is retained next to it as `config.yaml.<date>-~~~~` (backup: true). Restore it,
> `systemctl restart {{ k3s_service_name }}`, fix the template in Git before re-running.

**`templates/k3s-config.yaml.j2`**
```yaml
# Managed by ansible (platform/kubernetes). Local edits will be overwritten.
# Node-local runtime tuning decided after INC-2026-08-23 storage incident.
kubelet-arg:
  - "eviction-hard=nodefs.available<15%,imagefs.available<15%,nodefs.inodesFree<10%"
  - "image-gc-high-threshold={{ k8s_image_gc_high_threshold }}"
  - "image-gc-low-threshold={{ k8s_image_gc_low_threshold }}"
```

⚠️ **Merge caveat:** k3s reads exactly one `config.yaml`. All seven nodes currently have no
other content in it, so managing the whole file is safe *today*. If server-side settings are
ever needed on masters, extend this same template (single source of truth) rather than
hand-editing.

**`tasks/sysctl-inotify.yaml`**
```yaml
---
- name: Install inotify tuning
  ansible.builtin.template:
    src: sysctl-inotify.conf.j2
    dest: /etc/sysctl.d/99-inotify.conf
    mode: "0644"
  notify: Reload sysctl
```

**`templates/sysctl-inotify.conf.j2`**
```
# Managed by ansible. Required for large media libraries (Jellyfin NFS watchers).
fs.inotify.max_user_watches = {{ inotify_max_user_watches }}
fs.inotify.max_queued_events = {{ inotify_max_queued_events }}
```

**`handlers/main.yaml`**
```yaml
---
- name: Restart k3s
  ansible.builtin.systemd:
    name: "{{ k3s_service_name }}"
    state: restarted
  when: k3s_restart_enabled | bool

- name: Reload sysctl
  ansible.builtin.command: sysctl --system
  changed_when: true
```

### 3.2 New role `core/node_hygiene` (OS-level housekeeping)

```
roles/core/node_hygiene/
├── defaults/main.yml
├── handlers/main.yml
├── tasks/
│   ├── main.yml
│   ├── apt.yml          # APT::Periodic AutocleanInterval=7 (drop-in)
│   ├── snap.yml         # snap set system refresh.retain=2  (when snap present)
│   └── docker-prune.yml # cron: docker system prune -f --filter "until=168h" (when docker)
```

Defaults:
```yaml
hygiene_apt_autoclean_interval: 7
hygiene_snap_refresh_retain: 2
hygiene_docker_prune_enabled: false   # enable per-group (docker_hosts)
hygiene_docker_prune_age: 168h
inotify_max_user_watches: 524288
inotify_max_queued_events: 65536
k8s_image_gc_high_threshold: 80
k8s_image_gc_low_threshold: 70
k8s_eviction_hard: "nodefs.available<15%,imagefs.available<15%,nodefs.inodesFree<10%"
```

### 3.3 Service-name handling (masters vs workers)

Masters run `k3s.service`, workers/gpu run `k3s-node.service`. Set once in inventory
(`inventory/production.ini`) as group vars rather than detecting at runtime:

```ini
[k3s_masters:vars]
k3s_service_name=k3s

[k3s_nodes:vars]
k3s_service_name=k3s-node

[k3s_gpu_node:vars]
k3s_service_name=k3s-node
```

(`k3s_restart_enabled=false` default in the role; set true explicitly for restart runs so a
plain lint/apply never bounces the control plane accidentally.)

### 3.4 New playbook `playbooks/setup/kubernetes-node-hygiene.yml`

```yaml
---
- name: Kubernetes node runtime hygiene (kubelet args, sysctls, OS housekeeping)
  hosts: k3s_cluster:k3s_gpu_node
  serial: 1              # REVIEWED: one node at a time -- a handler-driven k3s restart
  become: true           # must never hit several masters in parallel (etcd/API quorum)
  roles:
    - role: platform/kubernetes
      tags: [kubernetes]
    - role: core/node_hygiene
      tags: [hygiene]
```

⚠️ **Review correction:** `hosts: k3s_cluster` alone would **silently skip the GPU node** —
`k3s_gpu_node` is a sibling group, not a child of `k3s_cluster` (verified against
`inventory/production.ini`). The union pattern `k3s_cluster:k3s_gpu_node` covers all seven.
`serial: 1` additionally prevents parallel k3s restarts across masters.

### 3.5 Journald reconciliation

`core/logging_setup` is now committed (2026-08-24) and writes `/etc/systemd/journald.conf`
directly; the manual drop-ins (`/etc/systemd/journald.conf.d/size.conf`) applied during the
incident carry identical values and override nothing. Once §4 is resolved and the role has
actually executed on k3s hosts, remove the hand-made drop-ins to avoid dual management
(one-line cleanup task in this role).

---

## 4. Blocking issue: base.yml runtime quirk on k3s hosts (diagnose first)

Observed 2026-08-24 from the jumphost (`~/repo/ansible`, commit 71411bc):
`ansible-playbook playbooks/setup/base.yml --tags logging --limit <k3s host>` printed the
PLAY header, executed **zero tasks**, produced an **empty recap**, exit 0 — while
`--list-hosts` showed the host matched and `ansible <host> -m ping` succeeded. Storage/media
hosts ran fine in the same invocation.

Diagnostics to run before relying on any new playbook:
1. `ansible-playbook --version` — confirm ansible-core version (old cores have subtle
   limit/group bugs).
2. Single host, max verbosity: `ansible-playbook playbooks/setup/base.yml --limit 192.168.1.201 -vvvv`
   and inspect whether tasks evaluate as skipped vs. hosts vanishing.
3. Check for inventory-level oddities affecting IP-named hosts (the three groups that DID
   work use DNS names; every failing host is a bare IP — test renaming one host in a scratch
   inventory to confirm).
4. Verify become credentials actually resolve for k3s hosts: the gpu node's sudo requires a
   password, `ansible.cfg` sets `become_ask_pass=False`, so a vaulted
   `ansible_become_pass` must exist for these groups — confirm with
   `ansible 192.168.1.201 -m ping -b` (a become failure would surface as failed tasks,
   though it does not alone explain the empty recap).
5. Workaround if unresolvable quickly: always execute the new hygiene playbook directly
   (`playbooks/setup/kubernetes-node-hygiene.yml`) instead of via base.yml tags — it targets
   the k8s nodes explicitly and was exercised end-to-end at rollout time.

## 5. Rollout sequence

| Step | Action | Gate |
|---|---|---|
| 1 | Implement §3 locally; `ansible-playbook --syntax-check`; yamllint | clean |
| 2 | Commit & push this repo; `git pull` on jumphost `~/repo/ansible` | jumphost at HEAD |
| 3 | Run §4 diagnostics; record findings in this doc | quirk understood/worked around |
| 4 | Execute hygiene playbook on **workers first**: `--limit k3s_nodes` | changed=expected; nodes Ready |
| 5 | GPU node: `--limit k3s_gpu_node` | Ready; jellyfin unaffected |
| 6 | Masters **one at a time** — ⚠️ inventory names are bare IPs: use `--limit 192.168.1.201`, then `.202`, then `.203` (`kubernetes-master-20x` are Kubernetes node names, **not** ansible inventory names — a wrong pattern matches zero hosts silently) | all Ready after each |
| 7 | Per-node functional gate after any handler-driven restart: `kubectl get --raw "/api/v1/nodes/<node>/proxy/configz"` shows GC 80/70 + eviction-hard; `kubectl get node <node>` Ready | verified per node |
| 8 | Idempotency: re-run same command | second run changed=0 |
| 9 | Drift probe: delete `/etc/sysctl.d/99-inotify.conf` on kn206, re-run, confirm restored | converged |

Note: since the live nodes already carry the desired state (applied manually), the first
run should report mostly `ok` — its purpose is enforcement + codification, not change.
Force one real change (step 9 drift probe) to prove the chain works.

## 6. Relationship to `k3s-ansible` (cluster installation)

The Kubernetes cluster itself is installed/managed by **[techno-tim/k3s-ansible](https://github.com/techno-tim/k3s-ansible)**,
included here as a git submodule at `vendor/k3s-ansible`, pinned to
`2fad0a8db698b320a5440d4506f1ffb543402182` — the exact commit used to build the current
cluster (k3s v1.30.2+k3s2).

**Where things actually live:** the working checkout is on the jumphost at
`~/repo/k3s-ansible` (ubuntu@ansible.local.hejsan.xyz). Its site-specific inventory,
`inventory/my-cluster/`, is **gitignored upstream** and therefore exists *only on the
jumphost*:

| File | Contents of note |
|---|---|
| `inventory/my-cluster/hosts.ini` | masters 192.168.1.201–203, nodes .204–206 + `gpu.local.hejsan.xyz` |
| `inventory/my-cluster/group_vars/all.yml` | k3s version, kube-vip endpoint `192.168.1.200`, **`k3s_token` (plaintext secret)**, flannel iface, master taint `node-role.kubernetes.io/master=true:NoSchedule`, `--disable traefik servicelb` (both come from Flux instead) |
| `kubeconfig` | cluster-admin kubeconfig (gitignored) |

Operational scripts in that checkout: `deploy.sh` (site.yml), `reset.yml` (full teardown),
`reboot.yml`.

**Consequences / rules:**
1. This repo manages the cluster *after* install (Flux for workloads, this repo for node
   config). Node rebuild/reinstall = run k3s-ansible from the jumphost, not anything here.
2. The jumphost's `my-cluster/` inventory is the **only copy** of the k3s token and install
   parameters. Recommended follow-up: keep a vault-encrypted copy under
   `ansible/inventory/group_vars/` (or a backup) so the cluster is recoverable if the
   jumphost dies.
 3. Upgrading the toolkit = `cd vendor/k3s-ansible && git fetch && git checkout <new-tag>`
    in a commit of its own; never let it float to master automatically.
 4. Because `my-cluster/hosts.ini` uses bare IPs while this repo's inventory names hosts by
    hostname/IP, the two inventories are related but not identical. Name mapping:

    | This repo's inventory | ansible_host | Kubernetes node name | k3s service |
    |---|---|---|---|
    | `192.168.1.201`–`203` | same IP | `kubernetes-master-201`–`203` | `k3s` |
    | `192.168.1.204`–`206` | same IP | `kubernetes-node-204`–`206` | `k3s-node` |
    | `gpu.local.hejsan.xyz` | 192.168.1.119 | `ubuntu-ms-7977` | `k3s-node` |

    Recommended follow-up: alias inventory entries to the Kubernetes node names so both
    systems share one vocabulary, and fold `k3s_gpu_node` into `k3s_cluster`.

## 7. Out of scope / follow-ups

- Vault-encrypted backup of `k3s-ansible/inventory/my-cluster/` (see §6.2) — the cluster's
  install parameters and token currently have a single point of failure (the jumphost).
- Longhorn settings remain Flux-managed (do not duplicate here).
- Recurring Artifactory crash-loops (2× in 2 days) — separate investigation.
- GPU-node inotify/journald/kubelet-arg values were applied manually on 2026-08-24; §3
  codifies them going forward.
