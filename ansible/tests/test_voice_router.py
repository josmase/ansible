"""Offline safety tests; no HA calls, tokens or SSH required."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                         'roles/services/home_assistant_voice/files'))
from deploy_router import (verified_members, validate_acceptance, conversation_entity_available,
                           release_fingerprint, configure_pipeline, CANDIDATE)
from cleanup_router import candidates


class PackageTests(unittest.TestCase):
    def package(self, name):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'release.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('custom_components/bilingual_assist/manifest.json', '{"domain":"bilingual_assist"}')
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
    def release(self):
        return dict(stt_revision='c'*40,stt_image='stt@sha256:'+'d'*64,
                    tts_image='tts@sha256:'+'e'*64,model_digest='f'*64,
                    configuration={'pipeline':dict(stt_engine='stt.test',stt_language='sv',
                        tts_engine='tts.test',tts_language='en-us',tts_voice='af_heart',
                        wake_word_entity=None,wake_word_id=None),
                        'router':dict(ollama_url='https://ollama.test',model='pinned',
                            search_url='https://search.test',search_username='assist',search_enabled=True,
                            session_timeout=60,max_turns=2,num_ctx=4096,debug_text=False,
                            recovery_enabled=True,classify_questions=True)})

    def report(self,release):
        return dict(hardware_passed=True,gpu_concurrent_passed=True,regression_suite_passed=True,
                    search_passed=True,idempotency_passed=True,playback_passed=True,
                    release_sha256='a'*64,model='pinned',release_fingerprint=release_fingerprint(release),
                    tested_at=datetime.now(timezone.utc).isoformat(),
                    metrics=dict(recorded_utterances=80,held_out_utterances=40,
                        ordinary_accuracy=.95,recovery_accuracy=.90,concurrency_minutes=30,
                        idle_free_vram_mib=2048,concurrent_free_vram_mib=1024,
                        unsafe_executions=0,duplicate_actions=0,duplicate_responses=0,
                        ooms=0,playback_failures=0,ordinary_median_seconds=2.5,
                        ordinary_p95_seconds=4,recovery_p95_seconds=6))

    def test_complete_report_and_wrong_release(self):
        release=self.release()
        report=self.report(release)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'acceptance.json'
            path.write_text(json.dumps(report))
            self.assertEqual(validate_acceptance(path, 'a'*64, 'pinned',release), report)
            with self.assertRaises(ValueError):
                validate_acceptance(path, 'b'*64, 'pinned',release)
            report['tested_at'] = '2020-01-01T00:00:00Z'
            path.write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                validate_acceptance(path, 'a'*64, 'pinned',release)

    def test_missing_or_failed_metrics_cannot_promote(self):
        release=self.release()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'acceptance.json'
            for metric,value in [('recorded_utterances',79),('held_out_utterances',39),
                                 ('unsafe_executions',1),('ordinary_p95_seconds',4.1),
                                 ('idle_free_vram_mib',2047),('ordinary_accuracy',float('nan')),
                                 ('ooms',None),('duplicate_responses',True)]:
                report=self.report(release)
                report['metrics'][metric]=value
                path.write_text(json.dumps(report))
                with self.subTest(metric=metric),self.assertRaises(ValueError):
                    validate_acceptance(path,'a'*64,'pinned',release)

    def test_configuration_change_invalidates_report(self):
        release=self.release()
        report=self.report(release)
        release['configuration']['router']['num_ctx']=8192
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'acceptance.json'
            path.write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                validate_acceptance(path,'a'*64,'pinned',release)

    def test_unpinned_or_secret_configuration_refused(self):
        release=self.release()
        release['stt_image']='stt:latest'
        with self.assertRaises(ValueError): release_fingerprint(release)
        release=self.release()
        release['configuration']['router']['search_password']='must-never-be-here'
        with self.assertRaises(ValueError): release_fingerprint(release)


class StagingTests(unittest.TestCase):
    def test_fresh_stage_creates_full_pipeline_without_selecting(self):
        class WS:
            def __init__(self): self.calls=[]
            def command(self,payload):
                self.calls.append(payload)
                if payload['type'].endswith('/list'): return {'pipelines':[]}
                return {}
        ws=WS()
        pipeline=AcceptanceTests().release()['configuration']['pipeline']
        with patch('deploy_router.http_json') as http:
            self.assertTrue(configure_pipeline(ws,'url','token','conversation.v2',[],pipeline))
            http.assert_not_called()
        self.assertEqual(len(ws.calls),2)
        self.assertEqual(ws.calls[1]['name'],CANDIDATE)
        self.assertEqual(ws.calls[1]['tts_voice'],'af_heart')
        self.assertFalse(ws.calls[1]['prefer_local_intents'])

    def test_selected_candidate_cannot_be_changed(self):
        class WS:
            def command(self,payload):
                return {'pipelines':[{'id':'active','name':CANDIDATE}], 'preferred_pipeline':'active'}
        with self.assertRaises(ValueError):
            configure_pipeline(WS(),'url','token','conversation.v2',[],{})

    def test_identical_stage_is_idempotent(self):
        pipeline=AcceptanceTests().release()['configuration']['pipeline']
        current={**pipeline,'id':'test','name':CANDIDATE,'language':'sv','conversation_language':'sv',
                 'conversation_engine':'conversation.v2','prefer_local_intents':False}
        class WS:
            def command(self,payload):
                assert payload['type']=='assist_pipeline/pipeline/list'
                return {'pipelines':[current],'preferred_pipeline':'production'}
        with patch('deploy_router.http_json') as http:
            self.assertFalse(configure_pipeline(WS(),'url','token','conversation.v2',[],pipeline))
            http.assert_not_called()


class ConversationEntityTests(unittest.TestCase):
    def test_unknown_state_is_ready_for_conversation_entity(self):
        self.assertTrue(conversation_entity_available(
            'conversation.bilingual', [{'entity_id':'conversation.bilingual','state':'unknown'}]))

    def test_unavailable_or_missing_entity_is_not_ready(self):
        self.assertFalse(conversation_entity_available(
            'conversation.bilingual', [{'entity_id':'conversation.bilingual','state':'unavailable'}]))
        self.assertFalse(conversation_entity_available('conversation.bilingual', []))


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
