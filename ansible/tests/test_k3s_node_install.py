"""Offline checks for lifecycle configuration and safety boundaries."""
from pathlib import Path
import unittest

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / 'roles/platform/k3s_node_install'


class NodeInstallTests(unittest.TestCase):
    def render(self, mode):
        defaults = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())
        defaults.update(k3s_node_install_mode=mode,
                        k3s_node_install_name='node-test',
                        k3s_node_install_ip='192.0.2.10',
                        k3s_node_install_interface='eth0',
                        k3s_node_install_token='test-token',
                        k3s_node_install_server_url='https://192.0.2.1:6443',
                        k3s_node_install_tls_sans=['192.0.2.1'],
                        k3s_node_install_disabled_components=['traefik'],
                        k3s_node_install_labels=['workload=test'],
                        k3s_node_install_taints=['workload=test:NoSchedule'])
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(ROLE / 'templates'), undefined=jinja2.StrictUndefined)
        env.filters['to_json'] = __import__('json').dumps
        return yaml.safe_load(env.get_template('config.yml.j2').render(**defaults))

    def test_initial_server_bootstraps_without_join_endpoint(self):
        data = self.render('server_init')
        self.assertTrue(data['cluster-init'])
        self.assertNotIn('server', data)
        self.assertEqual(data['tls-san'], ['192.0.2.1'])
        self.assertEqual(data['disable'], ['traefik'])

    def test_joining_server_does_not_initialize(self):
        data = self.render('server_join')
        self.assertNotIn('cluster-init', data)
        self.assertEqual(data['server'], 'https://192.0.2.1:6443')

    def test_agent_does_not_receive_server_options(self):
        data = self.render('agent_join')
        self.assertNotIn('cluster-init', data)
        self.assertNotIn('tls-san', data)
        self.assertNotIn('disable', data)
        self.assertEqual(data['node-label'], ['workload=test'])
        self.assertEqual(data['node-taint'], ['workload=test:NoSchedule'])

    def test_server_settings_are_only_rendered_for_servers(self):
        defaults = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())
        self.assertEqual(defaults['k3s_node_install_server_settings'], {})
        self.assertFalse(defaults['k3s_node_install_allow_cluster_init'])
        tasks = yaml.safe_load((ROLE / 'tasks/main.yml').read_text())
        validate = next(t for t in tasks if t['name'] == 'Validate node installation inputs')
        assertions = ' '.join(validate['ansible.builtin.assert']['that'])
        self.assertIn('cluster-reset', assertions)
        self.assertIn('ansible_play_hosts_all', assertions)

    def test_etcd_postflight_uses_loopback_without_enabling_external_metrics(self):
        postflight = yaml.safe_load((ROLE / 'tasks/server_postflight.yml').read_text())
        metrics = next(task for task in postflight if task['name'] == 'Read etcd metrics after the server joins')
        self.assertEqual(metrics['ansible.builtin.uri']['url'], 'http://127.0.0.1:2381/metrics')
        server = self.render('server_join')
        self.assertNotIn('etcd-expose-metrics', server)

    def test_wrapped_sudo_prompt_detection(self):
        import importlib.util
        try:
            import ansible  # noqa: F401
        except ImportError:
            self.skipTest('Ansible is required to load the become plugin')
        path = ROOT / 'plugins/become/sudo_wrapped.py'
        spec = importlib.util.spec_from_file_location('sudo_wrapped', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        plugin = module.BecomeModule()
        plugin.prompt = '[sudo via ansible, key=abc] password:'
        self.assertTrue(plugin.check_password_prompt(b'[sudo via ansible, key=abc] password:'))
        self.assertTrue(plugin.check_password_prompt(b'[sudo: [sudo via ansible, key=abc] password:] Password: '))
        self.assertFalse(plugin.check_password_prompt(b'[sudo via ansible, key=other] password:'))

    def test_verified_node_has_maintenance_group_membership(self):
        import configparser
        inventory = configparser.ConfigParser(allow_no_value=True, strict=False, interpolation=None, delimiters=('='))
        inventory.read(ROOT / 'inventory/production.ini')
        self.assertIn('k3s_workers_diskless', inventory['node:children'])
        self.assertIn('k3s_workers_diskless', inventory['k3s_workers:children'])
        play = yaml.safe_load((ROOT / 'playbooks/setup/kubernetes-worker-onboarding.yml').read_text())[0]
        self.assertEqual('k3s_workers', play['hosts'])
        group = yaml.safe_load((ROOT / 'inventory/group_vars/k3s_workers_diskless/vars.yml').read_text())
        self.assertEqual(group['k3s_node_install_mode'], 'agent_join')
        self.assertEqual(group['k3s_node_install_storage_replica_exclusion_label'], 'storage.josmase.io/replicas-disabled')
        self.assertEqual(group['k3s_node_install_labels'], ['storage.josmase.io/replicas-disabled=true'])
        self.assertNotIn('k3s_node_install_taints', group)
        gpu = yaml.safe_load((ROOT / 'inventory/host_vars/gpu.local.hejsan.xyz.yml').read_text())
        self.assertIn('gpu=true', gpu['k3s_node_install_labels'])
        self.assertIn('storage.josmase.io/replicas-disabled=true', gpu['k3s_node_install_labels'])
        self.assertEqual(gpu['k3s_node_install_taints'], ['gpu.josmase.io/workload=gpu:PreferNoSchedule'])
        scheduling = yaml.safe_load((ROOT / 'playbooks/setup/kubernetes-node-scheduling.yml').read_text())[0]
        self.assertIn('k3s_masters', scheduling['hosts'])
        cluster = yaml.safe_load((ROOT / 'inventory/group_vars/k3s_cluster/vars.yml').read_text())
        self.assertIn('k3s_token', cluster['k3s_node_install_token'])
        self.assertNotIn('k3s_node_install_version', group)

    def test_guards_precede_mutations_and_secret_is_private(self):
        tasks = yaml.safe_load((ROLE / 'tasks/main.yml').read_text())
        names = [task['name'] for task in tasks]
        self.assertLess(names.index('Reject unowned K3s installations or state'), names.index('Install prerequisites'))
        self.assertLess(names.index('Refuse implicit configuration changes to an existing node'), names.index('Install prerequisites'))
        config = next(t for t in tasks if t['name'] == 'Write initial lifecycle configuration')
        self.assertEqual(config['ansible.builtin.template']['mode'], '0600')
        self.assertTrue(config['no_log'])
        self.assertFalse(config['diff'])
        self.assertIn('config.yaml.d/', config['ansible.builtin.template']['dest'])

class SafetyPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import importlib.util
        spec = importlib.util.spec_from_file_location('storage_policy', ROLE / 'filter_plugins/storage_policy.py')
        cls.policy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.policy)

    def fixtures(self):
        excluded = {'nodeSelectorTerms': [{'matchExpressions': [{'key': 'storage.josmase.io/linstor-disabled', 'operator': 'DoesNotExist'}]}]}
        cluster = {'metadata': {'generation': 2}, 'spec': {'nodeAffinity': excluded}, 'status': {'conditions': [{'type': 'Applied', 'status': 'True', 'observedGeneration': 2}]}}
        daemonset = {'metadata': {'generation': 1}, 'status': {'observedGeneration': 1}, 'spec': {'template': {'spec': {'affinity': {'nodeAffinity': {'requiredDuringSchedulingIgnoredDuringExecution': excluded}}}}}}
        return {'items': [cluster]}, {'items': [daemonset]}

    def proven(self, clusters, daemonsets, name='kubernetes-node-213'):
        return self.policy.piraeus_exclusion_proven(clusters, daemonsets, 'storage.josmase.io/linstor-disabled', name)

    def test_storage_exclusion_requires_every_or_term(self):
        clusters, daemonsets = self.fixtures()
        self.assertTrue(self.proven(clusters, daemonsets))
        affinity = daemonsets['items'][0]['spec']['template']['spec']['affinity']['nodeAffinity']['requiredDuringSchedulingIgnoredDuringExecution']
        affinity['nodeSelectorTerms'].append({'matchExpressions': [{'key': 'kubernetes.io/hostname', 'operator': 'In', 'values': ['kubernetes-node-213']}]})
        self.assertFalse(self.proven(clusters, daemonsets))
        affinity['nodeSelectorTerms'][-1]['matchExpressions'][0]['values'] = ['another-node']
        self.assertTrue(self.proven(clusters, daemonsets))

    def test_diskless_replica_policy_excludes_every_pool_selector_term(self):
        configurations = {'items': [
            {'spec': {'storagePools': [{'name': 'pool1'}], 'nodeAffinity': {'nodeSelectorTerms': [
                {'matchExpressions': [{'key': 'storage.josmase.io/replicas-disabled', 'operator': 'DoesNotExist'}]}
            ]}}},
            {'spec': {'storagePools': [{'name': 'final'}], 'nodeAffinity': {'nodeSelectorTerms': [
                {'matchExpressions': [
                    {'key': 'storage.josmase.io/linstor-final', 'operator': 'In', 'values': ['true']},
                    {'key': 'storage.josmase.io/replicas-disabled', 'operator': 'DoesNotExist'},
                ]}
            ]}}},
        ]}
        self.assertTrue(self.policy.piraeus_replica_exclusion_proven(configurations, 'storage.josmase.io/replicas-disabled'))
        configurations['items'][0]['spec']['nodeAffinity']['nodeSelectorTerms'].append({'matchExpressions': []})
        self.assertFalse(self.policy.piraeus_replica_exclusion_proven(configurations, 'storage.josmase.io/replicas-disabled'))

    def test_storage_fails_closed_on_missing_stale_or_unexcluded_policy(self):
        clusters, daemonsets = self.fixtures()
        self.assertFalse(self.proven({'items': []}, daemonsets))
        self.assertFalse(self.proven(clusters, {'items': []}))
        clusters['items'][0]['status']['conditions'][0]['observedGeneration'] = 1
        self.assertFalse(self.proven(clusters, daemonsets))
        clusters, daemonsets = self.fixtures()
        daemonsets['items'][0]['status']['observedGeneration'] = 0
        self.assertFalse(self.proven(clusters, daemonsets))
        clusters, daemonsets = self.fixtures()
        daemonsets['items'][0]['spec']['template']['spec']['affinity'] = {}
        self.assertFalse(self.proven(clusters, daemonsets))

    def test_storage_exclusion_uses_node_field_for_satellites(self):
        self.assertTrue(self.policy.term_excludes_node({'matchFields': [{'key': 'metadata.name', 'operator': 'In', 'values': ['other']}]}, 'storage.josmase.io/linstor-disabled', 'node'))
        self.assertFalse(self.policy.term_excludes_node({'matchFields': [{'key': 'metadata.name', 'operator': 'In', 'values': ['node']}]}, 'storage.josmase.io/linstor-disabled', 'node'))

    def test_safety_gates_and_recovery_are_fail_closed(self):
        tasks = yaml.safe_load((ROLE / 'tasks/main.yml').read_text())
        names = [task['name'] for task in tasks]
        for guard in ('Match the secure token to the verification server CA',
                      'Verify the join endpoint TLS identity from the target',
                      'Check etcd and recovery before a server joins',
                      'Verify storage exclusion before joining',
                      'Verify ownership and effective configuration before a retry'):
            self.assertLess(names.index(guard), names.index('Install prerequisites'))
        validation = next(t for t in tasks if t['name'] == 'Validate node installation inputs')
        assertions = ' '.join(validation['ansible.builtin.assert']['that'])
        self.assertIn('^K10[0-9a-f]{64}::.+$', assertions)
        self.assertIn('k3s_node_install_recovery_restore_verified_sha256', assertions)
        marker = next(t for t in tasks if t['name'] == 'Refuse changes to an established installation identity')
        self.assertEqual(marker['vars']['k3s_node_install_identity']['phase'], 'complete')
        server = yaml.safe_load((ROLE / 'tasks/server_preflight.yml').read_text())
        self.assertIn('k3s_node_install_existing_masters', str(server))
        self.assertIn('k3s_node_install_confirm_even_etcd_members', str(server))
        self.assertIn('k3s_node_install_recovery_snapshot_sha256', str(server))

    def test_quorum_requires_exact_inventory_and_ready_nodes(self):
        ready = {'metadata': {'name': 'one'}, 'status': {'conditions': [{'type': 'Ready', 'status': 'True'}]}}
        self.assertTrue(self.policy.control_plane_ready({'items': [ready]}, ['one']))
        self.assertFalse(self.policy.control_plane_ready({'items': [ready]}, ['one', 'two']))
        ready['status']['conditions'][0]['status'] = 'False'
        self.assertFalse(self.policy.control_plane_ready({'items': [ready]}, ['one']))

    def test_install_marker_accepts_verified_later_release_without_changing_identity(self):
        identity = {'mode': 'agent_join', 'name': 'node-213', 'ip': '192.0.2.10', 'phase': 'complete'}
        marker = dict(identity, version='v1.37.2+k3s1')
        self.assertTrue(self.policy.managed_installation_marker_matches(marker, identity))
        self.assertFalse(self.policy.managed_installation_marker_matches(dict(marker, phase='in_progress'), identity))
        self.assertFalse(self.policy.managed_installation_marker_matches(dict(marker, version='latest'), identity))
        self.assertFalse(self.policy.managed_installation_marker_matches(dict(marker, ip='192.0.2.11'), identity))
        self.assertFalse(self.policy.managed_installation_marker_matches(dict(marker, unexpected=True), identity))
        self.assertFalse(self.policy.managed_installation_marker_matches(None, identity))

    def test_memory_limit_dropin_accepts_only_managed_directive(self):
        good = '# Managed by Ansible (platform/k3s_node_config).\n[Service]\nEnvironment="GOMEMLIMIT=6GiB"\n'
        self.assertTrue(self.policy.managed_gomemlimit_safe(good))
        self.assertFalse(self.policy.managed_gomemlimit_safe(good + 'ExecStart=unsafe\n'))
        self.assertFalse(self.policy.managed_gomemlimit_safe(good.replace('6GiB', 'arbitrary')))
        self.assertFalse(self.policy.managed_gomemlimit_safe(good.replace('GOMEMLIMIT=', 'OTHER=')))

    def test_runtime_configuration_rejects_unknown_and_dangerous_keys(self):
        self.assertTrue(self.policy.runtime_config_safe({'kubelet-arg': ['image-gc-low-threshold=70'], 'enable-pprof': False}))
        self.assertFalse(self.policy.runtime_config_safe({'cluster-reset': True}))
        self.assertFalse(self.policy.runtime_config_safe({'kubelet-arg': ['config=/tmp/unknown']}))
        self.assertFalse(self.policy.runtime_config_safe({'token': 'other'}))


class DropinTaskIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import shutil
        if shutil.which('ansible-playbook') is None:
            raise unittest.SkipTest('ansible-playbook is required')
        tasks = yaml.safe_load((ROLE / 'tasks/retry_preflight.yml').read_text())
        cls.assertion = next(t for t in tasks if t['name'] == 'Require the expected protected memory limit drop-in')
        cls.assertion = dict(cls.assertion)
        cls.assertion.pop('when', None)

    def evaluate(self, matched, stat, files):
        import os
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory(prefix='k3s-dropin-check-') as directory:
            path = Path(directory)
            cfg = path / 'ansible.cfg'
            cfg.write_text('[defaults]\nlocal_tmp=' + str(path / 'local') + '\n')
            play = [{'name': 'Check drop-in decision', 'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                     'vars': {'k3s_node_install_gomemlimit_files': {'matched': matched, 'files': files},
                              'k3s_node_install_gomemlimit': {'stat': stat}}, 'tasks': [self.assertion]}]
            playbook = path / 'check.yml'
            playbook.write_text(yaml.safe_dump(play))
            env = dict(os.environ, ANSIBLE_CONFIG=str(cfg), ANSIBLE_NOCOLOR='1')
            return subprocess.run(['ansible-playbook', '-i', 'localhost,', str(playbook)], env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)

    def test_empty_and_expected_dropin_are_accepted(self):
        self.assertEqual(self.evaluate(0, {'exists': False}, []).returncode, 0)
        expected = [{'path': '/etc/systemd/system/k3s.service.d/20-gomemlimit.conf'}]
        self.assertEqual(self.evaluate(1, {'isreg': True, 'uid': 0, 'mode': '0644'}, expected).returncode, 0)

    def test_unexpected_or_writable_dropin_is_rejected(self):
        expected = [{'path': '/etc/systemd/system/k3s.service.d/20-gomemlimit.conf'}]
        self.assertNotEqual(self.evaluate(1, {'isreg': True, 'uid': 0, 'mode': '0666'}, expected).returncode, 0)
        self.assertNotEqual(self.evaluate(1, {'isreg': True, 'uid': 0, 'mode': '0644'}, [{'path': '/tmp/other.conf'}]).returncode, 0)
        self.assertNotEqual(self.evaluate(2, {'isreg': True, 'uid': 0, 'mode': '0644'}, expected * 2).returncode, 0)

if __name__ == '__main__':
    unittest.main()
