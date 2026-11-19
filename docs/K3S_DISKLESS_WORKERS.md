# Diskless K3s workers

Node 213 and the GPU worker are members of `k3s_workers_diskless`. Both may
mount remote LINSTOR volumes, but the Piraeus storage-pool policy prevents
local replicas on them. Keep `storage.josmase.io/replicas-disabled=true` on
both nodes; do not use `storage.josmase.io/linstor-disabled`, which also
prevents diskless remote-volume access. Node 213 accepts ordinary workloads without a
workload taint. The GPU worker carries a soft `PreferNoSchedule` taint so the
scheduler favors other workers for ordinary pods while still allowing them
when needed.

Before onboarding another diskless worker, verify the replica-exclusion
selector is applied in Flux, confirm DNS and SSH/sudo access, verify the
vaulted K3s token and live release, then run the worker onboarding playbook
with a single-host limit. Inspect node readiness, Piraeus satellite health,
labels and taints before relying on the node.

Use `playbooks/setup/kubernetes-node-scheduling.yml` to apply the replica
exclusion label to node 213 and allow its diskless satellite to join. Use
`playbooks/setup-gpu-kubernetes-node.yml` after GPU host setup to apply the GPU
label and soft taint.
