import tempfile
import unittest
from pathlib import Path

from shelf_trace_summary import read_rows, summarize


def event(time, name, kind="Event"):
    return {"time": str(time), "name": name, "event-type": kind, "subsystem": "com.onevcat.prowl"}


class ShelfTraceSummaryTests(unittest.TestCase):
    def test_resolves_interned_values_and_nested_definitions(self):
        xml = """<trace-query-result><node><schema>
          <col><mnemonic>name</mnemonic><engineering-type>string</engineering-type></col>
          <col><mnemonic>ignored</mnemonic><engineering-type>typed-array</engineering-type></col>
        </schema><row><string id="1">first</string><typed-array>
          <string id="2">second</string></typed-array></row>
          <row><string ref="2"/><sentinel/></row>
          <row><string ref="1"/><sentinel/></row></node></trace-query-result>"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "export.xml"
            path.write_text(xml)
            self.assertEqual(list(read_rows(path, {"name"})), [
                {"name": "first"}, {"name": "second"}, {"name": "first"},
            ])

    def test_counts_calls_including_final_animation_but_excludes_startup(self):
        poi = [
            event(1, "ShelfView.body"),
            event(1_000_000_000, "reducer.selectRepository", "Begin"),
            event(1_000_010_000, "reducer.selectRepository", "End"),
            event(1_100_000_000, "ShelfView.body"),
            event(2_000_000_000, "reducer.selectWorktree", "Begin"),
            event(2_200_000_000, "ShelfView.body"),
            event(3_000_000_000, "ShelfView.body"),
        ]
        updates = [
            {"start": "1200000000", "update-type": "Layout Updates", "description": "Size That Fits"},
            {"start": "2200000000", "update-type": "Other Updates", "description": "Layout: AnimatableFrameAttribute"},
            {"start": "3000000000", "update-type": "Layout Updates", "description": "Size That Fits"},
        ]
        # Clip hitches at both window edges instead of dropping crossing intervals.
        hitches = [{"start": "990000000", "duration": "20000000"},
                   {"start": "2340000000", "duration": "20000000"}]
        result = summarize(poi, updates, hitches, expected_switches=2)
        self.assertEqual(result["switches"], 2)
        self.assertEqual(result["signposts"]["ShelfView.body"], 2)
        self.assertEqual(result["updates"]["total"], 2)
        self.assertEqual(result["updates"]["by_type"]["Layout Updates"], 1)
        self.assertEqual(result["hitches"]["overlap_ms"], 20)
        self.assertEqual(result["hitches"]["ms_per_switch"], 10)

    def test_rejects_missing_or_incomplete_workload(self):
        with self.assertRaises(ValueError):
            summarize([], [], [], expected_switches=30)
        with self.assertRaises(ValueError):
            summarize([event(1, "reducer.selectRepository", "Begin")], [], [], expected_switches=30)

    def test_does_not_count_end_events_or_other_subsystems_as_switches(self):
        unrelated = event(2, "reducer.selectRepository", "Begin")
        unrelated["subsystem"] = "another.app"
        result = summarize([
            event(1, "reducer.selectRepository", "Begin"),
            unrelated,
            event(3, "reducer.selectRepository", "End"),
        ], [], [], expected_switches=1)
        self.assertEqual(result["signposts"]["reducer.selectRepository"], 1)

    def test_accepts_debug_app_subsystem(self):
        selection = event(1, "reducer.selectRepository", "Begin")
        selection["subsystem"] = "com.onevcat.prowl.debug"
        self.assertEqual(summarize([selection], [], [], expected_switches=1)["switches"], 1)

    def test_attributes_only_layout_updates_to_views(self):
        selection = event(100, "reducer.selectRepository", "Begin")
        updates = [
            {"start": "101", "update-type": "Layout Updates", "description": "Size That Fits",
             "view-name": "TerminalSplitTreeAXContainer"},
            {"start": "102", "update-type": "Layout Updates", "description": "Center Alignment",
             "view-name": "TerminalSplitTreeAXContainer"},
            {"start": "103", "update-type": "Other Updates", "description": "View Responders",
             "view-name": "TerminalSplitTreeAXContainer"},
        ]
        result = summarize([selection], updates, [], expected_switches=1)
        self.assertEqual(result["updates"]["layouts_by_view"], {"TerminalSplitTreeAXContainer": 2})


if __name__ == "__main__":
    unittest.main()
