#!/usr/bin/env python3
"""
Dev tooling: static verification of the Referral System resource.

  1. every Lua file parses
  2. no unknown globals are referenced (typo catcher)
  3. every "assets/..." path used in code exists on disk
  4. client -> server event names match the server side addEvent
  5. every Arabic character used in the UI exists in assets/fonts/arabic.ttf

Run:  python3 tools/verify.py
"""
import os
import re
import sys

from luaparser import ast
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESOURCE = os.path.join(ROOT, "referral_system")

LUA_GLOBALS = set("""
_G assert collectgarbage coroutine debug dofile error gcinfo getfenv getmetatable
io ipairs load loadfile loadstring module next pairs pcall print rawequal rawget
rawlen rawset require select setfenv setmetatable tonumber tostring type unpack
xpcall string table math os package newproxy
""".split())

MTA_GLOBALS = set("""
addEvent addEventHandler removeEventHandler triggerEvent triggerServerEvent
triggerClientEvent getResourceFromName getResourceName getResourceState
getThisResource resourceRoot root localPlayer exports get setTimer killTimer
isTimer setTimer setClipboard playSound playSound3D stopSound showCursor
bindKey unbindKey isKeyBound getKeyState addCommandHandler outputDebugString
outputConsole outputChatBox debugScript createElement destroyElement isElement
getElementType getElementData setElementData getElementsByType getPlayerName
getPlayerSerial getPlayerAccount getAccountName getAccount getPlayerFromSerial
getPedOccupiedVehicleSeat getTickCount getRealTime getTimestamp getDistanceBetweenPoints3D
dbConnect dbExec dbQuery dbPoll dbFree givePlayerMoney takePlayerMoney getPlayerMoney
setPlayerMoney getPlayerTeam getPlayerWantedLevel getPlayerPing getPlayerIP
setElementPosition getElementPosition getElementDimension getElementInterior
isPedInVehicle getPedOccupiedVehicle getVehicleName getVehicleType
getPlayerCount getMaxPlayers getServerName getGameType getMapName
getFPSLimit setFPSLimit getVirtualMemory getRealDriveSectorSize
isTimer validXMLNode xmlLoadFile xmlCreateFile xmlNodeGetName
addDebugHook getCancelReason setGlitchEnabled isGlitchEnabled
toJSON fromJSON encodeString decodeString getColorFromString
md5 sha256 passwordHash passwordVerify getServerConfigSetting
setServerConfigSetting callRemote fetchRemote
""".split())

problems = []
notes = []


def iter_lua_files():
    for base, dirs, files in os.walk(RESOURCE):
        dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.join(base, name)


def collect_names(tree):
    """Return every identifier name referenced anywhere in the file."""
    names = set()

    class Visitor(ast.ASTVisitor):
        def visit_Name(self, node):  # noqa: N802
            names.add(node.id)

        def visit_Assign(self, node):  # noqa: N802
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)

        def visit_LocalAssign(self, node):  # noqa: N802
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)

        def visit_Fornum(self, node):  # noqa: N802
            names.add(node.target.id)

        def visit_Forin(self, node):  # noqa: N802
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)

        def visit_Function(self, node):  # noqa: N802
            if isinstance(node.name, ast.Name):
                names.add(node.name.id)

        def visit_LocalFunction(self, node):  # noqa: N802
            if isinstance(node.name, ast.Name):
                names.add(node.name.id)

    Visitor().visit(tree)
    return names


def main():
    all_names = set()
    per_file = {}

    # 1 + 2 : parse and collect globals
    for path in iter_lua_files():
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as fh:
            source = fh.read()
        try:
            tree = ast.parse(source)
        except Exception as exc:  # noqa: BLE001
            problems.append("%s: parse error %s" % (rel, exc))
            continue
        names = collect_names(tree)
        all_names |= names
        per_file[rel] = (names, source)

    for rel, (names, _source) in per_file.items():
        unknown = sorted(n for n in names - all_names - LUA_GLOBALS - MTA_GLOBALS)
        if unknown:
            problems.append("%s: unknown globals -> %s" % (rel, ", ".join(unknown)))

    # 3 : asset paths
    asset_re = re.compile(r'["\']((?:assets|:)[^"\']*)["\']')
    for rel, (_names, source) in per_file.items():
        for match in asset_re.findall(source):
            if not match.startswith("assets/"):
                continue
            if not os.path.exists(os.path.join(RESOURCE, match)):
                problems.append("%s: missing asset %s" % (rel, match))
            else:
                notes.append("%s -> %s" % (rel, match))

    # 4 : event wiring
    client_triggers, server_events = set(), set()
    for rel, (_names, source) in per_file.items():
        for match in re.findall(r'triggerServerEvent\(\s*(?:EV|Referral\.events)\.(\w+)', source):
            client_triggers.add(match)
        for match in re.findall(r'addEvent\(\s*(?:EV|Referral\.events)\.(\w+)', source):
            server_events.add(match)
        for match in re.findall(r'addEventHandler\(\s*(?:EV|Referral\.events)\.(\w+)', source):
            server_events.add(match)
    missing = sorted(client_triggers - server_events)
    if missing:
        problems.append("client triggers events the server never registers: %s" % ", ".join(missing))

    # 5 : arabic coverage
    font_path = os.path.join(RESOURCE, "assets", "fonts", "arabic.ttf")
    if not os.path.exists(font_path):
        problems.append("assets/fonts/arabic.ttf is missing")
    else:
        cmap = set(TTFont(font_path).getBestCmap().keys())
        arabic = set()
        for _rel, (_names, source) in per_file.items():
            arabic |= {ch for ch in source if 0x0600 <= ord(ch) <= 0x06FF
                       or ord(ch) in (0x060C, 0x061F, 0x06D4)}
        missing_glyphs = sorted(ch for ch in arabic if ord(ch) not in cmap)
        if missing_glyphs:
            problems.append("arabic.ttf is missing glyphs: %s"
                            % " ".join("%s(U+%04X)" % (c, ord(c)) for c in missing_glyphs))
        else:
            notes.append("arabic.ttf covers all %d arabic characters used" % len(arabic))

    print("== static verification ==")
    for note in notes:
        print("  note:", note)
    if problems:
        print("\n%d problem(s):" % len(problems))
        for problem in problems:
            print("  !", problem)
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
