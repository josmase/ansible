# K3s node runtime configuration

Manages kubelet eviction and image cleanup settings, inotify sysctls, fsck MOTD handling, and optional K3s server Go memory limits. It does not install K3s or change a node's cluster join settings.

Use `playbooks/setup/kubernetes-node-hygiene.yml` from `ansible/`, with an explicit `--limit` and appropriate tags. The play is serial. `k3s_restart_enabled` defaults to `false`; review service restarts and control-plane quorum before enabling it. Defaults and the inventory's `k3s_service_name` select the values and service.

This role owns `/etc/rancher/k3s/config.yaml`. The installation role owns `config.yaml.d/20-ansible-node.yaml`; these files have separate responsibilities. The installation role permits this role's supported runtime settings and the optional root-owned `20-gomemlimit.conf` systemd drop-in, while rejecting unknown configuration and drop-ins.

See [K3s roles and workflows](../../../../docs/K3S_ROLES.md) for entry points and ordering.
