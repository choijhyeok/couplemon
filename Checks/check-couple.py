#!/usr/bin/env python3
"""Run two native 3D views through a local WebSocket server. Usage: check-couple.py model.glb"""
import importlib.util
import json
import pathlib
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import threading

sys.dont_write_bytecode = True
root = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("local_realtime", root / "Checks/check-realtime.py")
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)
subprocess.run(["swift", "build", "-Xswiftc", "-warnings-as-errors"], cwd=root, check=True)
build = root / ".build/debug"
objects = [p for p in (build / "CoupleMon.product/Objects.LinkFileList").read_text().splitlines()
           if pathlib.Path(p).name != "CoupleMonApp.swift.o"]
app = root / ".build/CouplePetCheck.app/Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
executable = app / "MacOS/couple-check"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(build), "-I", str(build / "Modules"), str(root / "Checks/CouplePetCheck.swift"), *objects, "-o", str(executable)], check=True)
(app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.couplemon.couple-check", "CFBundleExecutable": "couple-check", "CFBundlePackageType": "APPL", "LSUIElement": True}))
shutil.copytree(build / "CoupleMon_CoupleMon.bundle", app / "Resources/CoupleMon_CoupleMon.bundle", dirs_exist_ok=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
server = server_module.http.server.ThreadingHTTPServer(("127.0.0.1", 0), server_module.WebSocket)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix="couple-fixture-") as folder:
        original = pathlib.Path(sys.argv[1]).resolve()
        data = original.read_bytes()
        length = struct.unpack_from("<I", data, 12)[0]
        content = json.loads(data[20:20 + length])
        # Deliberately different proportions and hash to test partner identity and alignment.
        index = content["scenes"][content.get("scene", 0)]["nodes"][0]
        content["nodes"][index]["scale"] = [0.85, 1.12, 0.85]
        encoded = json.dumps(content).encode()
        encoded += b" " * (-len(encoded) % 4)
        tail = data[20 + length:]
        partner = pathlib.Path(folder) / "partner.glb"
        partner.write_bytes(struct.pack("<5I", 0x46546c67, 2, 20 + len(encoded) + len(tail), len(encoded), 0x4e4f534a) + encoded + tail)
        subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}/realtime", str(original), str(partner), str(root / "dist/together-review")], cwd=root, check=True, timeout=150)
finally:
    server.shutdown()
    server.server_close()
