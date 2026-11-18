import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / '.gitlab' / 'opentofu' / 'post_plan_summary.sh'


class PlanCommentTests(unittest.TestCase):
    def test_posts_only_actions_and_addresses(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            plan = directory / 'plan.json'
            payload = directory / 'posted.json'
            plan.write_text(json.dumps({'resource_changes': [{
                'address': 'cloudflare_record.site',
                'change': {'actions': ['update'], 'after': {'token': 'secret-value'}},
            }]}))
            tofu = directory / 'tofu'
            tofu.write_text('#!/bin/sh\ncat "$FAKE_PLAN"\n')
            tofu.chmod(0o755)
            curl = directory / 'curl'
            curl.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = --data-binary ]; then
    shift
    cp "${1#@}" "$FAKE_POSTED"
  fi
  shift
done
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f'{tmp}:{os.environ["PATH"]}',
                       CI_PROJECT_DIR=str(ROOT), CI_MERGE_REQUEST_IID='5',
                       CI_PROJECT_ID='2', CI_API_V4_URL='https://gitlab.example/api/v4',
                       CI_COMMIT_SHORT_SHA='12345678', CI_JOB_URL='https://gitlab.example/job/1',
                       TF_STATE_NAME='dns', TOFU_MR_COMMENT_TOKEN='dummy-token',
                       FAKE_PLAN=str(plan), FAKE_POSTED=str(payload))
            subprocess.run(['bash', str(SCRIPT)], cwd=tmp, env=env, check=True,
                           capture_output=True, text=True)
            body = json.loads(payload.read_text())['body']
            self.assertIn('1 update', body)
            self.assertIn('cloudflare_record.site', body)
            self.assertNotIn('secret-value', body)
            self.assertNotIn('dummy-token', body)


if __name__ == '__main__':
    unittest.main()
