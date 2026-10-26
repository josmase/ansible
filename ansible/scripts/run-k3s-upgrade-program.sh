#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  echo "Usage: $0 <one-target-version>" >&2
  echo "Targets: v1.32.13+k3s1 v1.33.13+k3s2 v1.34.12+k3s1 v1.35.9+k3s1 v1.36.5+k3s1 v1.37.1+k3s1" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

target="$1"
case "$target" in
  v1.32.13+k3s1) previous=v1.31.14+k3s1 ;;
  v1.33.13+k3s2) previous=v1.32.13+k3s1 ;;
  v1.34.12+k3s1) previous=v1.33.13+k3s2 ;;
  v1.35.9+k3s1) previous=v1.34.12+k3s1 ;;
  v1.36.5+k3s1) previous=v1.35.9+k3s1 ;;
  v1.37.1+k3s1) previous=v1.36.5+k3s1 ;;
  *)
    echo "Refusing unsupported K3s target: $target" >&2
    usage
    exit 2
    ;;
esac

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing an upgrade from a dirty Ansible checkout." >&2
  exit 1
fi

# Hold the lock across preparation, upgrade, restoration, and verification.
exec 9>"$(git rev-parse --git-common-dir)/k3s-upgrade-program.lock"
if ! flock -n 9; then
  echo "Another K3s upgrade program is running." >&2
  exit 1
fi

# kubectl runs from this workstation against its configured API context. The
# default context is direct; override with KUBECTL_CONTEXT if needed.
kubectl_context="${KUBECTL_CONTEXT:-default}"
kube_vip=v1.3.0

echo "Checking node readiness, release stage, and Flux health through $kubectl_context"
nodes="$(kubectl --context "$kubectl_context" get nodes -o json)"
jq -e --arg previous "$previous" --arg target "$target" '
  (.items | length > 0) and
  ([.items[] | select(
    (.status.nodeInfo.kubeletVersion != $previous and .status.nodeInfo.kubeletVersion != $target) or
    ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)
  )] | length == 0)
' <<<"$nodes" >/dev/null || {
  echo "Refusing: every node must be Ready and running either $previous or $target." >&2
  jq -r '.items[] | [.metadata.name, .status.nodeInfo.kubeletVersion, ([.status.conditions[]? | select(.type == "Ready") | .status] | first // "Unknown")] | @tsv' <<<"$nodes" >&2
  exit 1
}

flux="$(kubectl --context "$kubectl_context" get kustomizations.kustomize.toolkit.fluxcd.io -A -o json)"
jq -e '(.items | length > 0) and ([.items[] | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)] | length == 0)' <<<"$flux" >/dev/null || {
  echo "Refusing: one or more Flux Kustomizations are not Ready." >&2
  jq -r '.items[] | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0) | [.metadata.namespace, .metadata.name, ([.status.conditions[]? | select(.type == "Ready") | .message] | first // "Ready condition missing")] | @tsv' <<<"$flux" >&2
  exit 1
}

prepared=false
restore() {
  if [[ "$prepared" == true ]]; then
    # Preserve an unsuccessful restore result so the EXIT handler can report it.
    ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_application_maintenance.yml -e k3s_maintenance_action=restore || return $?
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

echo "Running read-only Ansible transition preflight for $target"
ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_upgrade_preflight.yml \
  -e k3s_upgrade_target_version="$target" \
  -e kube_vip_upgrade_target_version="$kube_vip"

echo "Starting one monitored maintenance window for $target (from $previous)"
ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_application_maintenance.yml -e k3s_maintenance_action=prepare
prepared=true
ansible-playbook -i inventory/production.ini playbooks/maintenance/k3s_rolling_upgrade.yml \
  -e k3s_upgrade_target_version="$target" \
  -e kube_vip_upgrade_target_version="$kube_vip"
restore

final_nodes="$(kubectl --context "$kubectl_context" get nodes -o json)"
echo "Final node versions:"
kubectl --context "$kubectl_context" get nodes -o wide
jq -e --arg target "$target" '(.items | length > 0) and ([.items[] | select(.status.nodeInfo.kubeletVersion != $target or ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0))] | length == 0)' <<<"$final_nodes" >/dev/null

final_flux="$(kubectl --context "$kubectl_context" get kustomizations.kustomize.toolkit.fluxcd.io -A -o json)"
echo "Final Flux status:"
kubectl --context "$kubectl_context" get kustomizations.kustomize.toolkit.fluxcd.io -A
jq -e '(.items | length > 0) and ([.items[] | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)] | length == 0)' <<<"$final_flux" >/dev/null

trap - EXIT
echo "K3s minor upgrade $target completed successfully."
