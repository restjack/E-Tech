#!/usr/bin/env python3
"""Lint E-Tech/changelog.txt against Factorio's strict changelog format.

Rules enforced (https://lua-api.factorio.com/latest/auxiliary/changelog-format.html):
  - separator lines are EXACTLY 99 dashes
  - version lines: "Version: x.y.z"
  - date lines: "Date: ..." (free-form content)
  - category lines: 2 spaces + recognized name + ":"
  - entry lines: 4 spaces + "- "
  - continuation lines: exactly 6 spaces + text
  - no tabs, no trailing whitespace

Also cross-checks the newest entry's version against info.json (only when the
changelog sits next to one).

Usage: python tools/lint-changelog.py [path-to-changelog]
Exit code 0 = clean, 1 = problems found.
"""

import json
import re
import sys
from pathlib import Path

CATEGORIES = {
    "Major Features", "Features", "Minor Features", "Graphics", "Sounds",
    "Optimizations", "Balancing", "Combat Balancing", "Circuit Network",
    "Changes", "Bugfixes", "Modding", "Scripting", "Gui", "Control",
    "Translation", "Debug", "Ease of use", "Info", "Locale",
}

def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent.parent / "E-Tech" / "changelog.txt"
    problems = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines, 1):
        if "\t" in line:
            problems.append(f"{i}: tab character")
        if line != line.rstrip():
            problems.append(f"{i}: trailing whitespace")
        if line.startswith("---"):
            if line != "-" * 99:
                problems.append(f"{i}: separator is {len(line)} dashes, must be exactly 99")
        elif line.startswith("Version:"):
            if not re.fullmatch(r"Version: \d+\.\d+\.\d+", line):
                problems.append(f"{i}: bad version line: {line!r}")
        elif line.startswith("Date:"):
            pass
        elif re.fullmatch(r"  [A-Za-z ]+:", line):
            # Arbitrary category names are legal (only the known ones are
            # localized by the game) - so unknown ones are informational.
            cat = line.strip().rstrip(":")
            if cat not in CATEGORIES:
                print(f"  note {i}: non-standard category {cat!r} (legal, but unlocalized)")
        elif line.startswith("    - "):
            pass
        elif line.startswith("      ") and line.strip():
            if line.startswith("       "):
                problems.append(f"{i}: continuation must be exactly 6 spaces")
        elif line.strip() == "":
            pass
        else:
            problems.append(f"{i}: unrecognized line shape: {line[:60]!r}")

    # The newest changelog entry must match info.json. Shipping a build whose
    # changelog has no entry for its own version is the easiest release mistake
    # to make and the easiest to catch. Only checked when linting the mod's own
    # changelog, not an arbitrary file passed on the command line.
    info_path = path.parent / "info.json"
    if info_path.exists():
        info_version = json.loads(info_path.read_text(encoding="utf-8"))["version"]
        top = next((l[len("Version: "):].strip()
                    for l in lines if l.startswith("Version: ")), None)
        if top is None:
            problems.append("no Version: line found at all")
        elif top != info_version:
            problems.append(
                f"newest changelog entry is {top} but info.json says {info_version}"
                " - bump one of them before building")

    if problems:
        print(f"{path}: {len(problems)} problem(s)")
        for p in problems:
            print("  " + p)
        return 1
    print(f"{path}: changelog format OK ({len(lines)} lines)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
