# K3s master memory investigation and reduction

This procedure profiles the combined K3s server process before setting a Go
memory budget or reducing Proxmox VM memory. The master VM sizes are declared
per node in `opentofu/virtual-machines/variables.tf` (MiB).

## Preconditions

- All three masters report `Ready`, `/readyz` succeeds on each, and etcd has a
  stable leader with healthy peers.
- The LINSTOR controller and required satellites are available. Record current
  snapshot retry activity and host memory before beginning.
- Prometheus or another independent scraper can retain the measurements. The
  K3s process restarts when profiling is enabled, so the old process heap cannot
  be profiled after that restart. Capture during the next period when memory
  grows, especially during a controlled peer restart/catch-up.
- Save a verified etcd snapshot before any K3s upgrade. The existing
  `playbooks/maintenance/k3s_rolling_upgrade.yml` requires all nodes Ready and
  upgrades nodes serially. The last recorded live version (1.31.14) differed
  from the inventory target (1.32.13); confirm current versions before running.

## Temporary profiling

The `k3s_node_config` role keeps `k3s_enable_pprof` false by default. For one
master only, run from the Ansible repository root:

```sh
ansible-playbook -i inventory/production.ini playbooks/setup/kubernetes-node-hygiene.yml \
  --limit kubernetes-202.local.hejsan.xyz \
  -e k3s_enable_pprof=true -e k3s_restart_enabled=true
```

K3s serves pprof on the supervisor HTTPS port (6443). From the master itself,
create a private directory and retrieve profiles using its admin client
certificate and key:

```sh
sudo install -d -m 0700 /root/k3s-profiles
sudo curl --fail --silent --show-error \
  --cert /var/lib/rancher/k3s/server/tls/client-admin.crt \
  --key /var/lib/rancher/k3s/server/tls/client-admin.key \
  --cacert /var/lib/rancher/k3s/server/tls/server-ca.crt \
  https://192.168.1.202:6443/debug/pprof/heap \
  -o /root/k3s-profiles/heap.pb.gz
sudo curl --fail --silent --show-error \
  --cert /var/lib/rancher/k3s/server/tls/client-admin.crt \
  --key /var/lib/rancher/k3s/server/tls/client-admin.key \
  --cacert /var/lib/rancher/k3s/server/tls/server-ca.crt \
  'https://192.168.1.202:6443/debug/pprof/goroutine?debug=2' \
  -o /root/k3s-profiles/goroutines.txt
```

For another master, replace `192.168.1.202` with that node's address covered by
its server certificate. Do not disable TLS verification or expose port 6443 to
untrusted networks. Keep profile files private because they may contain
application data. Record the profile time together with `HeapAlloc`,
`HeapInuse`, RSS, K3s cgroup memory, GC cycles/CPU, API PATCH counters, and etcd
health. Compare a high-memory master and a low-memory master under similar
cluster load.

Disable profiling immediately after capture, again limiting the play to that
master and allowing the handler to restart it:

```sh
ansible-playbook -i inventory/production.ini playbooks/setup/kubernetes-node-hygiene.yml \
  --limit kubernetes-202.local.hejsan.xyz \
  -e k3s_enable_pprof=false -e k3s_restart_enabled=true
```

The K3s server configuration template only writes `enable-pprof: true` on a
master when explicitly enabled. A profile collected after restart describes
the new process; wait for the same memory-growth pattern to return before
capturing it. If it does not return, record that as evidence and do not infer a
leak from the old RSS alone.

## Go soft memory budget

Leave `k3s_gomemlimit` empty until profiles show the live heap and identify
which component can release memory. Then set a measured value for one master
in host/group variables, enable `k3s_restart_enabled` only for the maintenance
run, and run the same playbook with `--limit` for that master. This installs a
systemd drop-in with `GOMEMLIMIT`. The variable accepts Go memory units such as
`6GiB`; it is empty by default and the role removes its managed drop-in when
unset. Roll back by clearing the value and restarting the same master.

Treat `GOMEMLIMIT` as a soft runtime target, not a process or VM cap. Watch GC
CPU, API latency, etcd response/leader health, and host available memory. Undo
the setting if collection consumes sustained CPU, readiness degrades, or
latency rises. Do not add `MemoryMax` as a substitute; K3s, embedded etcd, the
API server, and node services share the same systemd service.

## Staged VM memory reductions

Do not change all three master sizes together. After profiling and a successful
Go-budget trial, reduce only one entry in `opentofu/virtual-machines/variables.tf`,
review the full `tofu plan`, apply, then verify all masters remain Ready, etcd
quorum is healthy, and LINSTOR, workers, and workloads recover before changing
the next entry. Keep at least 30% of the master's assigned RAM available at
the measured peak during normal load and one peer restart/catch-up test. If a
candidate size fails that margin or causes pressure, restore the prior size and
address the remaining memory source first.

The current `19456` MiB allocation remains unchanged until these measurements
support a smaller size. The published K3s baseline is useful context, not a
sizing target for this cluster's CRDs, LINSTOR state, and recovery workload.
