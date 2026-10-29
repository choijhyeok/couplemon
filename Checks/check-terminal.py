#!/usr/bin/env python3
"""Check the native terminal-mode window without connecting to the user's Supabase room."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "-Xswiftc", "-warnings-as-errors"], cwd=root, check=True)
build = root / ".build/debug"
objects = [p for p in (build / "CoupleMon.product/Objects.LinkFileList").read_text().splitlines()
           if pathlib.Path(p).name != "CoupleMonApp.swift.o"]
executable = root / ".build/terminal-window-check"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(build), str(root / "Checks/TerminalWindowCheck.swift"),
                *objects, "-o", str(executable)], cwd=root, check=True)
subprocess.run([str(executable), str(root / "dist/terminal-review")], cwd=root, check=True, timeout=30)
