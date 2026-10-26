"""Offline regression checks using actual Ansible tasks and fake K3s commands.

Run: python3 -m unittest discover -s ansible/tests -p 'test_k3s_upgrade_safety.py'
Requires ansible-playbook, git, and PyYAML; never contacts a cluster.
"""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / 'roles/platform/k3s_application_maintenance'
FAKE_K3S = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['K3S_TEST_DIR'])
config = json.loads((root / 'scenario.json').read_text())
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as handle:
    handle.write(json.dumps(args) + '\n')
if args == ['--version']:
    print(config.get('installed', 'k3s version v1.31.14+k3s1 (commit)'))
    sys.exit(0)
if config.get('fail') and config['fail'] in ' '.join(args):
    print('simulated Kubernetes command failure', file=sys.stderr)
    sys.exit(1)
if 'get' in args:
    kind = args[args.index('get') + 1]
    if kind == 'kustomization.kustomize.toolkit.fluxcd.io':
        print(json.dumps({'metadata': {'name': args[args.index('get') + 2]}, 'spec': {'suspend': False}}))
    elif kind == 'deployment,statefulset':
        print(json.dumps({'items': [{'kind': 'Deployment', 'metadata': {'name': 'app', 'namespace': 'default'}, 'spec': {'replicas': 1}, 'status': {'replicas': 4}}]}))
    elif kind == 'cronjob':
        print(json.dumps({'items': [{'metadata': {'name': 'cron', 'namespace': 'default'}, 'spec': {'suspend': config.get('cron_suspended', False)}}]}))
    elif kind in ('jobs', 'pods'):
        counter = root / (kind + '.count')
        count = int(counter.read_text()) if counter.exists() else 0
        counter.write_text(str(count + 1))
        pending = config.get(kind + '_pending', 0)
        active = pending == -1 or count < pending
        if kind == 'jobs':
            items = [{'status': {'active': 1}}] if active else []
        else:
            # Includes an unmanaged Pod and a DaemonSet; only the latter may remain.
            items = [{'metadata': {'ownerReferences': [{'kind': 'DaemonSet'}]}, 'status': {'phase': 'Running'}}]
            if active:
                items.append({'metadata': {'name': 'app-pod', 'deletionTimestamp': 'now'}, 'status': {'phase': 'Running'}})
        print(json.dumps({'items': items}))
    else:
        raise SystemExit('unexpected resource: ' + kind)
else:
    print('ok')
'''


class LocalHarness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='k3s-safety-')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.api = self.path / 'k3s'
        self.api.write_text(FAKE_K3S)
        self.api.chmod(0o755)
        self.state = self.path / 'state.json'
        self.lock = self.path / 'state.lock'
        self.config = self.path / 'ansible.cfg'
        self.config.write_text('[defaults]\nforks=1\nretry_files_enabled=False\nlocal_tmp=' + str(self.path / 'local') + '\nremote_tmp=' + str(self.path / 'remote') + '\n')
        # Production runs as root. Keep the same task logic in an unprivileged
        # fixture, changing only saved-file ownership for this local user.
        role_path = self.path / 'roles/platform/k3s_application_maintenance'
        shutil.copytree(ROLE, role_path)
        prepare = role_path / 'tasks/prepare.yml'
        prepare.write_text(prepare.read_text().replace('owner: root', f"owner: '{os.geteuid()}'").replace('group: root', f"group: '{os.getegid()}'"))
        self.env = dict(os.environ, ANSIBLE_CONFIG=str(self.config), ANSIBLE_ROLES_PATH=str(self.path / 'roles'), K3S_TEST_DIR=str(self.path), ANSIBLE_NOCOLOR='1')
        self.scenario()

    def scenario(self, **values):
        (self.path / 'scenario.json').write_text(json.dumps(values))

    def calls(self):
        log = self.path / 'calls.jsonl'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def saved_state(self, **changes):
        state = {'version': 1, 'flux_kustomizations': [{'metadata': {'name': 'apps-test'}, 'spec': {'suspend': False}}], 'workloads': [{'kind': 'Deployment', 'metadata': {'name': 'app', 'namespace': 'default'}, 'spec': {'replicas': 1}}], 'cronjobs': [{'metadata': {'name': 'cron', 'namespace': 'default'}, 'spec': {'suspend': True}}]}
        state.update(changes)
        self.state.write_text(json.dumps(state))

    def run_play(self, play):
        path = self.path / 'play.yml'
        path.write_text(yaml.safe_dump([play]))
        return subprocess.run(['ansible-playbook', '-i', 'localhost,', str(path)], env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)

    def maintenance(self, action):
        return self.run_play({'hosts': 'localhost', 'connection': 'local', 'gather_facts': False, 'vars': {
            'ansible_python_interpreter': shutil.which('python3'),
            'k3s_maintenance_action': action,
            'k3s_application_maintenance_api': str(self.api),
            'k3s_application_maintenance_state_path': str(self.state),
            'k3s_application_maintenance_lock_path': str(self.lock),
            'k3s_application_maintenance_flux_kustomizations': ['apps-test'],
            'k3s_application_maintenance_namespaces': ['default'],
            'k3s_application_maintenance_capacity_retries': 1,
            'k3s_application_maintenance_capacity_delay': 0,
            'k3s_application_maintenance_flux_timeout': '1s',
        }, 'roles': ['platform/k3s_application_maintenance']})


class MaintenanceTests(LocalHarness):
    def test_existing_record_is_untouched(self):
        self.saved_state()
        original = self.state.read_text()
        result = self.maintenance('prepare')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.state.read_text(), original)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.lock.exists())

    def test_existing_action_lock_is_not_removed(self):
        self.lock.mkdir()
        result = self.maintenance('prepare')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.lock.exists())
        self.assertEqual(self.calls(), [])

    def test_capture_failure_does_not_attempt_restoration(self):
        self.scenario(fail='get deployment,statefulset')
        result = self.maintenance('prepare')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.state.exists())
        self.assertFalse(any('patch' in c or 'scale' in c for c in self.calls()))

    def test_waits_for_jobs_and_actual_pods(self):
        self.scenario(jobs_pending=1, pods_pending=1)
        result = self.maintenance('prepare')
        self.assertEqual(result.returncode, 0, result.stdout)
        calls = self.calls()
        jobs = [i for i, c in enumerate(calls) if 'jobs' in c]
        pods = [i for i, c in enumerate(calls) if 'pods' in c]
        scale = next(i for i, c in enumerate(calls) if '--replicas=0' in c)
        self.assertEqual(len(jobs), 2)
        self.assertTrue(all('--all-namespaces' in calls[i] for i in jobs))
        self.assertEqual(len(pods), 2)
        self.assertLess(max(jobs), scale)
        self.assertLess(scale, min(pods))
        self.assertTrue(self.state.exists())
        self.assertFalse(self.lock.exists())

    def test_running_jobs_block_scale_down_and_restore_flux(self):
        self.scenario(jobs_pending=-1)
        result = self.maintenance('prepare')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any('--replicas=0' in c for c in self.calls()))
        self.assertTrue(any('patch' in c and 'kustomization.kustomize.toolkit.fluxcd.io' in c and json.loads(c[-1])['spec']['suspend'] is False for c in self.calls()))
        self.assertFalse(self.state.exists())

    def test_terminating_pods_block_preparation_and_recover(self):
        self.scenario(pods_pending=-1)
        result = self.maintenance('prepare')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(any('--replicas=1' in c for c in self.calls()))
        self.assertFalse(self.state.exists())

    def test_scale_failure_still_restores_flux_and_retains_state(self):
        self.saved_state()
        self.scenario(fail='scale')
        result = self.maintenance('restore')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(any('patch' in c and 'kustomization.kustomize.toolkit.fluxcd.io' in c for c in self.calls()))
        self.assertTrue(self.state.exists())
        self.assertFalse(self.lock.exists())

    def test_cronjob_failure_still_restores_flux_and_retains_state(self):
        self.saved_state()
        self.scenario(fail='patch cronjob')
        result = self.maintenance('restore')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(any('patch' in c and 'kustomization.kustomize.toolkit.fluxcd.io' in c for c in self.calls()))
        self.assertTrue(self.state.exists())

    def test_one_flux_failure_does_not_skip_other_flux_resources(self):
        self.saved_state(flux_kustomizations=[{'metadata': {'name': name}, 'spec': {'suspend': False}} for name in ['apps-test', 'apps-other']])
        self.scenario(fail='patch kustomization.kustomize.toolkit.fluxcd.io apps-test')
        result = self.maintenance('restore')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(any('patch' in c and 'apps-other' in c for c in self.calls()))
        self.assertTrue(self.state.exists())

    def test_success_restores_original_flags_and_removes_state(self):
        self.saved_state()
        result = self.maintenance('restore')
        self.assertEqual(result.returncode, 0, result.stdout)
        cron_patch = next(c for c in self.calls() if 'patch' in c and 'cronjob' in c)
        self.assertTrue(json.loads(cron_patch[-1])['spec']['suspend'])
        self.assertFalse(self.state.exists())
        self.assertFalse(self.lock.exists())


class VersionTests(LocalHarness):
    def test_version_transition_guards(self):
        source = (ROOT / 'roles/platform/k3s_rolling_upgrade/tasks/version_preflight.yml').read_text()
        # Run the actual tasks, substituting only the executable with the fake.
        task_path = self.path / 'version.yml'
        task_path.write_text(source.replace('/usr/local/bin/k3s', str(self.api)))
        for installed, target, allowed in [
            ('v1.31.14+k3s1', 'v1.32.13+k3s1', True),
            ('v1.32.13+k3s1', 'v1.32.13+k3s1', True),
            ('v1.33.13+k3s2', 'v1.32.13+k3s1', False),
            ('v1.32.14+k3s1', 'v1.32.13+k3s1', False),
            ('v1.32.13+k3s2', 'v1.32.13+k3s1', False),
            ('v1.30.14+k3s1', 'v1.32.13+k3s1', False),
            ('v1.31.14+k3s1', 'v2.0.0+k3s1', False),
            ('v1.31.14+k3s1', 'not-a-version', False),
            ('unknown', 'v1.32.13+k3s1', False),
        ]:
            with self.subTest(installed=installed, target=target):
                self.scenario(installed='k3s version ' + installed + ' (commit)')
                result = self.run_play({'hosts': 'localhost', 'connection': 'local', 'gather_facts': False, 'vars': {'ansible_python_interpreter': shutil.which('python3'), 'k3s_upgrade_target_version': target}, 'tasks': [{'ansible.builtin.include_tasks': str(task_path)}]})
                self.assertEqual(result.returncode == 0, allowed, result.stdout)


class ProgramTests(unittest.TestCase):
    def run_program(self, failure='', lock_held=False, target='v1.32.13+k3s1'):
        with tempfile.TemporaryDirectory(prefix='k3s-program-') as directory:
            path = Path(directory)
            repo = path / 'repo'
            scripts = repo / 'ansible/scripts'
            scripts.mkdir(parents=True)
            shutil.copy(ROOT / 'scripts/run-k3s-upgrade-program.sh', scripts)
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@localhost', 'commit', '-qm', 'fixture'], check=True)
            binary = path / 'bin'
            binary.mkdir()
            fake = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with Path(os.environ['PROGRAM_LOG']).open('a') as f: f.write(json.dumps([Path(sys.argv[0]).name] + sys.argv[1:])+'\\n')
args=' '.join(sys.argv[1:])
failure=os.environ['PROGRAM_FAILURE']
sys.exit(7 if failure and failure in args else 0)
'''
            executable = binary / 'ansible-playbook'
            executable.write_text(fake)
            executable.chmod(0o755)
            kubectl = binary / 'kubectl'
            kubectl.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
with Path(os.environ['PROGRAM_LOG']).open('a') as f: f.write(json.dumps(['kubectl'] + args)+'\\n')
if 'nodes' in args:
    version=os.environ['PROGRAM_TARGET']
    print(json.dumps({'items':[{'metadata':{'name':'node-1'},'status':{'nodeInfo':{'kubeletVersion':version},'conditions':[{'type':'Ready','status':'True'}]}}]}))
elif 'kustomizations.kustomize.toolkit.fluxcd.io' in args:
    print(json.dumps({'items':[{'metadata':{'namespace':'flux-system','name':'apps-test'},'status':{'conditions':[{'type':'Ready','status':'True'}]}}]}))
else:
    raise SystemExit('unexpected kubectl call: ' + ' '.join(args))
''')
            kubectl.chmod(0o755)
            log = path / 'calls.jsonl'
            env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], PROGRAM_LOG=str(log), PROGRAM_FAILURE=failure, PROGRAM_TARGET=target)
            lock_handle = (repo / '.git/k3s-upgrade-program.lock').open('w')
            if lock_held:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.addCleanup(lock_handle.close)
            result = subprocess.run(['bash', str(scripts / 'run-k3s-upgrade-program.sh'), target], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_concurrent_program_is_refused_before_any_commands(self):
        result, calls = self.run_program(lock_held=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertIn('Another K3s upgrade program is running', result.stdout)

    def test_preflight_failure_prevents_all_maintenance(self):
        result, calls = self.run_program('k3s_upgrade_preflight.yml')
        self.assertNotEqual(result.returncode, 0)
        ansible_calls = [call for call in calls if call[0] == 'ansible-playbook']
        self.assertEqual(len(ansible_calls), 1)
        self.assertFalse(any('k3s_maintenance_action=prepare' in call for call in ansible_calls))

    def test_upgrade_failure_stops_and_restores(self):
        result, calls = self.run_program('k3s_rolling_upgrade.yml')
        self.assertNotEqual(result.returncode, 0)
        ansible_calls = [call for call in calls if call[0] == 'ansible-playbook']
        self.assertEqual(len(ansible_calls), 4)
        self.assertIn('k3s_maintenance_action=restore', ansible_calls[-1])

    def test_restore_failure_is_reported_and_stops_next_minor(self):
        result, calls = self.run_program('k3s_maintenance_action=restore')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len([call for call in calls if call[0] == 'ansible-playbook']), 5)
        self.assertIn('Application restoration failed', result.stdout)

    def test_one_invocation_runs_exactly_one_minor(self):
        result, calls = self.run_program()
        self.assertEqual(result.returncode, 0, result.stdout)
        ansible_calls = [call for call in calls if call[0] == 'ansible-playbook']
        self.assertEqual(len(ansible_calls), 4)
        self.assertIn('playbooks/maintenance/k3s_upgrade_preflight.yml', ansible_calls[0])
        self.assertIn('k3s_maintenance_action=prepare', ansible_calls[1])
        self.assertIn('playbooks/maintenance/k3s_rolling_upgrade.yml', ansible_calls[2])
        self.assertIn('k3s_upgrade_target_version=v1.32.13+k3s1', ansible_calls[2])
        self.assertIn('kube_vip_upgrade_target_version=v1.3.0', ansible_calls[2])
        self.assertIn('k3s_maintenance_action=restore', ansible_calls[3])
        self.assertFalse(any(call[0] == 'ssh' for call in calls))
        inventory = yaml.safe_load((ROOT / 'inventory/group_vars/k3s_cluster/vars.yml').read_text())
        self.assertEqual(inventory['kube_vip_tag_version'], 'v1.3.0')

    def test_unsupported_target_is_refused_before_cluster_access(self):
        result, calls = self.run_program(target='v1.35.10+k3s1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
