# MetalLB Flux handoff

Performs the one-time transfer from the K3s static MetalLB add-on to the
Flux-managed Helm release. The Flux commit must already be reconciled before
this playbook runs. Its HelmRelease can show an expected install conflict until
the legacy static manifest is removed.

Run only in an approved maintenance window:

```sh
ansible-playbook playbooks/maintenance/metallb_flux_handoff.yml \
  -e metallb_flux_handoff_allow_static_removal=true
```

The role backs up the legacy static manifest, removes it, waits for K3s to
delete the add-on, requests Flux reconciliation, and verifies the controller,
speakers, and every existing LoadBalancer allocation. If Flux cannot install
MetalLB, stop and revert the Flux release change before restoring the backed-up
manifest; restoring it while Flux remains enabled would create dual ownership.
