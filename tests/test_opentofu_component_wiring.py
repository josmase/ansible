import pathlib
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]
COMPONENT = (
    "$CI_SERVER_FQDN/josmase/infrastructure/ci-templates/"
    "ansible-opentofu@v4.2.0"
)
SHARED_CHANGED_PATHS = [".gitlab-ci.yml"]


class OpenTofuComponentWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pipeline = yaml.safe_load((ROOT / ".gitlab-ci.yml").read_text())

    def test_each_parent_root_uses_pinned_component_inputs(self):
        expected_roots = {
            "dns": ("opentofu/dns", "dns"),
            "virtual-machines": (
                "opentofu/virtual-machines",
                "virtual-machines",
            ),
        }

        for job_name, (tf_root, state_name) in expected_roots.items():
            with self.subTest(root=job_name):
                trigger = self.pipeline[job_name]["trigger"]
                included = trigger["include"][0]
                self.assertEqual(included["component"], COMPONENT)
                self.assertEqual(
                    included["inputs"],
                    {"tf_root": tf_root, "state_name": state_name},
                )

    def test_parent_root_selection_rules_are_preserved(self):
        for job_name, root in (
            ("dns", "dns"),
            ("virtual-machines", "virtual-machines"),
        ):
            with self.subTest(root=job_name):
                self.assertEqual(
                    self.pipeline[job_name]["rules"],
                    [
                        {
                            "if": f'$CI_PIPELINE_SOURCE == "web" && '
                            f'($TOFU_ROOT == "{root}" || $TOFU_ROOT == "all")'
                        },
                        {
                            "if": '$CI_PIPELINE_SOURCE == "merge_request_event" '
                            '|| ($CI_PIPELINE_SOURCE == "push" && '
                            '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH)',
                            "changes": [
                                f"opentofu/{root}/**/*",
                                *SHARED_CHANGED_PATHS,
                            ],
                        },
                    ],
                )

    def test_pipeline_workflow_still_limits_supported_sources(self):
        self.assertEqual(
            self.pipeline["workflow"]["rules"],
            [
                {
                    "if": '$CI_PIPELINE_SOURCE == "merge_request_event" && '
                    '$CI_MERGE_REQUEST_SOURCE_PROJECT_ID == $CI_PROJECT_ID'
                },
                {
                    "if": '$CI_PIPELINE_SOURCE == "push" && '
                    '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
                },
                {
                    "if": '$CI_PIPELINE_SOURCE == "web" && '
                    '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
                },
                {"when": "never"},
            ],
        )


if __name__ == "__main__":
    unittest.main()
