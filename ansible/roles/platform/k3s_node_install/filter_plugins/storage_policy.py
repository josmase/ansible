"""Conservative safety checks for K3s cluster and storage state."""

import re


def term_excludes_node(term, label, node_name):
    for expression in term.get('matchExpressions', []):
        if expression.get('key') == label and expression.get('operator') == 'DoesNotExist':
            return True
        if expression.get('key') == 'kubernetes.io/hostname':
            values = expression.get('values', [])
            if expression.get('operator') == 'In' and node_name not in values:
                return True
            if expression.get('operator') == 'NotIn' and node_name in values:
                return True
    for field in term.get('matchFields', []):
        if field.get('key') == 'metadata.name':
            values = field.get('values', [])
            if field.get('operator') == 'In' and node_name not in values:
                return True
            if field.get('operator') == 'NotIn' and node_name in values:
                return True
    return False


def all_terms_exclude(affinity, label, node_name):
    terms = (affinity or {}).get('nodeSelectorTerms', [])
    return bool(terms) and all(term_excludes_node(term, label, node_name) for term in terms)


def piraeus_exclusion_proven(clusters, daemonsets, label, node_name):
    items = clusters.get('items', [])
    sets = daemonsets.get('items', [])
    if not items or not sets:
        return False
    for cluster in items:
        conditions = cluster.get('status', {}).get('conditions', [])
        applied = any(c.get('type') == 'Applied' and c.get('status') == 'True'
                      and c.get('observedGeneration') == cluster.get('metadata', {}).get('generation')
                      for c in conditions)
        if not applied or not all_terms_exclude(cluster.get('spec', {}).get('nodeAffinity'), label, node_name):
            return False
    for ds in sets:
        if ds.get('status', {}).get('observedGeneration') != ds.get('metadata', {}).get('generation'):
            return False
        spec = ds.get('spec', {}).get('template', {}).get('spec', {})
        affinity = spec.get('affinity', {}).get('nodeAffinity', {}).get('requiredDuringSchedulingIgnoredDuringExecution')
        if not all_terms_exclude(affinity, label, node_name):
            return False
    return True


def piraeus_replica_exclusion_proven(configurations, label):
    """Require every local-pool affinity alternative to exclude marked nodes."""
    if not isinstance(configurations, dict) or not isinstance(configurations.get('items'), list):
        return False
    storage_configs = [
        item for item in configurations['items']
        if isinstance(item, dict) and item.get('spec', {}).get('storagePools')
    ]
    if not storage_configs:
        return False
    for item in storage_configs:
        terms = item.get('spec', {}).get('nodeAffinity', {}).get('nodeSelectorTerms', [])
        if not isinstance(terms, list) or not terms:
            return False
        for term in terms:
            if not any(
                expression.get('key') == label and expression.get('operator') == 'DoesNotExist'
                for expression in term.get('matchExpressions', [])
            ):
                return False
    return True


def control_plane_ready(nodes, expected_names):
    items = nodes.get('items', [])
    if not expected_names or {n.get('metadata', {}).get('name') for n in items} != set(expected_names):
        return False
    for node in items:
        conditions = node.get('status', {}).get('conditions', [])
        if not any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in conditions):
            return False
    return True


def runtime_config_safe(config):
    if not isinstance(config, dict) or set(config) - {'kubelet-arg', 'enable-pprof'}:
        return False
    args = config.get('kubelet-arg', [])
    if not isinstance(args, list):
        return False
    pattern = re.compile(r'^(eviction-hard|image-gc-high-threshold|image-gc-low-threshold)=[a-zA-Z0-9%.,<>=-]+$')
    return all(isinstance(arg, str) and pattern.fullmatch(arg) for arg in args) and isinstance(config.get('enable-pprof', False), bool)


def managed_installation_marker_matches(marker, identity):
    if not isinstance(marker, dict) or not isinstance(identity, dict):
        return False
    version = marker.get('version')
    if not isinstance(version, str) or not re.fullmatch(r'v[0-9]+[.][0-9]+[.][0-9]+[+]k3s[0-9]+', version):
        return False
    return {key: value for key, value in marker.items() if key != 'version'} == identity


def managed_gomemlimit_safe(content):
    return bool(re.fullmatch(
        r'# Managed by Ansible \(platform/k3s_node_config\)\.\s*\n\[Service\]\s*\nEnvironment="GOMEMLIMIT=[0-9]+(?:B|KiB|MiB|GiB|TiB)?"\s*',
        content,
    ))


class FilterModule:
    def filters(self):
        return {'k3s_piraeus_exclusion_proven': piraeus_exclusion_proven, 'k3s_piraeus_replica_exclusion_proven': piraeus_replica_exclusion_proven, 'k3s_control_plane_ready': control_plane_ready, 'k3s_runtime_config_safe': runtime_config_safe, 'k3s_managed_gomemlimit_safe': managed_gomemlimit_safe, 'k3s_managed_marker_matches': managed_installation_marker_matches}
