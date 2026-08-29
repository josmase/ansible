# Plan: Remediate NFS Mount Issues on the Media Service

Closes the gap exposed by the 2026-08-23 GPU-node storage incident and the Jellyfin PVC
migration. The **flux** repo already carries a 5-layer defense-in-depth for Jellyfin's NFS
consumption (CSI driver, probes+alerts, DaemonSet recovery agent, init-container pre-flight
check, log-watcher). The **ansible** media service (Docker hosts `media.local.hejsan.xyz`
192.168.1.105 and 192.168.1.213) has **none** of that: only a crude hourly `df`-grep handler,
`defaults`+`_netdev` mount options, no pre-flight check, no node-level recovery agent, and no
alerting.

This plan brings the ansible media service up to a comparable level of resilience, scoped to
the ansible repo. **Phase A and Phase B are implemented and deployed** (2026-08-29); Phase C
and D are deferred.

> **Deployment status (2026-08-29):** Phase A + B fully deployed and verified on
> `media.local.hejsan.xyz` (192.168.1.105). See §8 for the deployment record, including four
> additional pre-existing bugs found and fixed during rollout.

Related docs (flux repo): `docs/INCIDENT_2026-08-23_GPU_NODE_STORAGE.md`,
`docs/PREVENTION_PLAN_GPU_NODE_STORAGE.md`, `.omo/plans/nfs-stale-recovery-plan.md`,
`docs/MEDIA_SPLIT_PLAN.md`. Related ansible doc: `docs/PLAN_NODE_HYGIENE.md`.

---

## 0. Root-cause summary (from investigation)

| Factor | Detail |
|---|---|
| Shared root-squashed export | `storage.local.hejsan.xyz:/` (`fsid=0`), root-squashed to `anonuid=1000/anongid=1000`, consumed by many concurrent clients (flux k8s + ansible Docker hosts) |
| Aggressive caching | `hard` mounts + default attribute/dentry caching → stale handles when one client deletes/moves a file another client has cached |
| `hard` mounts hang | A hung server leaves processes stuck in uninterruptible sleep (D-state); no `soft`/`timeo` to fail fast |
| mergerfs near-full pool | ~98% full (2.4T free of 105T) over 9 LUKS drives → pressure + slow metadata ops |
| Single-disk GPU node | The GPU node's local disk is a single point of failure for its NFS cache |

## 1. Reference: the flux 5-layer pattern (already proven)

| Layer | Mechanism | Applies to Docker hosts? |
|---|---|---|
| L5 | CSI NFS driver (`csi-driver-nfs`) with stale-mount recovery + `fsGroupPolicy: None` | No (k8s-only) |
| L4 | Probes (startup/liveness/readiness) + PrometheusRules alerts | Partially (no Prometheus on Docker hosts → Gotify instead) |
| L3 | `nfs-stale-mount-recovery` DaemonSet agent (hung-mount force-unmount + stale-handle dentry-cache drop) | **Yes** → ported as systemd timer (Phase B) |
| L2 | `nfs-stale-check` init container on all 8 NFS consumers | **Yes** → ported as pre-flight check in `start.sh` (Phase A) |
| L1 | log-watcher sidecar (jellyfin only) | No (jellyfin-specific) |

Proven mount options (from the Jellyfin media PV):
`soft,bg,intr,nfsvers=4.1,proto=tcp,timeo=30,retrans=3,actimeo=5,lookupcache=none,noatime,nodiratime`.

---

## 2. Phase A — Harden the NFS client mount ✅ IMPLEMENTED

### A1. Hardened mount options (`roles/storage/nfs_client_setup`)

- **New `defaults/main.yml`** defines `nfs_client_mount_opts` (role-independent, overridable):
  ```
  soft,bg,intr,nfsvers=4.1,proto=tcp,timeo=30,retrans=3,actimeo=5,lookupcache=none,noatime,nodiratime
  ```
- **`tasks/main.yaml`** legacy single-mount path now uses `{{ nfs_client_mount_opts }}`
  instead of the old `soft,lock,vers=4`.
- **`inventory/group_vars/jellyfin_transcode_servers.yml`** `nfs_mounts[].opts` updated to the
  same hardened set (both `/mnt/jellyfin-cache` and `/mnt/storage/files`).

> The media service mount (`/mnt/storage` ← `storage.local.hejsan.xyz:/`) is applied by
> `nfs_client_setup` via `base.yml`/`storage.yml` (`nfs_mount_point: {{ system.storage_dir }}`),
> so A1 hardens it directly.

### A2. Pre-flight NFS check in `start.sh` (`roles/container/docker_setup`)

`templates/scripts/start.sh` now runs `check_nfs_mount()` before `docker compose up`:
- `ls -d ${docker_storage_dir}` with a 5s timeout.
- On `Stale file handle` / `Input/output error` / `Connection timed out` / `Host is down`:
  force-lazy-unmount, remount, then proceed.
- On unrecoverable failure: **abort** `docker compose up` with a clear error (prevents
  starting containers that immediately fail).

This is the Docker-host port of the flux `nfs-stale-check` init container (L2).

### A3. Upgraded `staleFileHandleHandler.sh` (hourly)

`templates/scripts/staleFileHandleHandler.sh` upgraded from the crude `df`-grep to also:
- Detect hung mounts at `${docker_storage_dir}` (timeout-bounded `ls`).
- Force-unmount + remount hung mounts.
- Drop the VFS dentry/inode cache (`echo 2 > /proc/sys/vm/drop_caches`) on stale handles.

Kept on the existing hourly timer.

---

## 3. Phase B — Node-level recovery agent + alerts ✅ IMPLEMENTED

### B1. New recovery agent `nfsStaleRecovery.sh` (`roles/container/docker_setup`)

`templates/scripts/nfsStaleRecovery.sh` is a self-contained port of the flux DaemonSet agent
(`nfs-stale-agent.sh`), adapted for a Docker host (no `/host` mount, no container):
- Scans `/proc/mounts` for all NFS mounts.
- **Hung-mount scan:** timeout-bounded `ls` per mount → force-lazy-unmount + remount.
- **Stale-handle scan:** bounded `find` (maxdepth 3) capturing stderr → drop dentry cache.
- **Storage-dir sanity:** checks `${docker_storage_dir}` responsiveness.
- On any issue: sends a **Gotify** alert (see B3).

### B2. Systemd timer (every 5 minutes)

- New `templates/timers/nfsStaleRecovery.service.j2` + `.timer.j2` (matches existing
  `staleFileHandleHandler` pattern).
- Registered in `docker_timers` (`docker_setup/defaults/main.yml`) with schedule
  `*-*-* *:00/5:00` (every 5 min).
- Script added to `docker_script_templates` in:
  - `roles/container/docker_setup/defaults/main.yml`
  - `roles/container/docker_template_setup/defaults/main.yml`
  - `playbooks/setup/vars/docker.yml` (the vars file actually used by the `docker_hosts` play)
  - `inventory/group_vars/all/main.yml` (`scripts.templates` / `timers.jobs`)

### B3. Gotify alerting

- `nfsStaleRecovery.sh` POSTs to `https://gotify.local.hejsan.xyz/message` with
  `X-Gotify-Key` header and JSON body (title/message/priority).
- Token comes from `{{ vault_gotify_token | default('') }}` — safe default (skips
  notification with a warning if unset).
- **Action required:** add `vault_gotify_token` to
  `inventory/group_vars/all/vault.yml` (encrypted). The flux repo's
  `alertmanager-gotify-bridge` uses token `A7TvHUAUjtqng3X`; a dedicated app token is
  preferred for the node-level script.
- New defaults `nfs_alert_gotify_url` / `nfs_alert_gotify_priority` in
  `docker_setup/defaults/main.yml`.

---

## 4. Phase C — DEFERRED (out of current scope)

- **CSI NFS driver on Docker hosts** — not applicable (k8s-only). If the media service ever
  moves to k8s, adopt the flux L5 pattern directly.
- **Log-watcher sidecar (L1)** — jellyfin-specific; only relevant if the ansible jellyfin
  container needs the same log-based stale detection as the flux deployment.

## 5. Phase D — DEFERRED (out of current scope)

- **Storage-side remediation** on `storage.local.hejsan.xyz`:
  - Rebalance / free space on the ~98%-full mergerfs pool (2.4T free of 105T).
  - Consider per-consumer sub-exports instead of the single root-squashed `/` export to
    reduce cross-client stale-handle churn.
  - Review `fsid=0` root export exposure.
- **GPU-node single-disk resilience** — the GPU node's local disk is a single point of
  failure for its NFS cache; consider redundancy.

---

## 6. Rollout sequence

| Step | Action | Gate | Status |
|---|---|---|---|
| 1 | `ansible-playbook --syntax-check` on `base.yml` + `storage.yml`; `bash -n` on all scripts | clean | ✅ done |
| 2 | Add `vault_gotify_token` to `inventory/group_vars/all/vault.yml` | token present | ⏳ pending (user) |
| 3 | Commit & push; `git pull` on jumphost | jumphost at HEAD | ✅ done |
| 4 | Run `storage.yml` (NFS client) on `media_services` → applies hardened mount opts | mount shows new opts (`mount | grep /mnt/storage`) | ✅ done |
| 5 | Run `base.yml --tags docker` on `media_services` → deploys scripts + timers | `nfsStaleRecovery.timer` active; scripts present | ✅ done |
| 5b | Verify storage-dir override: `docker inspect` a media container's mounts, or check rendered compose, shows `/mnt/storage/files` (not `/opt/docker/storage/files`) | bind-mounts point at `/mnt/storage` | ✅ done |
| 5c | If `/opt/docker/storage` was an unmanaged symlink to `/mnt/storage`, remove it (now redundant) | symlink gone | ✅ done (was a real empty local dir, not a symlink — left in place) |
| 6 | Verify timer fires: `systemctl list-timers nfsStaleRecovery`; check journal for "No NFS issues found" | timer runs clean | ✅ done (timer fired 17:40:01) |
| 7 | Idempotency: re-run same commands | second run changed=0 | ⏳ pending |
| 8 | Drift probe: `systemctl stop nfsStaleRecovery.timer`, re-run playbook, confirm re-enabled | converged | ⏳ pending |

**First-run expectations:** the hardened mount options differ from the current
`defaults,_netdev`, so step 4 **will** report the mount task as `changed` — correct, not
drift. The new scripts/timers are additive; no existing behavior is removed.

---

## 7. Out of scope / follow-ups

- Phase C and Phase D (see §4, §5) — deferred.
- ~~`docker_storage_dir` vs `/mnt/storage` discrepancy~~ **RESOLVED 2026-08-29 (Option A):**
  `docker_storage_dir: /mnt/storage` is now overridden in
  `inventory/group_vars/media_services/docker.yml`, so the compose bind-mounts and the NFS
  recovery scripts (`start.sh`, `staleFileHandleHandler.sh`, `nfsStaleRecovery.sh`) all point
  at the real NFS mount. **Verified on the live host** that `/opt/docker/storage` is a real
  (empty) local dir on the root disk, **not** a symlink — left in place (harmless, unused).
- The `storage.mount` group var in `inventory/group_vars/media_services/storage.yml`
  (`defaults` + `_netdev`) is validated by `variable_validation` but not consumed by
  `nfs_client_setup`; consider reconciling it with the hardened options or removing it.
- `docker_nfs_enabled` is true but the AppArmor profile in `docker_setup/tasks/nfs.yml` /
  `nfs.yml` compose template is commented out — confirm whether the profile should be
  enabled (separate work item).

---

## 8. Deployment record (2026-08-29)

Deployed to `media.local.hejsan.xyz` (192.168.1.105). Commits (all pushed to GitLab origin
**and** GitHub mirror — the jumphost pulls from GitHub):

| Commit | Change |
|---|---|
| `6e42527` | feat(nfs): harden media service NFS mount + add recovery agent and alerts (Phase A + B + Option A) |
| `c36461c` | fix(nfs): correct docker_storage_dir precedence + user dict recursion |
| `1c3cca1` | fix(nfs): don't chgrp NFS mount in docker_setup dir creation |
| `b18a74a` | fix(nfs): set docker_registry_domain for media compose images |

### Verified on the live host
- NFS mount: `vers=4.1, timeo=30, retrans=3, actimeo=5, lookupcache=none, noatime, nodiratime, soft` (fstab + runtime).
- `nfsStaleRecovery.timer` active, fired 17:40:01, next run in 5 min.
- All three scripts (`start.sh`, `staleFileHandleHandler.sh`, `nfsStaleRecovery.sh`) have `STORAGE_DIR=/mnt/storage`.
- `transmission` container recreated via compose with `/mnt/storage/downloads` bind-mounts + correct registry image.

### Pre-existing bugs found & fixed during rollout (not part of the original Phase A/B scope)
1. **`docker_storage_dir` precedence bug** — play-level `vars/docker.yml` overrode the
   `media_services` group_var, so the storage-dir override never applied. Fixed by removing
   `docker_storage_dir` from `playbooks/setup/vars/docker.yml`.
2. **`user` dict recursion bug** — `user.group: "{{ user.name }}"` / `user.gid: "{{ user.uid }}"`
   self-referenced → Ansible `recursive loop detected in template string` blocked compose
   deployment. Fixed with plain `ubuntu`/`1000` in `inventory/group_vars/all/main.yml`.
3. **NFS mount chgrp failure** — `docker_setup` "Create docker directories" tried to
   chgrp/chmod `/mnt/storage` (root-squashed NFS mount) → `chgrp failed`. Split storage-dir
   creation into its own task that only ensures existence (no ownership/mode forcing).
4. **Empty `docker_registry_domain`** — compose templates reference the flat
   `docker_registry_domain` var, which defaulted to `""`, producing invalid image refs
   (`/linuxserver/transmission`) that blocked `docker compose up`. Mapped it to
   `docker.registry.domain` (`artifactory.local.hejsan.xyz/docker`) in
   `inventory/group_vars/media_services/docker.yml`.

### Remaining follow-ups
- **`vault_gotify_token`** not yet added to `inventory/group_vars/all/vault.yml` — alerts are
  silent until added (script logs a warning and skips the POST).
- **Second media host `192.168.1.213`** unreachable ("No route to host") — needs the same
  deployment once reachable; investigate connectivity.
- **Storage pool ~97% full** (3.2T free of 105T) — Phase D (storage-side remediation) deferred.
- Idempotency (step 7) and drift probe (step 8) not yet run.
