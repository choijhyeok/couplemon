#!/usr/bin/env python3
"""Real Blender image-rig/export check; no AI account or application data used.

python3 Checks/check-image-rig.py /path/to/Blender
python3 Checks/check-image-rig.py /path/to/python-with-bpy --bpy
Artifacts: dist/image-rig-review/{model.glb,source.blend,preview.png}
"""
import json
import pathlib
import shutil
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def inside_blender():
    import bpy
    resources = ROOT / "Sources/CoupleMon/Resources/Pet3D"
    workspace = ROOT / "dist/image-rig-review"
    workspace.mkdir(parents=True, exist_ok=True)
    for name in ("build-model.py", "image-rig.py", "pet-actions.py"):
        shutil.copy2(resources / name, workspace / name)
    texture = ROOT / "Sources/CoupleMon/Resources/Emoticons/otter.png"
    shutil.copy2(texture, workspace / "texture.png")
    (workspace / "character.py").write_text('''image_character(
        head=(0.49,0.26,0.22,0.19), neck=(0.49,0.44), face=(0.47,0.32), limbs=[
          {"name":"pet_arm_l","pivot":(0.33,0.45),"tip":(0.36,0.52),"radius":0.065},
          {"name":"pet_arm_r","pivot":(0.63,0.46),"tip":(0.57,0.52),"radius":0.065},
          {"name":"pet_leg_l","pivot":(0.37,0.74),"tip":(0.39,0.86),"radius":0.06},
          {"name":"pet_leg_r","pivot":(0.55,0.74),"tip":(0.54,0.86),"radius":0.06},
          {"name":"pet_ear_l","pivot":(0.33,0.18),"tip":(0.32,0.13),"radius":0.025},
          {"name":"pet_ear_r","pivot":(0.65,0.22),"tip":(0.67,0.19),"radius":0.025},
          {"name":"pet_tail","pivot":(0.62,0.79),"tip":(0.82,0.82),"radius":0.04}],
        eyes=[(0.35,0.207,0.422,0.276), (0.533,0.239,0.596,0.306)])''')
    wrapper = workspace / "build-model.py"
    exec(compile(wrapper.read_text(), str(wrapper), "exec"), {"__file__": str(wrapper)})
    obj = bpy.data.objects["original_illustration"]
    assert len(obj.data.vertices) > 1000, "Need a deformable grid"
    assert all(abs(sum(g.weight for g in v.groups) - 1) < 1e-5 for v in obj.data.vertices), "Skin weights must sum to 1"
    assert bpy.data.objects["pet_root"]["couplemon_render_mode"] == "illustrated"
    rig = bpy.data.objects["pet_image_rig"]
    anchor = bpy.data.objects["pet_anchor_face"]
    neutral = anchor.matrix_world.translation.copy()
    rig.pose.bones["pet_head"].rotation_euler.x = 0.2
    bpy.context.view_layer.update()
    assert (anchor.matrix_world.translation - neutral).length > 0.001, "Contact anchor must follow the head bone"
    rig.pose.bones["pet_head"].rotation_euler.x = 0
    # Invalid anchors fail explicitly instead of generating corrupt geometry.
    namespace = {}
    exec(compile((resources / "image-rig.py").read_text(), "image-rig.py", "exec"), namespace)
    for head in [(0.5, 0.3, 0, 0.2), (float("nan"), 0.3, 0.2, 0.2)]:
        try:
            namespace["build_image_character"](bpy.data.objects["pet_root"], str(workspace), head, (0.5, 0.5), (0.5, 0.3), [])
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid anchors accepted")

    data = (workspace / "model.glb").read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    model = json.loads(data[20:20 + length])
    expected = set()
    exec((resources / "pet-actions.py").read_text(), actions := {})
    expected.update(actions["ACTION_NAMES"])
    assert {a["name"] for a in model["animations"]} == expected, "All 21 merged clips required"
    assert len(model["skins"]) == 1
    material = model["materials"][0]
    assert "KHR_materials_unlit" in material.get("extensions", {}), "Source palette must be unlit"
    assert material.get("alphaMode") == "BLEND", "Source alpha must survive glTF export"
    assert material.get("doubleSided"), "Small turns must not cull the illustration"
    for action in model["animations"]:
        targets = {model["nodes"][c["target"]["node"]]["name"] for c in action["channels"]}
        assert {"pet_root", "pet_head", "pet_arm_r"}.issubset(targets), (action["name"], targets)
    binary = 20 + length + 8
    images = []
    for image in model["images"]:
        assert "uri" not in image, "Texture must be embedded"
        view = model["bufferViews"][image["bufferView"]]
        start = binary + view.get("byteOffset", 0)
        images.append(data[start:start + view["byteLength"]])
    assert texture.read_bytes() in images, "Original eye artwork bytes must be preserved"
    eye_nodes = [n for n in model["nodes"] if n.get("extras", {}).get("couplemon_eye_role")]
    assert len(eye_nodes) == 8, "Two eyes need original patches, two lids and closed strokes"
    for node in eye_nodes:
        mesh = model["meshes"][node["mesh"]]
        assert mesh["primitives"][0].get("targets"), "Eye parts need morph targets"
        eye_material = model["materials"][mesh["primitives"][0]["material"]]
        assert eye_material.get("alphaMode", "OPAQUE") == "OPAQUE", "Lids must cover the iris without transparency sorting artifacts"
    assert {"pet_ear_l", "pet_ear_r", "pet_tail"}.issubset({n["name"] for n in model["nodes"]})
    print("PASS: original eye PNG bytes/alpha, curved mesh, normalized skin, anchors, ears/tail, eye/lid morphs, 21 GLB clips")
    print("Review artifacts:", workspace)


if "--inside-blender" in sys.argv:
    inside_blender()
else:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = [sys.argv[1]]
    if "--bpy" in sys.argv:
        command += [str(pathlib.Path(__file__).resolve()), "--inside-blender"]
    else:
        command += ["--background", "--factory-startup", "--threads", "2", "--python-exit-code", "1",
                    "--python", str(pathlib.Path(__file__).resolve()), "--", "--inside-blender"]
    subprocess.run(command, check=True, timeout=300)
