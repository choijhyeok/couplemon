#!/usr/bin/env python3
"""Verify 3D library, native renderer and real local Blender export in private storage.

Usage: python3 Checks/check-3d.py /path/to/Blender [--live] [--model /path/to/model.glb]
--live additionally uses the signed-in Codex CLI for one image-to-3D generation.
"""
import pathlib
import plistlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    sys.exit("Pass Blender.app/Contents/MacOS/Blender (use --live for a real Codex request)")
subprocess.run(["swift", "build", "-Xswiftc", "-warnings-as-errors"], cwd=root, check=True)
build = root / ".build/debug"
objects = [p for p in (build / "CoupleMon.product/Objects.LinkFileList").read_text().splitlines()
           if pathlib.Path(p).name != "CoupleMonApp.swift.o"]
executable = root / ".build/pet3d-check"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(build), str(root / "Checks/Pet3DCheck.swift"),
                *objects, "-o", str(executable)], cwd=root, check=True)
app = root / ".build/Pet3DCheck.app/Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
native = app / "MacOS/pet3d-check"
shutil.copy2(executable, native)
shutil.copytree(build / "CoupleMon_CoupleMon.bundle", app / "Resources/CoupleMon_CoupleMon.bundle", dirs_exist_ok=True)
(app / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "com.couplemon.pet3d-check", "CFBundleName": "Pet3DCheck",
    "CFBundleExecutable": "pet3d-check", "CFBundlePackageType": "APPL",
    "LSUIElement": True, "LSMinimumSystemVersion": "14.0",
}))
subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
subprocess.run([str(native), str(root), *sys.argv[1:]], cwd=root, check=True, timeout=1200)
