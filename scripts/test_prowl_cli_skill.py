import pathlib
import unittest


class ProwlCLISkillTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).resolve().parents[1]
        cls.skill = (root / "skills" / "prowl-cli" / "SKILL.md").read_text()

    def test_documents_shipped_dispatch_wait_flow(self):
        self.assertIn('dispatch="$(printf', self.skill)
        self.assertIn('prowl agents wait --dispatch "$dispatch"', self.skill)
        self.assertIn("DISPATCH_INCOMPLETE", self.skill)
        self.assertNotIn("When\n`agents wait` ships", self.skill)

    def test_labels_heuristic_results_and_requires_screen_review(self):
        self.assertIn('confidence == "heuristic"', self.skill)
        self.assertIn("never treat heuristic evidence as task completion", self.skill)
        self.assertIn("re-arm the wait", self.skill)

    def test_documents_structured_wait_errors(self):
        self.assertIn(".error.details", self.skill)
        self.assertIn("DISPATCH_NEEDS_INPUT", self.skill)
        self.assertIn('agents wait "$pane" --until changed', self.skill)
        self.assertIn(".error.details.mode", self.skill)
        self.assertIn("WAIT_TIMEOUT", self.skill)


if __name__ == "__main__":
    unittest.main()
