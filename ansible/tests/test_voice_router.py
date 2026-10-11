"""Offline safety tests; no HA calls, tokens or SSH required."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                         'roles/services/home_assistant_voice/files'))
from deploy_router import verified_members, validate_acceptance
from cleanup_router import candidates


class PackageTests(unittest.TestCase):
    def package(self, name):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'release.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('custom_components/bilingual_assist/manifest.json', '{}')
            archive.writestr(name, 'bad')
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_traversal_rejected(self):
        path, sha = self.package('custom_components/bilingual_assist/../../configuration.yaml')
        with self.assertRaises(ValueError):
            verified_members(path, sha)

    def test_foreign_component_rejected(self):
        path, sha = self.package('custom_components/other/__init__.py')
        with self.assertRaises(ValueError):
            verified_members(path, sha)

    def test_checksum_rejected(self):
        path, _ = self.package('custom_components/bilingual_assist/__init__.py')
        with self.assertRaises(ValueError):
            verified_members(path, '0' * 64)

    def test_valid_package(self):
        path, sha = self.package('custom_components/bilingual_assist/__init__.py')
        self.assertEqual(len(verified_members(path, sha)), 2)


class AcceptanceTests(unittest.TestCase):
    def test_complete_report_and_wrong_release(self):
        report = dict(hardware_passed=True, swedish_pipeline_passed=True,
                      gpu_concurrent_passed=True, regression_suite_passed=True,
                      release_sha256='a'*64, model='pinned', regression_questions=40,
                      whisper_revision='08e178d48790749d25932bbc082711ddcfdfbc4f',
                      tested_at=datetime.now(timezone.utc).isoformat())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'acceptance.json'
            path.write_text(json.dumps(report))
            self.assertEqual(validate_acceptance(path, 'a'*64, 'pinned'), report)
            with self.assertRaises(ValueError):
                validate_acceptance(path, 'b'*64, 'pinned')
            report['tested_at'] = '2020-01-01T00:00:00Z'
            path.write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                validate_acceptance(path, 'a'*64, 'pinned')


class OwnershipTests(unittest.TestCase):
    def test_empty_manifest_removes_nothing(self):
        self.assertEqual(candidates({}, [], [], [], {}, []),
                         {'pipelines': [], 'subentries': [], 'entries': []})

    def test_selected_pipeline_refused(self):
        manifest = {'pipelines': [{'id':'old','name':'Legacy'}]}
        states = [{'entity_id':'select.speaker_assistant','state':'Legacy'}]
        with self.assertRaises(ValueError):
            candidates(manifest, manifest['pipelines'], [], [], {}, states)

    def test_referenced_agent_refused(self):
        owned = {'entry_id':'entry','subentry_id':'sub','title':'Old voice'}
        manifest = {'subentries':[owned]}
        entities = [{'entity_id':'conversation.old','config_entry_id':'entry',
                     'config_subentry_id':'sub'}]
        with self.assertRaises(ValueError):
            candidates(manifest, [{'conversation_engine':'conversation.old'}],
                       entities, [], {'entry':[owned]}, [])

    def test_unreferenced_owned_agent_only(self):
        owned = {'entry_id':'entry','subentry_id':'sub','title':'Old voice'}
        other = {'subentry_id':'user','title':'User-owned voice'}
        result = candidates({'subentries':[owned]}, [], [], [],
                            {'entry':[owned,other]}, [])
        self.assertEqual(result['subentries'], [owned])


if __name__ == '__main__':
    unittest.main()
