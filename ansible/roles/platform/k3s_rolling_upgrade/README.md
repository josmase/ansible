# K3s rolling upgrade

Upgrades K3s nodes serially while preserving the systemd units and K3s
configuration created by the vendored installer. The role replaces only the
verified `/usr/local/bin/k3s` binary, then upgrades kube-vip through its
existing K3s static manifest after every node is healthy.

The accompanying maintenance playbook takes a fresh etcd snapshot first, then
runs this role with `serial: 1`. Each node is cordoned, drained, upgraded,
restarted, waited for, version-checked, and uncordoned. A failed node stays
cordoned for investigation.

Run from `ansible/` after reviewing the target version:

```sh
ansible-playbook playbooks/maintenance/k3s_rolling_upgrade.yml \
  -e k3s_upgrade_target_version=v1.31.6+k3s1 \
  -e kube_vip_upgrade_target_version=v0.8.7
```

Before running, commit `kube_vip_tag_version` with the same kube-vip release.
The playbook refuses an unpinned target. Upgrade one Kubernetes minor release
at a time.

Use `--check` only to validate inventory and playbook wiring: the snapshot,
drain, download, and service restart steps intentionally require a real run.
Set `k3s_upgrade_drain_force=true` only if unmanaged pods have been reviewed.

The multi-version program is `ansible/scripts/run-k3s-upgrade-program.sh`.
Its kube-vip target and the committed inventory both pin **v1.3.0**. A local
`flock` prevents overlapping program runs. Before each maintenance window,
`playbooks/maintenance/k3s_upgrade_preflight.yml` reads every inventory node's
installed release and rejects downgrades (including patch and K3s build
numbers), major-version changes, and skipped minors. The rolling role repeats
that validation immediately before touching each node.

The program deliberately refuses to restart from v1.32 if any node has already
advanced beyond that target. Following a failed later stage, restore the saved
maintenance state if necessary, inspect all installed versions and cluster
health, and review the remaining target sequence before continuing. Do not
remove the version gate to rerun earlier stages.

Offline regression checks require Python, PyYAML, `ansible-playbook`, Git, and
`flock`; they substitute fake K3s/SSH commands and never contact a cluster:

```sh
# From the repository root:
python3 -m unittest discover -s ansible/tests -p 'test_k3s_upgrade_safety.py' -v
```
