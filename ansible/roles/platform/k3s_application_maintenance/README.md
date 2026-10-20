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
