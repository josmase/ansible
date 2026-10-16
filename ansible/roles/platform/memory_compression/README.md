# Memory Compression Role

Installs the running kernel's extra modules package and configures a host-only
compressed zram swap device through `systemd-zram-generator`.

The role intentionally does not change K3s or kubelet swap policy. Kubernetes
workloads therefore keep the kubelet default of `NoSwap`; zram is only a
short-term buffer for the host and its system services.

## Scope

Use this role through
`playbooks/setup/kubernetes-worker-memory-compression.yml`. That play targets
the `k3s_workers` inventory group (the regular workers and GPU worker), never
the control-plane nodes.

## Variables

- `memory_compression_package`: generator package; default
  `systemd-zram-generator`.
- `memory_compression_device`: zram device name; default `zram0`.
- `memory_compression_zram_size`: generator size expression; default
  `min(ram / 4, 8192)` (at most 8 GiB of logical zram capacity).
- `memory_compression_algorithm`: compression algorithm; default `lz4`.
- `memory_compression_swap_priority`: swap priority; default `100`.

## Rollout

Start with Ansible check mode, then run normally. The play executes one worker
at a time and verifies that `/dev/zram0` is active swap on each host.

```sh
ansible-playbook playbooks/setup/kubernetes-worker-memory-compression.yml --check
ansible-playbook playbooks/setup/kubernetes-worker-memory-compression.yml
```
