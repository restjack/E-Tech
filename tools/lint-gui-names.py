#!/usr/bin/env python3
"""Reject GUI element names that collide with LuaGuiElement's own members.

WHY THIS EXISTS. Naming a GUI element after a property LuaGuiElement already
has is not a warning - the engine refuses to create the element at all:

    Invalid name "tabs": LuaGuiElement contains a property or method with the
    same name.

which surfaces as a non-recoverable mod error the moment a player opens the
window. E-Tech shipped exactly that in 0.24.1 with a tabbed-pane named "tabs",
and nothing caught it: verify.ps1 only proves the mod loads, and the runtime
harness runs under --benchmark, which has no player and therefore cannot open a
relative GUI at all. This is the cheap static stand-in for the test that cannot
be written.

The reserved list is read from the game's own runtime-api.json rather than
hardcoded, so it stays correct across game versions.

Usage:  python tools/lint-gui-names.py [path-to-runtime-api.json]
"""

import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "E-Tech")
DEFAULT_API = (
    r"C:\Program Files (x86)\Steam\steamapps\common\Factorio\doc-html\runtime-api.json"
)

# Element creation in this codebase is always `<parent>.add { ... }`; entities go
# through create_entity, which takes a prototype name and is not our concern.
ADD_CALL = re.compile(r"\.add\s*\{(.*?)\}", re.S)
NAME_FIELD = re.compile(r'\bname\s*=\s*"([\w\-]+)"')


def reserved_names(api_path):
    with open(api_path, encoding="utf-8") as handle:
        api = json.load(handle)
    for cls in api["classes"]:
        if cls["name"] != "LuaGuiElement":
            continue
        names = {a["name"] for a in cls.get("attributes", [])}
        names |= {m["name"] for m in cls.get("methods", [])}
        return names
    raise SystemExit("LuaGuiElement not found in runtime-api.json")


def main():
    api_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_API
    if not os.path.exists(api_path):
        print("runtime-api.json not found - skipped (pass its path as an argument)")
        return 0

    reserved = reserved_names(api_path)
    problems = []
    for root, _dirs, files in os.walk(MOD):
        for filename in files:
            if not filename.endswith(".lua"):
                continue
            path = os.path.join(root, filename)
            with open(path, encoding="utf-8") as handle:
                source = handle.read()
            for call in ADD_CALL.finditer(source):
                match = NAME_FIELD.search(call.group(1))
                if not match:
                    continue
                name = match.group(1)
                if name in reserved:
                    line = source.count("\n", 0, call.start() + match.start()) + 1
                    problems.append(
                        "%s:%d: GUI element named %r collides with LuaGuiElement.%s"
                        % (os.path.relpath(path, REPO), line, name, name)
                    )

    for problem in problems:
        print("  " + problem)
    if problems:
        print("GUI name lint: %d collision(s) - the engine refuses these outright"
              % len(problems))
        return 1
    print("GUI name lint OK (%d reserved names checked)" % len(reserved))
    return 0


if __name__ == "__main__":
    sys.exit(main())
