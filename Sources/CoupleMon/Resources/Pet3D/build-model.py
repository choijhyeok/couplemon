"""Host wrapper: generated scene -> validated self-contained GLB and review artifacts."""
import bpy
import math
import os
from mathutils import Vector

workspace = os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
root = bpy.data.objects.new("pet_root", None)
bpy.context.collection.objects.link(root)
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 72
scene.render.fps = 24
print("COUPLEMON_STAGE modeling", flush=True)
with open(os.path.join(workspace, "character.py"), encoding="utf-8") as script_file:
    script = script_file.read()
exec(compile(script, "character.py", "exec"), {
    "__name__": "__character__", "bpy": bpy, "math": math, "Vector": Vector, "root": root,
})
scene.frame_set(1)
with open(os.path.join(workspace, "pet-actions.py"), encoding="utf-8") as actions_file:
    action_globals = {}
    exec(compile(actions_file.read(), "pet-actions.py", "exec"), action_globals)
action_globals["add_pet_actions"](root)
meshes = [obj for obj in scene.objects if obj.type == "MESH"]
if not meshes:
    raise RuntimeError("No character meshes generated")
for obj in meshes:
    if obj.parent is None:
        obj.parent = root
    obj.hide_render = False
bpy.context.view_layer.update()
triangles = sum(len(obj.data.loop_triangles) for obj in meshes)
# Export contact points with the articulated parts; the app uses them to align
# differently proportioned partners. Older GLBs use bounds-based fallbacks.
for anchor_name, joint_name, words in [
    ("pet_anchor_face", "pet_head", ("mouth", "nose")),
    ("pet_anchor_hand_l", "pet_arm_l", ("paw", "hand")),
    ("pet_anchor_hand_r", "pet_arm_r", ("paw", "hand")),
]:
    if bpy.data.objects.get(anchor_name):
        continue
    joint = bpy.data.objects.get(joint_name)
    if joint is None or joint not in root.children_recursive:
        continue
    candidates = [obj for obj in joint.children_recursive if obj.type == "MESH"]
    preferred = [obj for obj in candidates if any(word in obj.name.lower() for word in words)]
    coords = [obj.matrix_world @ Vector(corner) for obj in (preferred or candidates) for corner in obj.bound_box]
    if not coords:
        continue
    lower = Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    upper = Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    point = (lower + upper) / 2
    if anchor_name == "pet_anchor_face":
        point.y = lower.y
    anchor = bpy.data.objects.new(anchor_name, None)
    bpy.context.collection.objects.link(anchor)
    anchor.parent = joint
    anchor.location = joint.matrix_world.inverted() @ point
bpy.context.view_layer.update()
# Mesh loop triangles are lazily populated.
for obj in meshes:
    obj.data.calc_loop_triangles()
triangles = sum(len(obj.data.loop_triangles) for obj in meshes)
if triangles > 80000:
    raise RuntimeError(f"Character has {triangles} triangles; simplify below 80000")
print(f"COUPLEMON_STAGE export ({triangles} triangles)", flush=True)
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in root.children_recursive:
    if obj.type not in {"CAMERA", "LIGHT"}:
        obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=os.path.join(workspace, "model.glb"), export_format="GLB",
    use_selection=True, export_animations=True, export_yup=True, export_animation_mode="ACTIONS",
    export_draco_mesh_compression_enable=False,
)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(workspace, "source.blend"))
# Review image never enters the exported character model.
coords = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
lower = Vector(tuple(min(v[i] for v in coords) for i in range(3)))
upper = Vector(tuple(max(v[i] for v in coords) for i in range(3)))
center = (lower + upper) / 2
extent = max(upper - lower)
if not math.isfinite(extent) or extent <= 0:
    raise RuntimeError("Character bounds are invalid")
bpy.ops.object.camera_add(location=center + Vector((0, -extent * 2.5, extent * 0.12)))
camera = bpy.context.object
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = extent * 1.2
scene.camera = camera
for offset, energy, size in [((2, -3, 4), 500, 5), ((-3, -1, 2), 250, 4)]:
    bpy.ops.object.light_add(type="AREA", location=center + Vector(offset) * extent)
    lamp = bpy.context.object
    lamp.data.energy = energy
    lamp.data.shape = "DISK"
    lamp.data.size = size
    lamp.rotation_euler = (center - lamp.location).to_track_quat("-Z", "Y").to_euler()
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 12
scene.render.resolution_x = 384
scene.render.resolution_y = 384
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = os.path.join(workspace, "preview.png")
print("COUPLEMON_STAGE preview", flush=True)
bpy.ops.render.render(write_still=True)
print("COUPLEMON_STAGE complete", flush=True)
