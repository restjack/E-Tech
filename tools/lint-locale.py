#!/usr/bin/env python3
"""Lint E-Tech's locale coverage.

Factorio does not fail to load on a missing locale key - it prints the raw key
in the GUI instead. So a typo, a renamed setting or a feature added without its
strings ships silently and is only caught by someone noticing
"etech-tp-sort-name" in their settings list. This catches it in CI.

Three checks:

  1. Mod settings. Every setting defined in settings.lua must have BOTH a
     [mod-setting-name] and a [mod-setting-description] entry, and no orphan
     entries may exist for settings that are gone. This one is exact - setting
     names are unambiguous.

  2. Referenced keys. Every LocalisedString literal in the Lua source whose key
     mentions "etech" must resolve to a key in locale/en/. Restricting it to our
     own namespace is what keeps base-game keys ({"gui-map-generator.aux"},
     {"time-symbol-seconds-short"}, ...) from producing noise - those are the
     game's to provide, not ours. Dynamically built keys ({"etech-name." .. n})
     cannot be checked and are skipped.

  3. Orphan keys. Bare etech-* keys defined in locale/en/ that no Lua file
     references. Keys inside prototype sections ([item-name], [entity-name],
     [technology-name], [mod-setting-name], ...) are exempt: the game resolves
     those by prototype name, so nothing in the source has to mention them.

Usage: python tools/lint-locale.py [mod-dir]
Exit code 0 = clean, 1 = problems found.
"""

import re
import sys
from pathlib import Path

# Sections whose keys the ENGINE resolves by prototype name, so no Lua file
# needs to reference them. Anything not listed here is expected to be used
# explicitly from code.
PROTOTYPE_SECTIONS = {
    "item-name", "item-description",
    "entity-name", "entity-description",
    "recipe-name", "recipe-description",
    "technology-name", "technology-description",
    "fluid-name", "fluid-description",
    "tile-name", "equipment-name",
    "mod-setting-name", "mod-setting-description",
    "tips-and-tricks-item-name", "tips-and-tricks-item-description",
    "shortcut-name", "shortcut-description",
    "controls", "controls-description",
    "description",
}

# Matches of the {"..."} shape that are not LocalisedStrings. Keep this list
# short and justified - every entry is a hole in check 2.
NOT_LOCALE = {
    # factory-mk4/layout.lua: Factorissimo's layout.upgrades entries are
    # {mod_name, remote_function} pairs, not localised strings.
    "etech-factory-mk4",
}

# A plain Lua array of prototype names opens with the same {"..." shape as a
# LocalisedString and cannot be told apart syntactically. Put this marker on
# such a line (or the line above it) to skip it.
IGNORE_MARKER = "lint-locale: ignore"


def parse_cfg(path):
    """-> (set of qualified keys, dict section -> set of keys)"""
    keys, sections = set(), {}
    section = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        qualified = f"{section}.{key}" if section else key
        keys.add(qualified)
        sections.setdefault(section, set()).add(key)
    return keys, sections


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent.parent / "E-Tech"
    locale_dir = root / "locale" / "en"
    if not locale_dir.is_dir():
        print(f"no locale directory at {locale_dir}")
        return 1

    keys, sections = set(), {}
    for cfg in sorted(locale_dir.glob("*.cfg")):
        k, s = parse_cfg(cfg)
        keys |= k
        for name, entries in s.items():
            sections.setdefault(name, set()).update(entries)

    problems = []

    # --- 1. settings coverage ------------------------------------------------
    settings_lua = root / "settings.lua"
    setting_names = set()
    if settings_lua.exists():
        setting_names = set(re.findall(r'name\s*=\s*"(etech-[a-z0-9-]+)"',
                                       settings_lua.read_text(encoding="utf-8")))
    for section in ("mod-setting-name", "mod-setting-description"):
        present = sections.get(section, set())
        for name in sorted(setting_names - present):
            problems.append(f"setting {name!r} has no [{section}] entry")
        for name in sorted(present - setting_names):
            problems.append(f"[{section}] {name!r} does not match any setting")

    # --- 2. referenced keys --------------------------------------------------
    # A LocalisedString literal: {"key"} or {"key", param, ...}. Keys built by
    # concatenation ({"etech-name." .. name}) end at a `..` and cannot be
    # resolved statically - record their prefix instead, so check 3 does not
    # then report every key under that prefix as an orphan.
    lua_files = [p for p in root.rglob("*.lua") if "releases" not in p.parts]
    referenced = {}
    dynamic_prefixes = set()
    quoted_anywhere = set()
    literal = re.compile(r'\{\s*"([A-Za-z0-9_.\-]+)"(\s*\.\.)?')
    for path in lua_files:
        text = path.read_text(encoding="utf-8", errors="replace")
        quoted_anywhere.update(re.findall(r'"([A-Za-z0-9_.\-]+)"', text))
        lines = text.splitlines()
        for m in literal.finditer(text):
            key, concatenated = m.group(1), m.group(2)
            if "etech" not in key.lower() or key in NOT_LOCALE:
                continue
            if concatenated:
                dynamic_prefixes.add(key)
                continue
            line_no = text.count("\n", 0, m.start())
            context = "\n".join(lines[max(0, line_no - 1):line_no + 1])
            if IGNORE_MARKER in context:
                continue
            referenced.setdefault(key, path)
    for key, path in sorted(referenced.items()):
        if key not in keys:
            rel = path.relative_to(root.parent)
            problems.append(f"{rel}: references missing locale key {key!r}")

    def is_used(qualified, bare):
        # Any mention as a quoted string counts - some call sites build the
        # LocalisedString indirectly (copy-paste-modules picks its key with an
        # inline conditional), and for "is this key dead?" that is the right
        # question to ask.
        if qualified in referenced or qualified in quoted_anywhere or bare in quoted_anywhere:
            return True
        return any(qualified.startswith(prefix) for prefix in dynamic_prefixes)

    # --- 3. orphan keys ------------------------------------------------------
    for key in sorted(sections.get(None, set())):
        if "etech" in key.lower() and not is_used(key, key):
            problems.append(f"locale key {key!r} is defined but never referenced")
    for section in sorted(s for s in sections if s is not None):
        if section in PROTOTYPE_SECTIONS:
            continue
        for key in sorted(sections[section]):
            qualified = f"{section}.{key}"
            if "etech" in qualified.lower() and not is_used(qualified, key):
                problems.append(f"locale key {qualified!r} is defined but never referenced")

    if problems:
        print(f"{locale_dir}: {len(problems)} problem(s)")
        for p in problems:
            print("  " + p)
        return 1
    print(f"{locale_dir}: locale OK "
          f"({len(keys)} keys, {len(setting_names)} settings, {len(referenced)} references)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
