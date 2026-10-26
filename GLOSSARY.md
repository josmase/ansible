# Ansible Infrastructure

This context provisions the hosts managed by this Ansible repository and
defines the vocabulary for their infrastructure capabilities.

## GPU unlock

**Eligible GPU**:
An NVIDIA GPU whose PCI device ID is included in gpu-unlock's upstream
supported-device allowlist.
_Avoid_: compatible GPU, supported card

**GPU unlock target set**:
The collection of eligible GPUs selected for gpu-unlock on a host. The `all`
target set selects every eligible GPU.
_Avoid_: GPU selection, card list

**GPU unlock opt-in**:
The explicit inventory setting that permits the role to install gpu-unlock and
change early-boot configuration on an eligible host.
_Avoid_: automatic enablement

**GPU unlock revision**:
The full upstream git commit selected for a gpu-unlock deployment and kept
current through Renovate.
_Avoid_: latest version, floating branch

**Ineligible host**:
A managed host that has no eligible GPU. Enabling the GPU unlock role on an
ineligible host is a successful no-op.
_Avoid_: unsupported host, failed detection

**GPU unlock role**:
A host-level early-boot capability for eligible GPUs. It is independent of
Kubernetes, container-runtime, and workload configuration.
_Avoid_: Kubernetes GPU setup, GPU workload role

**GPU unlock hosts**:
The inventory group of hosts intentionally selected to receive the GPU unlock
role. It is capability-based rather than tied to a workload or orchestrator.
_Avoid_: Tdarr GPU hosts, Kubernetes GPU nodes
