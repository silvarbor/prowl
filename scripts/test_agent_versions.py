#!/usr/bin/env python3
"""Tests for the tier-A agent version attestation check.

The version parsers are pinned to the `--version` output each tier-A CLI actually printed on the
attesting Mac, so a runtime that changes its banner fails here before it confuses the report. The
comparison, the missing/unparseable handling, the JSON shape, and the research-matrix drift check
run against fakes, and the drift check additionally runs against the committed record and matrix
so `make test-scripts` notices when one is edited without the other.

Run with `make test-scripts`, or directly:

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

SCRIPT = pathlib.Path(__file__).resolve().parent / "agent_versions.py"

_spec = importlib.util.spec_from_file_location("agent_versions", SCRIPT)
agent_versions = importlib.util.module_from_spec(_spec)
# dataclasses resolve deferred annotations through sys.modules, so register before executing.
sys.modules[_spec.name] = agent_versions
_spec.loader.exec_module(agent_versions)

# Verbatim `--version` output captured on 2026-08-29 (stdout; every binary printed nothing on stderr).
REAL_OUTPUTS = {
    "claude": "2.1.251 (Claude Code)\n",
    "codex": "codex-cli 0.149.1\n",
    "copilot": "GitHub Copilot CLI 1.0.80.\nRun 'copilot update' to check for updates.\n",
    "droid": "0.204.0\n",
    "qodercli": "1.1.31\n",
    "pi": "0.84.3\n",
    "omp": "omp/18.0.6\n",
    "opencode": "1.18.23\n",
}

REAL_VERSIONS = {
    "claude": "2.1.251",
    "codex": "0.149.1",
    "copilot": "1.0.80",
    "droid": "0.204.0",
    "qodercli": "1.1.31",
    "pi": "0.84.3",
    "omp": "18.0.6",
    "opencode": "1.18.23",
}


def entry(binary, version="1.0.0", **overrides):
    fields = {
        "runtime": binary,
        "name": binary.title(),
        "binary": binary,
        "version_command": [binary, "--version"],
        "attested_version": version,
        "attested_on": "2026-08-26",
        "record": "011-s3c-action.md",
    }
    fields.update(overrides)
    return agent_versions.AttestedRuntime.from_json(fields)


class VersionParsing(unittest.TestCase):
    def test_every_real_banner_yields_its_version(self):
        for binary, output in REAL_OUTPUTS.items():
            with self.subTest(binary=binary):
                version = agent_versions.parse_version(output)
                self.assertIsNotNone(version)
                self.assertEqual(version.text, REAL_VERSIONS[binary])

    def test_copilot_trailing_period_is_not_part_of_the_version(self):
        # "GitHub Copilot CLI 1.0.80." — the sentence ends in a period right after the patch.
        self.assertEqual(agent_versions.parse_version(REAL_OUTPUTS["copilot"]).core, (1, 0, 80))

    def test_prefixes_and_prerelease_tags(self):
        self.assertEqual(agent_versions.parse_version("v1.2.3\n").text, "1.2.3")
        version = agent_versions.parse_version("tool 2.0.0-beta.1\n")
        self.assertEqual(version.core, (2, 0, 0))
        self.assertEqual(version.prerelease, "beta.1")
        self.assertEqual(version.text, "2.0.0-beta.1")

    def test_ansi_escapes_are_stripped_before_parsing(self):
        self.assertEqual(agent_versions.parse_version("\x1b[1m3.4.5\x1b[0m (thing)\n").text, "3.4.5")

    def test_output_without_a_version_is_none(self):
        self.assertIsNone(agent_versions.parse_version(""))
        self.assertIsNone(agent_versions.parse_version("Run 'copilot update' to check for updates.\n"))
        # Four dotted components are a build stamp, not a semantic version.
        self.assertIsNone(agent_versions.parse_version("build 1.2.3.4\n"))

    def test_first_version_wins_when_a_banner_mentions_several(self):
        self.assertEqual(agent_versions.parse_version("cli 1.2.3 (node 22.21.1)\n").text, "1.2.3")


class VersionComparison(unittest.TestCase):
    def compare(self, installed, attested):
        return agent_versions.compare_versions(
            agent_versions.parse_version(installed), agent_versions.parse_version(attested)
        )

    def test_equal_is_attested(self):
        self.assertEqual(self.compare("0.149.1", "0.149.1"), "attested")

    def test_numeric_segments_compare_as_integers(self):
        self.assertEqual(self.compare("0.204.0", "0.203.0"), "newer")
        self.assertEqual(self.compare("1.1.31", "1.1.29"), "newer")
        self.assertEqual(self.compare("2.1.251", "2.1.245"), "newer")
        self.assertEqual(self.compare("0.84.2", "0.84.3"), "older")
        self.assertEqual(self.compare("18.0.6", "17.2.7"), "newer")
        self.assertEqual(self.compare("1.18.9", "1.18.23"), "older")

    def test_prerelease_sorts_below_its_release(self):
        self.assertEqual(self.compare("2.0.0-beta.1", "2.0.0"), "older")
        self.assertEqual(self.compare("2.0.0", "2.0.0-beta.1"), "newer")
        self.assertEqual(self.compare("2.0.0-beta.2", "2.0.0-beta.1"), "newer")


class AttestationRecord(unittest.TestCase):
    def test_committed_record_covers_the_tier_a_runtimes(self):
        entries = agent_versions.load_attestation(agent_versions.ATTESTATION_PATH)
        self.assertEqual(tuple(item.runtime for item in entries), agent_versions.TIER_A_RUNTIMES)
        for item in entries:
            with self.subTest(runtime=item.runtime):
                self.assertEqual(item.version_command[0], item.binary)
                self.assertIsNotNone(agent_versions.parse_version(item.attested_version))
                self.assertTrue((agent_versions.ATTESTATION_PATH.parent / item.record).is_file())

    def test_loader_rejects_a_malformed_record(self):
        good = json.loads(agent_versions.ATTESTATION_PATH.read_text())
        cases = {
            "unknown schema": {**good, "schema": 99},
            "duplicate runtime": {**good, "runtimes": good["runtimes"] + [good["runtimes"][0]]},
            "unparseable version": {
                **good,
                "runtimes": [{**good["runtimes"][0], "attested_version": "latest"}],
            },
            "bad date": {**good, "runtimes": [{**good["runtimes"][0], "attested_on": "26/08/2026"}]},
            "missing record": {**good, "runtimes": [{**good["runtimes"][0], "record": "nope.md"}]},
            "extra key": {**good, "runtimes": [{**good["runtimes"][0], "notes": "x"}]},
        }
        with tempfile.TemporaryDirectory() as tmp:
            for label, document in cases.items():
                with self.subTest(case=label):
                    path = pathlib.Path(tmp) / "agent-attestation.json"
                    path.write_text(json.dumps(document))
                    (pathlib.Path(tmp) / "011-s3c-action.md").write_text("# record\n")
                    with self.assertRaises(agent_versions.AttestationError):
                        agent_versions.load_attestation(path)


class ShellPathLookup(unittest.TestCase):
    """The shell fallback reads PATH through a stub shell that behaves like a chatty rc file."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.bin = root / "shell-bin"
        self.bin.mkdir()
        self.shell = root / "stub-shell"
        # Prints a banner first, then evaluates the requested command with an extended PATH.
        self.shell.write_text(
            "#!/bin/sh\necho 'Welcome to the stub shell'\nexport PATH=\"" + str(self.bin) + ":$PATH\"\neval \"$2\"\n"
        )
        self.shell.chmod(self.shell.stat().st_mode | stat.S_IEXEC)

    def tearDown(self):
        self.tmp.cleanup()

    def stub_pi(self):
        stub = self.bin / "pi"
        stub.write_text("#!/bin/sh\necho 0.84.3\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        return stub

    def test_path_is_read_from_the_marker_and_ignores_banners(self):
        path = agent_versions.login_shell_path(shell=str(self.shell))
        self.assertTrue(path.startswith(str(self.bin) + ":"), path)
        self.assertNotIn("Welcome", path)

    def test_failing_shell_yields_none(self):
        self.assertIsNone(agent_versions.login_shell_path(shell=str(self.bin / "does-not-exist")))

    def test_resolver_falls_back_to_the_shell_path_only_when_allowed(self):
        stub = self.stub_pi()
        with unittest.mock.patch.dict(os.environ, {"SHELL": str(self.shell), "PATH": "/usr/bin:/bin"}):
            self.assertIsNone(agent_versions.BinaryResolver(use_login_shell=False)("pi"))
            resolved = agent_versions.BinaryResolver(use_login_shell=True)("pi")
        self.assertEqual(resolved.path, str(stub))
        self.assertEqual(resolved.resolution, "login-shell")
        self.assertTrue(resolved.search_path.startswith(str(self.bin) + ":"))

    def test_resolver_prefers_the_process_path(self):
        self.stub_pi()
        with unittest.mock.patch.dict(os.environ, {"SHELL": str(self.shell), "PATH": str(self.bin)}):
            resolved = agent_versions.BinaryResolver(use_login_shell=True)("pi")
        self.assertEqual(resolved.resolution, "path")


class FakeRunner:
    """Stands in for the binary resolver and the version command."""

    def __init__(self, paths, outputs):
        self.paths = paths
        self.outputs = outputs
        self.commands = []

    def resolve(self, binary):
        return self.paths.get(binary)

    def run(self, command, search_path, timeout):
        self.commands.append((tuple(command), timeout))
        result = self.outputs[command[0]]
        if result == "timeout":
            return agent_versions.CommandResult(stdout="", stderr="", returncode=None, timed_out=True)
        return result


def report_with(entries, paths, outputs):
    runner = FakeRunner(paths, outputs)
    return agent_versions.assess(entries, resolve=runner.resolve, run=runner.run, timeout=5.0)


class Assessment(unittest.TestCase):
    def test_statuses_cover_every_outcome(self):
        entries = [
            entry("claude", "2.1.245"),
            entry("codex", "0.149.1"),
            entry("pi", "0.84.3"),
            entry("droid", "0.203.0"),
            entry("omp", "18.0.6"),
            entry("qodercli", "1.1.29"),
        ]
        paths = {
            "claude": agent_versions.ResolvedBinary("/x/claude", "path", "/x"),
            "codex": agent_versions.ResolvedBinary("/x/codex", "login-shell", "/x"),
            "pi": agent_versions.ResolvedBinary("/x/pi", "path", "/x"),
            "omp": agent_versions.ResolvedBinary("/x/omp", "path", "/x"),
            "qodercli": agent_versions.ResolvedBinary("/x/qodercli", "path", "/x"),
        }
        outputs = {
            "/x/claude": agent_versions.CommandResult(REAL_OUTPUTS["claude"], "", 0, False),
            "/x/codex": agent_versions.CommandResult(REAL_OUTPUTS["codex"], "", 0, False),
            "/x/pi": agent_versions.CommandResult("0.84.2\n", "", 0, False),
            "/x/omp": agent_versions.CommandResult("", "cannot start: no display\n", 1, False),
            "/x/qodercli": "timeout",
        }
        reports = report_with(entries, paths, outputs)
        statuses = {report.entry.runtime: report.status for report in reports}
        self.assertEqual(
            statuses,
            {
                "claude": "newer",
                "codex": "attested",
                "pi": "older",
                "droid": "missing",
                "omp": "unparseable",
                "qodercli": "unparseable",
            },
        )
        by_runtime = {report.entry.runtime: report for report in reports}
        self.assertEqual(by_runtime["claude"].installed.text, "2.1.251")
        self.assertEqual(by_runtime["codex"].resolution, "login-shell")
        self.assertIsNone(by_runtime["droid"].installed)
        self.assertIn("not found", by_runtime["droid"].detail)
        self.assertIn("exited 1", by_runtime["omp"].detail)
        self.assertIn("no display", by_runtime["omp"].detail)
        self.assertIn("timed out after 5s", by_runtime["qodercli"].detail)

    def test_version_is_taken_from_stderr_when_stdout_is_empty(self):
        reports = report_with(
            [entry("pi", "0.84.3")],
            {"pi": agent_versions.ResolvedBinary("/x/pi", "path", "/x")},
            {"/x/pi": agent_versions.CommandResult("", "0.84.3\n", 0, False)},
        )
        self.assertEqual(reports[0].status, "attested")

    def test_version_command_runs_with_the_path_it_was_found_on(self):
        runner = FakeRunner(
            {"pi": agent_versions.ResolvedBinary("/shims/pi", "login-shell", "/shims:/usr/bin")},
            {"/shims/pi": agent_versions.CommandResult("0.84.3\n", "", 0, False)},
        )
        agent_versions.assess([entry("pi", "0.84.3")], resolve=runner.resolve, run=runner.run, timeout=7.0)
        self.assertEqual(runner.commands, [(("/shims/pi", "--version"), 7.0)])

    def test_warnings_point_newer_builds_at_the_contract_gate(self):
        reports = report_with(
            [entry("claude", "2.1.245"), entry("droid", "0.203.0"), entry("pi", "0.84.3")],
            {
                "claude": agent_versions.ResolvedBinary("/x/claude", "path", "/x"),
                "pi": agent_versions.ResolvedBinary("/x/pi", "path", "/x"),
            },
            {
                "/x/claude": agent_versions.CommandResult(REAL_OUTPUTS["claude"], "", 0, False),
                "/x/pi": agent_versions.CommandResult("0.84.3\n", "", 0, False),
            },
        )
        warnings = agent_versions.warnings_for(reports)
        self.assertEqual(len(warnings), 2)
        self.assertIn("claude 2.1.251 is newer than the attested 2.1.245", warnings[0])
        self.assertIn("make test-agent-contracts", warnings[0])
        self.assertIn("011-s3c-action.md", warnings[0])
        self.assertIn("droid", warnings[1])
        self.assertIn("not found", warnings[1])

    def test_table_lists_every_runtime_with_aligned_columns(self):
        reports = report_with(
            [entry("claude", "2.1.245"), entry("droid", "0.203.0")],
            {"claude": agent_versions.ResolvedBinary("/x/claude", "path", "/x")},
            {"/x/claude": agent_versions.CommandResult(REAL_OUTPUTS["claude"], "", 0, False)},
        )
        table = agent_versions.render_table(reports).splitlines()
        self.assertEqual(table[0].split(), ["runtime", "attested", "installed", "status"])
        self.assertEqual(table[1].split(), ["claude", "2.1.245", "2.1.251", "newer"])
        self.assertEqual(table[2].split(), ["droid", "0.203.0", "-", "missing"])
        self.assertEqual(table[1].index("2.1.245"), table[2].index("0.203.0"))

    def test_json_document_carries_the_evidence_per_runtime(self):
        reports = report_with(
            [entry("claude", "2.1.245"), entry("droid", "0.203.0")],
            {"claude": agent_versions.ResolvedBinary("/x/claude", "path", "/x")},
            {"/x/claude": agent_versions.CommandResult(REAL_OUTPUTS["claude"], "", 0, False)},
        )
        document = agent_versions.json_document(reports, pathlib.Path("/repo/agent-attestation.json"))
        self.assertEqual(document["attestation"], "/repo/agent-attestation.json")
        self.assertEqual(document["summary"], {"attested": 0, "newer": 1, "older": 0, "missing": 1, "unparseable": 0})
        claude, droid = document["runtimes"]
        self.assertEqual(
            {key: claude[key] for key in ("runtime", "attested_version", "installed_version", "status", "path")},
            {
                "runtime": "claude",
                "attested_version": "2.1.245",
                "installed_version": "2.1.251",
                "status": "newer",
                "path": "/x/claude",
            },
        )
        self.assertEqual(claude["raw_output"], REAL_OUTPUTS["claude"])
        self.assertEqual(claude["version_command"], ["claude", "--version"])
        self.assertEqual(claude["record"], "011-s3c-action.md")
        self.assertIsNone(droid["installed_version"])
        self.assertIsNone(droid["path"])
        self.assertEqual(droid["status"], "missing")
        json.dumps(document)

    def test_strict_fails_on_anything_but_attested(self):
        attested = report_with(
            [entry("pi", "0.84.3")],
            {"pi": agent_versions.ResolvedBinary("/x/pi", "path", "/x")},
            {"/x/pi": agent_versions.CommandResult("0.84.3\n", "", 0, False)},
        )
        missing = report_with([entry("pi", "0.84.3")], {}, {})
        self.assertEqual(agent_versions.exit_code(attested, strict=False), 0)
        self.assertEqual(agent_versions.exit_code(attested, strict=True), 0)
        self.assertEqual(agent_versions.exit_code(missing, strict=False), 0)
        self.assertEqual(agent_versions.exit_code(missing, strict=True), 1)


class MatrixCheck(unittest.TestCase):
    def setUp(self):
        self.entries = agent_versions.load_attestation(agent_versions.ATTESTATION_PATH)
        self.matrix = agent_versions.MATRIX_PATH.read_text()

    def test_committed_matrix_matches_the_committed_record(self):
        self.assertEqual(agent_versions.check_matrix(self.entries, self.matrix), [])

    def test_rendered_line_lists_every_runtime_and_its_provenance(self):
        line = agent_versions.render_matrix_line(self.entries)
        self.assertTrue(line.startswith(agent_versions.MATRIX_LINE_PREFIX))
        self.assertIn("[agent-attestation.json](agent-attestation.json)", line)
        for item in self.entries:
            self.assertIn(f"{item.binary} {item.attested_version}", line)
            self.assertIn(f"[{item.record}]({item.record})", line)
            self.assertIn(item.attested_on, line)

    def test_provenance_groups_by_sweep(self):
        entries = [
            entry("claude", "2.1.245", attested_on="2026-08-25", record="009-s3b-action.md"),
            entry("pi", "0.84.3"),
            entry("omp", "18.0.6"),
        ]
        line = agent_versions.render_matrix_line(entries)
        self.assertIn("2026-08-25 ([009-s3b-action.md](009-s3b-action.md)): claude", line)
        self.assertIn("2026-08-26 ([011-s3c-action.md](011-s3c-action.md)): pi, omp", line)

    def test_drift_is_reported_per_runtime(self):
        first = self.entries[0]
        drifted = self.matrix.replace(f"{first.binary} {first.attested_version}", f"{first.binary} 0.0.1", 1)
        problems = agent_versions.check_matrix(self.entries, drifted)
        self.assertEqual(len(problems), 2)
        self.assertIn(first.binary, problems[0])
        self.assertIn("matrix 0.0.1", problems[0])
        self.assertIn(f"attestation {first.attested_version}", problems[0])
        self.assertTrue(problems[1].startswith("expected line:\n"))
        self.assertIn("actual line:\n", problems[1])

    def test_missing_and_duplicated_lines_are_reported(self):
        without = "\n".join(
            line for line in self.matrix.splitlines() if not line.startswith(agent_versions.MATRIX_LINE_PREFIX)
        )
        self.assertTrue(any("no line starting with" in problem for problem in agent_versions.check_matrix(self.entries, without)))
        rendered = agent_versions.render_matrix_line(self.entries)
        doubled = self.matrix.replace(rendered, rendered + "\n\n" + rendered, 1)
        self.assertTrue(any("2 lines" in problem for problem in agent_versions.check_matrix(self.entries, doubled)))

    def test_write_matrix_replaces_only_the_generated_line(self):
        first = self.entries[0]
        drifted = self.matrix.replace(f"{first.binary} {first.attested_version}", f"{first.binary} 0.0.1", 1)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "matrix.md"
            path.write_text(drifted)
            self.assertTrue(agent_versions.write_matrix(self.entries, path))
            self.assertEqual(path.read_text(), self.matrix)
            self.assertFalse(agent_versions.write_matrix(self.entries, path))


class CommandLine(unittest.TestCase):
    """Runs the script as `make agent-versions` does, against stub binaries on a private PATH."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.record_dir = root / "record"
        self.record_dir.mkdir()
        (self.record_dir / "011-s3c-action.md").write_text("# record\n")
        self.attestation = self.record_dir / "agent-attestation.json"
        self.attestation.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "description": "test",
                    "runtimes": [
                        entry_json("claude", "2.1.245"),
                        entry_json("copilot", "1.0.80"),
                        entry_json("droid", "0.203.0"),
                    ],
                }
            )
        )
        self.stub("claude", REAL_OUTPUTS["claude"])
        self.stub("copilot", REAL_OUTPUTS["copilot"])

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self, name, output):
        path = self.bin / name
        path.write_text("#!/bin/sh\nprintf '%s' " + shell_quote(output) + "\n")
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_script(self, *args):
        env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin"}
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--attestation", str(self.attestation), "--no-login-shell", *args],
            capture_output=True,
            text=True,
            env=env,
        )

    def test_table_and_warnings(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [line.split() for line in result.stdout.splitlines()]
        self.assertEqual(rows[0], ["runtime", "attested", "installed", "status"])
        self.assertEqual(rows[1], ["claude", "2.1.245", "2.1.251", "newer"])
        self.assertEqual(rows[2], ["copilot", "1.0.80", "1.0.80", "attested"])
        self.assertEqual(rows[3], ["droid", "0.203.0", "-", "missing"])
        self.assertIn("make test-agent-contracts", result.stderr)
        self.assertIn("droid", result.stderr)

    def test_strict_exit_code(self):
        self.assertEqual(self.run_script("--strict").returncode, 1)

    def test_json_output(self):
        result = self.run_script("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        document = json.loads(result.stdout)
        self.assertEqual([item["status"] for item in document["runtimes"]], ["newer", "attested", "missing"])
        self.assertEqual(document["runtimes"][0]["path"], str(self.bin / "claude"))
        self.assertEqual(document["runtimes"][0]["resolution"], "path")

    def test_check_matrix_reports_drift_and_exit_code(self):
        entries = agent_versions.load_attestation(self.attestation)
        matrix = self.record_dir / "matrix.md"
        matrix.write_text("# Matrix\n\n" + agent_versions.render_matrix_line(entries) + "\n")
        ok = self.run_script("--check-matrix", "--matrix", str(matrix))
        self.assertEqual(ok.returncode, 0, ok.stderr)
        matrix.write_text(matrix.read_text().replace("droid 0.203.0", "droid 0.202.0"))
        drifted = self.run_script("--check-matrix", "--matrix", str(matrix))
        self.assertEqual(drifted.returncode, 1)
        self.assertIn("droid: matrix 0.202.0, attestation 0.203.0", drifted.stderr)
        fixed = self.run_script("--write-matrix", "--matrix", str(matrix))
        self.assertEqual(fixed.returncode, 0, fixed.stderr)
        self.assertEqual(self.run_script("--check-matrix", "--matrix", str(matrix)).returncode, 0)


def entry_json(binary, version):
    return {
        "runtime": binary,
        "name": binary.title(),
        "binary": binary,
        "version_command": [binary, "--version"],
        "attested_version": version,
        "attested_on": "2026-08-26",
        "record": "011-s3c-action.md",
    }


def shell_quote(text):
    return "'" + text.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
