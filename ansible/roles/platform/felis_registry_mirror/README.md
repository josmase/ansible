# Felis registry mirror role

Configures the K3s containerd mirror needed to pull Felis game images. K3s pulls an image before its Pod starts, so the pull cannot depend on the cluster-only DNS name `registry.felis.svc`.

The role adds or updates only the Felis mirror entry in `/etc/rancher/k3s/registries.yaml`, preserving other registry settings. K3s must restart after a changed configuration. The dedicated playbook runs serially across the `k3s_cluster` inventory group.

## Defaults

| Variable | Default | Purpose |
| --- | --- | --- |
| `felis_registry_mirror_name` | `registry.felis.svc:5000` | Registry hostname used in Felis image references |
| `felis_registry_mirror_endpoint` | `http://192.168.1.182:5000` | MetalLB registry Service endpoint shared with Felis API and Velocity |
| `felis_registry_mirror_config_path` | `/etc/rancher/k3s/registries.yaml` | K3s registry configuration file |
| `felis_registry_mirror_service_name` | `k3s_service_name`, else `k3s-node` | systemd unit restarted when the config changes |

Felis registry pulls are anonymous; write requests are authenticated by Felis. Do not put Felis registry write credentials in node-level K3s configuration.

## Apply

```bash
cd ansible
ansible-playbook playbooks/setup/felis-registry-nodes.yml --check --diff
ansible-playbook playbooks/setup/felis-registry-nodes.yml --limit kubernetes-201.local.hejsan.xyz
ansible-playbook playbooks/setup/felis-registry-nodes.yml
```

Apply this to all K3s nodes before enabling the Felis game stage. The mirror endpoint requires the Felis registry LoadBalancer Service at `192.168.1.182:5000` to be Ready.
