#!/usr/bin/env python3
"""Check private-directory pet switching and native drawing gestures. Optional args: pet folders."""
import pathlib
import plistlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "-Xswiftc", "-warnings-as-errors"], cwd=root, check=True)
build = root / ".build/debug"
objects = [p for p in (build / "CoupleMon.product/Objects.LinkFileList").read_text().splitlines()
           if pathlib.Path(p).name != "CoupleMonApp.swift.o"]
executable = root / ".build/pet-interaction-check"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(build), str(root / "Checks/PetInteractionCheck.swift"),
                *objects, "-o", str(executable)], cwd=root, check=True)
app = root / ".build/PetInteractionCheck.app/Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
native_executable = app / "MacOS/pet-interaction-check"
shutil.copy2(executable, native_executable)
(app / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "com.couplemon.pet-interaction-check", "CFBundleName": "PetInteractionCheck",
    "CFBundleExecutable": "pet-interaction-check", "CFBundlePackageType": "APPL",
    "LSUIElement": True, "LSMinimumSystemVersion": "14.0",
}))
subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
subprocess.run([str(native_executable), str(root / "Resources/DefaultPet"), str(root / "dist/pet-interaction-review"),
                *sys.argv[1:]], cwd=root, check=True, timeout=40)
