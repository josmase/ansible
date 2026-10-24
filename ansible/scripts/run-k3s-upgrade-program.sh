#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing an upgrade from a dirty Ansible checkout." >&2
  exit 1
fi
kube_vip=v1.2.4
targets=(v1.32.13+k3s1 v1.33.13+k3s2 v1.34.12+k3s1 v1.35.9+k3s1 v1.36.5+k3s1 v1.37.1+k3s1)
prepared=false
restore() {
  if [[ "$prepared" == true ]]; then
    ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_application_maintenance.yml -e k3s_maintenance_action=restore
    prepared=false
  fi
}
on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$prepared" == true ]] && ! restore; then
    echo "Application restoration failed; inspect the saved maintenance state before continuing." >&2
    if [[ "$status" -eq 0 ]]; then
      status=1
    fi
  fi
  exit "$status"
}
trap on_exit EXIT
for target in "${targets[@]}"; do
  echo "Starting monitored maintenance window for $target"
  ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_application_maintenance.yml -e k3s_maintenance_action=prepare
  prepared=true
  ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_rolling_upgrade.yml \
    -e k3s_upgrade_target_version="$target" \
    -e kube_vip_upgrade_target_version="$kube_vip"
  restore
  ssh ubuntu@192.168.1.201 'sudo /usr/local/bin/k3s kubectl get nodes && sudo /usr/local/bin/k3s kubectl -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io'
done
trap - EXIT
echo "K3s minor upgrade program completed successfully."
