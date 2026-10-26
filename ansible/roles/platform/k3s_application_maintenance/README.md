# K3s application maintenance

This role prepares application capacity for a K3s maintenance window and
restores it afterward. It only operates on the explicit Flux Kustomizations
and application namespaces in its defaults. It excludes all control-plane,
storage, networking, and system namespaces.

Run from `ansible/` on the first K3s control-plane host:

```sh
ansible-playbook playbooks/maintenance/k3s_application_maintenance.yml \
  -e k3s_maintenance_action=prepare

# Complete the K3s work, then restore application capacity.
ansible-playbook playbooks/maintenance/k3s_application_maintenance.yml \
  -e k3s_maintenance_action=restore
```

`prepare` captures every affected Deployment, StatefulSet, CronJob, and Flux
Kustomization state before suspending Flux and CronJobs and scaling workloads
to zero. `restore` returns recorded replicas and suspend flags, requests Flux
reconciliation, waits for each Kustomization that was active before the
window, then removes the state record. A second prepare is refused while a
state record exists.

Each action atomically acquires a sibling `.lock` directory before inspecting
state. An existing state record blocks a new prepare without restoring or
removing that record. Preparation recovery only uses state saved by that
invocation. The lock is released when the action finishes; an interrupted
process can leave a lock behind. Investigate the owner before removing a stale
lock, and restore an incomplete window explicitly before another prepare.

After CronJobs are suspended, active Jobs across all namespaces must finish while their
dependencies remain available. After scaling workloads down, all non-DaemonSet
Pods must terminate (completed/failed Pods are excluded). The Job gate and each namespace Pod gate
retry 120 times at five-second intervals by default, configurable with
`k3s_application_maintenance_capacity_retries` and
`k3s_application_maintenance_capacity_delay`. A timeout fails preparation and
attempts recovery; it never deletes Pods or forces a drain.

Restoration attempts all workload, CronJob, and Flux commands even if a command
fails. Any failure is reported after Flux restoration has been attempted, and
the saved state is retained for an explicit retry. Only a fully successful
restore removes the recovery record. The CLI path defaults to
`k3s_application_maintenance_api=/usr/local/bin/k3s`.
