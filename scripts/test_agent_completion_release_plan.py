import pathlib
import re
import unittest


class AgentCompletionReleasePlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).resolve().parents[1]
        cls.release_plan = (
            root / "docs-ai" / "063-agent-workflows" / "release-plan.md"
        ).read_text()
        cls.signal_plan = (
            root / "docs-ai" / "064-agent-completion-signals" / "000-plan.md"
        ).read_text()

    def test_release_table_records_s2_before_s3(self):
        self.assertRegex(
            self.release_plan,
            re.compile(r"\| 3 \| \*\*S2\*\* .*?\| 064 \| A2, S1 \|"),
        )
        self.assertRegex(
            self.release_plan,
            re.compile(r"\| 4 \| \*\*S3 wave 1\*\* .*?\| 064 \| S2 \|"),
        )

    def test_signal_plan_records_transitive_slice_dependencies(self):
        self.assertRegex(
            self.signal_plan,
            re.compile(r"\| \*\*S2\*\* \| 063-A2, S1 \|"),
        )
        self.assertRegex(
            self.signal_plan,
            re.compile(r"\| \*\*S3 wave 1\*\* \| S2, research matrix \|"),
        )

    def test_dependency_graph_is_linear_through_s2(self):
        self.assertIn("A2 ──┐", self.release_plan)
        self.assertIn("├──► S2 ──► S3w1", self.release_plan)
        self.assertIn("S1 ──┘", self.release_plan)


if __name__ == "__main__":
    unittest.main()
