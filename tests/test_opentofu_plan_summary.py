import json
import pathlib
import subprocess
import unittest


FILTER = pathlib.Path(__file__).resolve().parents[1] / '.gitlab/opentofu/plan_summary.jq'


def summarize(changes):
    result = subprocess.run(
        ['jq', '-r', '-f', str(FILTER)],
        input=json.dumps({'resource_changes': changes}),
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout


def change(address, actions):
    return {'address': address, 'change': {'actions': actions,
            'before': {'password': 'before-secret'}, 'after': {'password': 'after-secret'}}}


class PlanSummaryTests(unittest.TestCase):
    def test_summarizes_actions_without_values(self):
        output = summarize([
            change('cloudflare_record.site', ['create']),
            change('proxmox_virtual_environment_vm.node', ['update']),
            change('cloudflare_record.old', ['delete']),
            change('terraform_data.replaced', ['delete', 'create']),
            change('terraform_data.same', ['no-op']),
        ])
        for word in ('1 create', '1 update', '1 delete', '1 replace'):
            self.assertIn(word, output)
        self.assertIn('cloudflare_record.site', output)
        self.assertNotIn('terraform_data.same', output)
        self.assertNotIn('before-secret', output)
        self.assertNotIn('after-secret', output)

    def test_no_changes_is_clear(self):
        self.assertIn('No resource changes', summarize([]))

    def test_unusual_address_cannot_break_out_of_code_block(self):
        output = summarize([change('test.`\nmalicious', ['create'])])
        self.assertNotIn('test.`\nmalicious', output)

    def test_limits_large_plan_details_without_losing_count(self):
        output = summarize([change(f'terraform_data.item[{i}]', ['create'])
                            for i in range(105)])
        self.assertIn('105 create', output)
        self.assertIn('Only the first 100 resources are shown', output)
        self.assertNotIn('terraform_data.item[104]', output)


if __name__ == '__main__':
    unittest.main()
