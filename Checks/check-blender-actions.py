#!/usr/bin/env python3
"""Check real Blender exports across versions: pass one or more Blender executables."""
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
resources = root / "Sources/CoupleMon/Resources/Pet3D"
fixture = """
for name, location in [('pet_head', (0, 0, 1)), ('pet_arm_r', (0.6, 0, 0.5))]:
    joint = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(joint)
    joint.parent = root
    joint.location = location
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.3)
    mesh = bpy.context.object
    mesh.parent = joint
    mesh.location = (0, 0, 0)
"""

if len(sys.argv) < 2:
    sys.exit("Usage: check-blender-actions.py /path/to/Blender [...]")
for executable in sys.argv[1:]:
    with tempfile.TemporaryDirectory(prefix="couplemon-actions-") as temporary:
        workspace = pathlib.Path(temporary)
        for name in ["build-model.py", "pet-actions.py"]:
            shutil.copyfile(resources / name, workspace / name)
        (workspace / "character.py").write_text(fixture)
        result = subprocess.run([str(pathlib.Path(executable).resolve()), "--background", "--factory-startup",
                                 "--threads", "2", "--python-exit-code", "1", "--python",
                                 str(workspace / "build-model.py")], capture_output=True, text=True, timeout=180)
        assert result.returncode == 0, result.stdout + result.stderr
        data = (workspace / "model.glb").read_bytes()
        length = struct.unpack_from("<I", data, 12)[0]
        gltf = json.loads(data[20:20 + length])
        clips = {clip["name"]: clip for clip in gltf["animations"]}
        assert len(clips) == 21, list(clips)
        for name in ["idle", "runningLeft", "runningRight", "waving", "jumping", "celebrate100"]:
            assert name in clips, (name, list(clips))
        binary = data[28 + length:]

        def values(accessor_index):
            accessor = gltf["accessors"][accessor_index]
            view = gltf["bufferViews"][accessor["bufferView"]]
            assert accessor["componentType"] == 5126
            components = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accessor["type"]]
            offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            stride = view.get("byteStride", components * 4)
            return [struct.unpack_from("<" + "f" * components, binary, offset + i * stride)
                    for i in range(accessor["count"])]

        # One behavior must animate multiple articulated parts, not just be renamed.
        clip = clips["waving"]
        moving = set()
        for channel in clip["channels"]:
            sampler = clip["samplers"][channel["sampler"]]
            frames = values(sampler["output"])
            if len(set(frames)) > 1:
                moving.add(gltf["nodes"][channel["target"]["node"]]["name"])
        assert {"pet_root", "pet_head", "pet_arm_r"}.issubset(moving), moving
        print(f"PASS: {executable}: 21 clips; waving moves root, head and arm together", flush=True)
