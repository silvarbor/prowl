import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class AssertXCResultTestsTests(unittest.TestCase):
    def test_rejects_result_bundle_with_wrong_expected_test_count(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            result_bundle = root / "result.xcresult"
            result_bundle.mkdir()
            bin_directory = root / "bin"
            bin_directory.mkdir()
            xcrun = bin_directory / "xcrun"
            xcrun.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' '{\"result\":\"Passed\",\"totalTestCount\":1,\"failedTests\":0}'\n"
            )
            xcrun.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{bin_directory}:{environment['PATH']}"

            completed = subprocess.run(
                [
                    "bash",
                    "scripts/assert-xcresult-tests.sh",
                    str(result_bundle),
                    "2",
                ],
                capture_output=True,
                check=False,
                env=environment,
                text=True,
            )

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("expected 2 tests, found 1", completed.stderr)


if __name__ == "__main__":
    unittest.main()
