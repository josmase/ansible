# Kubernetes worker 214 onboarding

The new Ubuntu host receives the normal base setup, then joins as a K3s agent.
It is tainted so that only explicitly opted-in low-risk workloads can run
there. Piraeus/LINSTOR components are excluded by the node label configured in
the Ansible host variables.

Run these commands from `ansible/` on the Ansible jumphost after confirming
that `ubuntu@192.168.1.214` is reachable over SSH and has working sudo access.

1. Apply the DNS record and Flux changes before the node joins. Wait for Flux
   to report the Piraeus configuration ready; this prevents storage components
   from briefly scheduling on the new node.

2. Apply the standard server base setup only. The `general` and `shell` tags
   avoid the broader Kubernetes storage role, which can install kernel modules
   and reboot the host.

   ```sh
   ansible-playbook playbooks/setup/base.yml \
     --limit kubernetes-214.local.hejsan.xyz \
     --tags general,shell \
     --skip-tags docker
   ```

   Docker-specific setup is skipped because K3s uses containerd and this
   worker does not run a Docker daemon. Its network interface is `enp2s0`,
   which is also configured as the host-specific Flannel interface.

3. Join the worker using the dedicated agent-only playbook. Its host override
   pins K3s to the live control-plane version (`v1.31.14+k3s1`); the cluster-wide
   upgrade target remains `v1.32.13`. The playbook uses the existing vaulted
   token without running the retired cluster installer or its server-side
   add-on configuration.

   ```sh
   ansible-playbook playbooks/setup/kubernetes-worker-onboarding.yml
   ```

4. Apply the normal Kubernetes node runtime hygiene after the agent has joined.

   ```sh
   ansible-playbook playbooks/setup/kubernetes-node-hygiene.yml \
     --limit kubernetes-214.local.hejsan.xyz
   ```

5. Confirm the node is Ready, retains its `workload=low-risk-only:NoSchedule` taint and
   `storage.josmase.io/linstor-disabled=true` label, and has no Piraeus/LINSTOR
   pods or replicas. Do not opt in workloads until this check passes.

Workloads that qualify are stateless services, disposable caches, and retryable
batch jobs. Each must explicitly tolerate the low-risk taint and select the
`workload.josmase.io/low-risk-only=true` label. No workloads are opted in by
this onboarding.
