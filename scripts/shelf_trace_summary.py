#!/usr/bin/env python3
"""Summarize exported Shelf selection signposts and SwiftUI update counts."""

import argparse
import json
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


def read_rows(path, columns):
    """Stream rows while resolving xctrace id/ref values, including nested definitions.

    Large update exports contain downstream cause sets we do not need. Keep only
    the scalar types used by requested columns, and release each XML row at once.
    """
    references = {}
    names = []
    types = set()
    stack = []
    for event, element in ET.iterparse(path, events=("start", "end")):
        if event == "start":
            stack.append(element)
            continue
        if element.tag == "schema":
            names = [col.findtext("mnemonic") for col in element.findall("col")]
            types = {
                col.findtext("engineering-type") for col in element.findall("col")
                if col.findtext("mnemonic") in columns
            }
        elif element.tag == "row":
            for value in element.iter():
                if value.tag in types and "id" in value.attrib:
                    references[value.attrib["id"]] = value.text or value.get("fmt", "")
            row = {}
            for name, value in zip(names, element):
                if name in columns:
                    row[name] = (references[value.attrib["ref"]] if "ref" in value.attrib
                                 else value.text or value.get("fmt", ""))
            yield row
            stack[-2].remove(element)
            element.clear()
        stack.pop()


def summarize(signposts, updates, hitches, expected_switches, settle_ms=350):
    if expected_switches <= 0 or settle_ms < 0:
        raise ValueError("Expected switches must be positive and settle time must be nonnegative")
    events = [row for row in signposts if row["subsystem"] in ("com.onevcat.prowl", "com.onevcat.prowl.debug")]
    selections = [int(row["time"]) for row in events
                  if row["event-type"] == "Begin"
                  and row["name"] in ("reducer.selectRepository", "reducer.selectWorktree")]
    if len(selections) != expected_switches:
        raise ValueError(f"Expected {expected_switches} selections, recorded {len(selections)}")
    start = min(selections)
    end = max(selections) + settle_ms * 1_000_000
    calls = Counter(row["name"] for row in events
                    if start <= int(row["time"]) <= end and row["event-type"] != "End")
    by_type = Counter()
    by_description = Counter()
    layouts_by_view = Counter()
    for row in updates:
        if start <= int(row["start"]) <= end:
            by_type[row["update-type"]] += 1
            by_description[row["description"]] += 1
            if row["update-type"] == "Layout Updates":
                layouts_by_view[row.get("view-name", "unknown")] += 1
    hitch_count = 0
    hitch_ns = 0
    for row in hitches:
        hitch_start = int(row["start"])
        overlap = min(end, hitch_start + int(row["duration"])) - max(start, hitch_start)
        if overlap > 0:
            hitch_count += 1
            hitch_ns += overlap
    return {
        "switches": len(selections),
        "window_ns": [start, end],
        "signposts": dict(calls),
        "signposts_per_switch": {name: count / len(selections) for name, count in calls.items()},
        "updates": {
            "total": sum(by_type.values()),
            "by_type": dict(by_type),
            "by_description": dict(by_description.most_common()),
            "layouts_by_view": dict(layouts_by_view.most_common()),
        },
        "hitches": {
            "count": hitch_count,
            "overlap_ms": hitch_ns / 1_000_000,
            "ms_per_switch": hitch_ns / 1_000_000 / len(selections),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signposts", type=Path, required=True)
    parser.add_argument("--updates", type=Path, required=True)
    parser.add_argument("--hitches", type=Path, required=True)
    parser.add_argument("--expected-switches", type=int, required=True)
    parser.add_argument("--settle-ms", type=int, default=350)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = summarize(
            read_rows(args.signposts, {"time", "name", "event-type", "subsystem"}),
            read_rows(args.updates, {"start", "update-type", "description", "view-name"}),
            read_rows(args.hitches, {"start", "duration"}),
            args.expected_switches,
            args.settle_ms,
        )
    except (ValueError, KeyError, OSError, ET.ParseError) as error:
        parser.exit(1, f"Invalid or incomplete trace: {error}\n")
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "switches": result["switches"],
        "signposts": result["signposts"],
        "update_types": result["updates"]["by_type"],
        "hitches": result["hitches"],
        "output": str(args.output),
    }, indent=2))


if __name__ == "__main__":
    main()
