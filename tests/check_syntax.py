"""Compiles every addon Lua file with real Lua 5.1, the same compiler WoW uses.

    python tests/check_syntax.py          # the working copy
    python tests/check_syntax.py HEAD     # a committed version (any git revision)

A pure-Python Lua parser once accepted a string with a raw line break in it; Lua itself rejects that, so this is the
check to trust.
"""
import glob
import os
import subprocess
import sys
from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime()
compile_error = lua.eval("function(src, name) local f, err = loadstring(src, name) return err end")


def sources(rev):
    for path in sorted(glob.glob(os.path.join(ROOT, "EasyFish", "*.lua"))):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rev:
            src = subprocess.run(["git", "-C", ROOT, "show", f"{rev}:{rel}"], capture_output=True,
                                 encoding="utf-8").stdout
        else:
            with open(path, encoding="utf-8") as f:
                src = f.read()
        yield rel, src


def main():
    rev = sys.argv[1] if len(sys.argv) > 1 else None
    broken = 0
    for rel, src in sources(rev):
        err = compile_error(src, rel)
        if err:
            print("SYNTAX ERROR", err)
            broken += 1
    label = f"at {rev}" if rev else "in the working copy"
    print(f"all addon files compile under Lua 5.1 {label}" if not broken else f"{broken} broken file(s) {label}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
