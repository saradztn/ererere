#!/usr/bin/env python3
"""
Dev tooling: syntax check every Lua file of the Referral System
resource (MTA uses Lua 5.1, luaparser parses a superset, so a clean
parse here means the file is syntactically valid Lua).

Run:  python3 tools/check_lua.py
"""
import os
import sys

from luaparser import ast

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCE = os.path.join(os.path.dirname(HERE), "referral_system")


def iter_lua_files():
    for root, dirs, files in os.walk(RESOURCE):
        dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.join(root, name)


def main():
    failures = 0
    checked = 0
    for path in iter_lua_files():
        checked += 1
        rel = os.path.relpath(path, os.path.dirname(RESOURCE))
        try:
            with open(path, "r", encoding="utf-8") as fh:
                source = fh.read()
            ast.parse(source)
            print("OK    %s (%d lines)" % (rel, source.count("\n") + 1))
        except Exception as exc:  # noqa: BLE001 - report anything
            failures += 1
            print("FAIL  %s -> %s" % (rel, exc))
    print("\n%d files checked, %d failed" % (checked, failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
