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
| Kubelet args (eviction-hard, image-GC 80/70) | `/etc/rancher/k3s/config.yaml` | all 7 k8s nodes | ✅ **Committed 2026-08-24** — `platform/k3s_node_config` role (§3.1); first enforcement run pending (§5) |
| Inotify sysctls (watches 524288, queued 65536) | `/etc/sysctl.d/99-inotify.conf` | all 7 k8s nodes | ✅ **Committed 2026-08-24** — same role; first enforcement run pending (§5) |
| apt autoclean / snap retain / docker prune | not yet applied anywhere | — | ✅ **Committed 2026-08-24** — `core/node_hygiene` role; execution pending (§5) |

## 2. Current repo coverage map

| Playbook / role | Hosts today | Notes |
|---|---|---|
| `playbooks/setup/base.yml` → `core/logging_setup` | `all_servers` | journald+logrotate+docker logging; runtime quirk prevents k3s-host execution (§4) |
| `base.yml` play "Kubernetes storage configuration" → `platform/kubernetes` | `k3s_nodes` only | masters & gpu node NOT covered by this play |
| `playbooks/setup-gpu-kubernetes-node.yml` → `platform/kubernetes` + `kubernetes_gpu_setup` | gpu node | one-shot GPU provisioning |
| masters (201–203) | nothing k8s-related | gap |

## 3. Target design

### 3.1 New role `platform/k3s_node_config` (k8s-node runtime config)

> **Review correction (2026-08-24):** the original draft extended `platform/kubernetes`.
> That role's `nvme.yaml` contains a conditional **`reboot:`** task and `multipath.yaml`
> restarts multipathd — pulling it into hygiene runs would have exposed masters (which
> never ran this role) to surprise reboots. Concerns are therefore separated: this new
> role owns runtime tuning; `platform/kubernetes` keeps its storage-specific behavior.

New task files, included from `tasks/main.yml`:

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
# Managed by ansible (platform/k3s_node_config). Local edits will be overwritten.
# Runtime tuning decided after INC-2026-08-23 storage incident.
kubelet-arg:
  - "eviction-hard={{ k8s_eviction_hard }}"
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
├── tasks/
│   └── main.yml         # apt autoclean drop-in; snap refresh.retain (idempotent,
│                        #   guarded on snap presence); docker-prune cron
│                        #   (flag-gated, absent-file cleanup when disabled)
```

Defaults:
```yaml
hygiene_apt_autoclean_interval: 7
hygiene_snap_refresh_retain: 2
hygiene_docker_prune_enabled: false   # enable per-group (docker_hosts)
hygiene_docker_prune_age: 168h
```
(Inotify/GC thresholds live in `platform/k3s_node_config/defaults` — see §3.1.)

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
  hosts: k3s_cluster
  serial: 1              # REVIEWED: one node at a time -- a handler-driven k3s restart
  become: true           # must never hit several masters in parallel (etcd/API quorum)
  roles:
    - role: platform/k3s_node_config
      tags: [k3s_config, kubelet, sysctl]
    - role: core/node_hygiene
      tags: [hygiene]
```

**Review history:** the first draft used `hosts: k3s_cluster:k3s_gpu_node` because the GPU
node was a stray sibling group. The §6.1 normalization folded `k3s_gpu_node` into
`k3s_cluster`, so plain `hosts: k3s_cluster` now covers all seven nodes. It also swapped
`platform/kubernetes` for `platform/k3s_node_config` — see the correction note in §3.1
(reboot/multipath tasks must not run on masters during hygiene passes).

### 3.5 Journald reconciliation

`core/logging_setup` is now committed (2026-08-24) and writes `/etc/systemd/journald.conf`
directly; the manual drop-ins (`/etc/systemd/journald.conf.d/size.conf`) applied during the
incident carry identical values and override nothing. Once §4 is resolved and the role has
actually executed on k3s hosts, remove the hand-made drop-ins to avoid dual management
(one-line cleanup task in this role).

---

## 4. ~~Blocking issue~~ RESOLVED: the "base.yml runtime quirk" was a misdiagnosis

**Post-mortem (2026-08-25).** The original symptom — k3s hosts matching `--list-hosts`
but vanishing from playbook output/recap under `--tags logging` — does **not reproduce**
on current code. Controlled experiments:

1. **Full-output single-host run** (`base.yml --tags journald --limit
   kubernetes-204.local.hejsan.xyz`, complete log captured): both journald tasks +
   handler executed, recap `ok=3 changed=3 failed=0`, exit 0.
2. **Minimal IP-vs-DNS reproduction** (scratch inventory with one bare-IP host and one
   DNS-named host, identical tagged tasks): byte-for-byte identical behavior —
   ansible-core 2.16.3 has **no naming bias**.

**Root causes of the original observation** (three compounding factors):

1. **Truncated output review.** The diagnostics piped through `tail -30` / inspected with
   `head -30`. Ansible prints recap lines for *every* matched host; the k3s hosts' lines
   were above/below the cut. "Hosts vanished" = lines I never looked at.
2. **Control-node/VCS drift.** At diagnosis time the jumphost checkout (`71411bc`) had no
   `logging_setup` role and no reference to it in `base.yml` — those existed only as
   uncommitted WIP on the desktop. `--tags logging` therefore legitimately executed almost
   nothing (tag-excluded tasks print *no output at all*, unlike condition-skips), producing
   sparse logs that looked like silent failure.
3. **Confounded expectations.** Sparse output + truncation were read together as "hosts are
   being skipped by some mechanism", when each was independently mundane.

**Guardrails adopted:**
- Always capture full playbook output to a file and inspect the complete recap — never
  diagnose from `tail`-truncated pipelines.
- Before diagnosing runtime behavior, confirm control node and VCS are at the same commit
  (`git status --short && git log -1` on both sides) — untracked roles/manifests silently
  change what a playbook means.
- Tag-excluded tasks emit no output; empty-looking runs under `--tags` usually mean the
  tag selected nothing, not that hosts failed.

No code change required. The dedicated hygiene playbook (§3.4) remains the preferred
entry point regardless, since it targets `k3s_cluster` explicitly and carries its own
serial/restart semantics.

## 5. Rollout sequence

> ## ✅ EXECUTED 2026-08-25 — all gates passed
>
> - Jumphost synced to `7c5da01`; become verified working (pre-existing
>   `group_vars/all/vault.yml` on the jumphost supplies the sudo password).
> - Terraform: provider pinned to v4, executed with terraform **1.13.1**
>   (side-by-side at `~/bin/terraform131`; system default remains 1.5.2 — too old for
>   `required_version >= 1.6`). All records applied/imported; final plan = "No changes".
>   New `kubernetes-201..206.local.hejsan.xyz` records resolve via public DNS.
> - Playbook: workers → gpu → masters one-at-a-time. Every node `ok=8 changed=4 failed=0`
>   (config template + sysctl template + apt drop-in + snap retain), **no restarts**
>   (`k3s_restart_enabled=false`), all nodes Ready after each stage.
> - Idempotency: second run on workers = **changed=0**.
> - Drift probe: deleted `/etc/sysctl.d/99-inotify.conf` on kn204 → re-run restored it
>   (`changed=2`) → enforcement chain proven.
>
> Remaining: none for this plan. Follow-ups live in §7.

| Step | Action | Gate |
|---|---|---|
| 1 | Implement §3 locally; `ansible-playbook --syntax-check`; yamllint | clean |
| 2 | Commit & push this repo; `git pull` on jumphost `~/repo/ansible` | jumphost at HEAD |
| 3 | Run §4 diagnostics; record findings in this doc | quirk understood/worked around |
| 4 | Execute hygiene playbook on **workers first**: `--limit k3s_nodes` | changed=expected; nodes Ready |
| 5 | GPU node: `--limit k3s_gpu_node` | Ready; jellyfin unaffected |
| 6 | Masters **one at a time** — inventory names are now the DNS aliases: `--limit kubernetes-201.local.hejsan.xyz`, then `-202`, `-203` | all Ready after each |
| 7 | Per-node functional gate after any handler-driven restart: `kubectl get --raw "/api/v1/nodes/<node>/proxy/configz"` shows GC 80/70 + eviction-hard; `kubectl get node <node>` Ready | verified per node |
| 8 | Idempotency: re-run same command | second run changed=0 |
| 9 | Drift probe: delete `/etc/sysctl.d/99-inotify.conf` on kn206, re-run, confirm restored | converged |

**First-run expectations (review correction):** the managed templates add a header comment
that the hand-applied files lack, so step 4–6 **will** report the config task as `changed`
on every node — that is correct and does not mean drift. With `k3s_restart_enabled=false`
(the default) no restart follows: safe, because the running kubelet already uses these
exact values. Enable restarts (`-e k3s_restart_enabled=true`) only on runs that actually
change thresholds. The "mostly ok" claim in earlier drafts was wrong for exactly this
reason.

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
    hostname/IP, the two inventories are related but not identical. Name mapping (after the
    2026-08-24 normalization):

    | This repo's inventory | ansible_host | Kubernetes node name | k3s service |
    |---|---|---|---|
    | `kubernetes-201.local.hejsan.xyz`–`203` | .201–.203 | `kubernetes-master-201`–`203` | `k3s` |
    | `kubernetes-204.local.hejsan.xyz`–`206` | .204–.206 | `kubernetes-node-204`–`206` | `k3s-node` |
    | `gpu.local.hejsan.xyz` | 192.168.1.119 | `ubuntu-ms-7977` | `k3s-node` |

    The `k8s_node_name` hostvar carries the Kubernetes node name for drain/cordon/configz
    operations; `k3s_service_name` group vars distinguish server vs agent units.

### 6.1 Naming normalization + DNS + secrets (executed 2026-08-24)

1. **Inventory aliases** renamed from bare IPs to `kubernetes-<octet>.local.hejsan.xyz`
   (`ansible_host` still carries the IP, so nothing breaks before DNS is applied).
2. **Group topology fixed:** `k3s_gpu_node` is now a child of `k3s_cluster`, so
   `hosts: k3s_cluster` covers all seven nodes.
3. **Duplicate identity removed:** the GPU node was listed twice (`gpu.local.hejsan.xyz`
   and `ubuntu-ms-7977.localdomain`) — a double-execution hazard for any broad play.
   `[printer_monitors]` now references `gpu.local.hejsan.xyz`; the Ollama/Wyoming plays in
   `base.yml` target `k3s_gpu_node`.
4. **DNS records** added to `terraform/dns/main.tf`: `kubernetes-201..206.local` →
   .201–.206 (optional `kubernetes-119.local` left commented). ⚠️ Records are *code only*
   until `terraform apply` runs with the Cloudflare token/state.
5. **Secrets:** `k3s_token` from the gitignored k3s-ansible inventory is now vaulted at
   `ansible/inventory/group_vars/k3s_cluster/vault.yml` (encrypted with the repo's
   `.vault_pass` on the jumphost); non-secret install parameters are in `vars.yml`.
   Decryption requires the jumphost's `.vault_pass`.

## 7. Out of scope / follow-ups

- Vault-encrypted backup of `k3s-ansible/inventory/my-cluster/` (see §6.2) — the cluster's
  install parameters and token currently have a single point of failure (the jumphost).
- Longhorn settings remain Flux-managed (do not duplicate here).
- Recurring Artifactory crash-loops (2× in 2 days) — separate investigation.
- GPU-node inotify/journald/kubelet-arg values were applied manually on 2026-08-24; §3
  codifies them going forward.
