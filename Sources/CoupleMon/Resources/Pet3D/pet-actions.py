"""Bake CoupleMon's ten actions into each generated GLB, using named articulated parts."""
import bpy
import math
from mathutils import Vector

ACTION_NAMES = ("idle", "runningRight", "runningLeft", "waving", "jumping", "failed",
                "waiting", "running", "review", "lookAround", "playStar", "hugHeart", "blowBubbles",
                "restMoon", "playBall", "paint", "playMusic", "fish", "celebrateCrown", "castSpell", "celebrate100")


def add_pet_actions(root):
    scene = bpy.context.scene
    scene.frame_set(1)
    bpy.context.view_layer.update()
    objects = [root] + list(root.children_recursive)
    head = next((obj for obj in objects if obj.name == "pet_head"), None)
    if head is None:
        head = next((obj for obj in objects if obj.type == "EMPTY" and "head" in obj.name.lower()), None)
    if head:
        head.name = "pet_head"

    # Upgrade the previously generated test otter without remodeling its face or silhouette.
    for side, suffix in [(-1, "l"), (1, "r")]:
        if bpy.data.objects.get("pet_arm_" + suffix):
            continue
        parts = []
        for obj in objects:
            if obj.type != "MESH" or not any(word in obj.name.lower() for word in
                    ("short embracing forearm", "paw holding heart", "holding paw finger crease")):
                continue
            center = sum((obj.matrix_world @ Vector(corner) for corner in obj.bound_box), Vector()) / 8
            if center.x * side > 0:
                parts.append(obj)
        forearm = next((obj for obj in parts if "forearm" in obj.name.lower()), None)
        if forearm:
            pivot = bpy.data.objects.new("pet_arm_" + suffix, None)
            bpy.context.collection.objects.link(pivot)
            pivot.parent = root
            pivot.location = root.matrix_world.inverted() @ (forearm.matrix_world.translation + Vector((0, 0, 0.16)))
            bpy.context.view_layer.update()
            for obj in parts:
                world = obj.matrix_world.copy()
                obj.parent = pivot
                obj.matrix_world = world

    joints = {"root": root}
    for side, suffix in [(-1, "l"), (1, "r")]:
        if bpy.data.objects.get("pet_leg_" + suffix):
            continue
        parts = []
        for obj in objects:
            if obj.type != "MESH" or not any(word in obj.name.lower() for word in
                    ("haunch", "rounded hind paw", "short toe crease")):
                continue
            center = sum((obj.matrix_world @ Vector(corner) for corner in obj.bound_box), Vector()) / 8
            if center.x * side > 0:
                parts.append(obj)
        haunch = next((obj for obj in parts if "haunch" in obj.name.lower()), None)
        if haunch:
            pivot = bpy.data.objects.new("pet_leg_" + suffix, None)
            bpy.context.collection.objects.link(pivot)
            pivot.parent = root
            pivot.location = root.matrix_world.inverted() @ (haunch.matrix_world.translation + Vector((0, 0, 0.13)))
            bpy.context.view_layer.update()
            for obj in parts:
                world = obj.matrix_world.copy()
                obj.parent = pivot
                obj.matrix_world = world
    for role, name in [("head", "pet_head"), ("left", "pet_arm_l"), ("right", "pet_arm_r"),
                       ("leg_l", "pet_leg_l"), ("leg_r", "pet_leg_r"), ("tail", "pet_tail")]:
        joint = bpy.data.objects.get(name)
        if joint and joint in root.children_recursive:
            joints[role] = joint
    image_rig = next((obj for obj in objects if obj.type == "ARMATURE" and obj.get("couplemon_image_rig")), None)
    if image_rig:
        for role, name in [("head", "pet_head"), ("left", "pet_arm_l"), ("right", "pet_arm_r"),
                           ("leg_l", "pet_leg_l"), ("leg_r", "pet_leg_r"), ("tail", "pet_tail")]:
            bone = image_rig.pose.bones.get(name)
            if bone:
                joints[role] = bone
    # Generated actions replace ad-hoc animations so clip names and neutral poses stay predictable.
    for obj in [root] + list(root.children_recursive):
        obj.animation_data_clear()
    base = {}
    for role, obj in joints.items():
        obj.rotation_mode = "XYZ"
        base[role] = (obj.location.copy(), obj.rotation_euler.copy(), obj.scale.copy())

    owners = {role: (image_rig if isinstance(obj, bpy.types.PoseBone) else obj) for role, obj in joints.items()}
    for name in ACTION_NAMES:
        duration = 96 if name == "celebrate100" else (72 if name == "idle" or name not in ACTION_NAMES[:10] else 48)
        for owner in set(owners.values()):
            owner.animation_data_create()
            owner.animation_data.action = None
        for role, obj in joints.items():
            for frame in range(1, duration + 1, 3):
                _key_pose(obj, role, name, frame, duration, base[role], illustrated=bool(image_rig))
            _key_pose(obj, role, name, duration, duration, base[role], illustrated=bool(image_rig))
        for owner in set(owners.values()):
            action = owner.animation_data.action
            action.name = "CoupleMon_" + name + "_" + owner.name
            track = owner.animation_data.nla_tracks.new()
            # Equal track names merge all body parts into ONE glTF clip per behavior.
            track.name = name
            strip = track.strips.new(name, 1, action)
            strip.extrapolation = "NOTHING"
            strip.blend_type = "REPLACE"
            track.mute = True
            owner.animation_data.action = None
        for role, obj in joints.items():
            obj.location, obj.rotation_euler, obj.scale = base[role]
    scene.frame_start = 1
    scene.frame_end = 72
    scene.frame_set(1)
    bpy.context.view_layer.update()
    print("COUPLEMON_ACTIONS " + ",".join(ACTION_NAMES), flush=True)


def _key_pose(obj, role, action, frame, duration, base, illustrated=False):
    t = (frame - 1) / (duration - 1)
    envelope = math.sin(math.pi * t) ** 2
    cycle = math.sin(2 * math.pi * t)
    run = math.sin(8 * math.pi * t) * envelope
    interaction = action not in ACTION_NAMES[:10]
    location, rotation, scale = (item.copy() for item in base)
    if action == "idle":
        if role == "root":
            location.z += 0.006 * cycle
        elif role == "head":
            rotation[1] += 0.025 * cycle
            rotation[2] += 0.035 * cycle
        elif role == "tail":
            rotation[2] += 0.06 * cycle
    elif role == "root":
        if action == "jumping":
            location.z += 0.22 * envelope
            scale.z *= 1 - 0.08 * math.sin(2 * math.pi * t)
        elif action.startswith("running"):
            location.z += 0.05 * abs(run)
            rotation[1] += 0.05 * run
            if action != "running":
                location.x += (0.22 if action == "runningRight" else -0.22) * envelope
                rotation[2] += (0.35 if action == "runningRight" else -0.35) * envelope
        elif action == "failed":
            rotation[0] += 0.12 * envelope
            scale.z *= 1 - 0.07 * envelope
        elif action == "waiting":
            rotation[1] += 0.04 * cycle * envelope
        elif action == "waving":
            rotation[1] += 0.04 * cycle * envelope
        elif action == "review":
            rotation[0] += 0.06 * envelope
        elif action == "lookAround":
            rotation[2] += 0.12 * cycle * envelope
        elif interaction:
            rotation[1] += 0.04 * cycle * envelope
            if action in ("playBall", "celebrate100"):
                location.z += (0.16 if action == "celebrate100" else 0.08) * abs(run)
            if action == "restMoon":
                rotation[1] += 0.14 * envelope
    elif role == "head":
        if action in ("lookAround", "waiting"):
            rotation[2] += 0.45 * cycle * envelope
        elif action in ("review", "failed"):
            rotation[0] += 0.28 * envelope
        elif action in ("waving", "jumping"):
            rotation[1] += 0.1 * cycle * envelope
        elif action.startswith("running"):
            rotation[0] += 0.04 * run
        elif interaction:
            rotation[0] += (0.22 if action in ("restMoon", "paint", "fish", "hugHeart") else -0.06) * envelope
            rotation[2] += 0.06 * cycle * envelope
    elif role in ("left", "right"):
        side = -1 if role == "left" else 1
        if action == "waving" and role == "right":
            rotation[1] -= side * (1.3 + 0.3 * math.sin(8 * math.pi * t)) * envelope
        elif action in ("jumping", "failed"):
            rotation[1] -= side * (0.45 if action == "jumping" else -0.12) * envelope
        elif action == "review":
            rotation[0] -= 0.28 * envelope
        elif action.startswith("running"):
            rotation[0] += side * 0.45 * run
        elif interaction:
            if action == "hugHeart":
                rotation[0] -= 0.25 * envelope
                rotation[1] += side * 0.28 * envelope
            elif action == "restMoon":
                rotation[1] += side * 0.15 * envelope
            elif role == "right":
                rotation[1] -= (0.75 if action in ("playStar", "castSpell", "celebrate100") else 0.25) * envelope
                rotation[0] -= 0.35 * envelope
                if action in ("paint", "playMusic", "fish", "blowBubbles"):
                    rotation[2] += 0.2 * run
    elif role in ("leg_l", "leg_r") and action.startswith("running"):
        rotation[0] += (0.5 if role == "leg_l" else -0.5) * run
    if illustrated:
        # Large 3D rotations expose a drawing's unseen side and stretch its seams.
        # Keep screen-plane gestures, with smaller yaw/nod and leg swings.
        rotation[0] = base[1][0] + (rotation[0] - base[1][0]) * 0.3
        rotation[2] = base[1][2] + (rotation[2] - base[1][2]) * 0.3
        if role in ("left", "right"):
            rotation[1] = base[1][1] + (rotation[1] - base[1][1]) * 0.45
    obj.location, obj.rotation_euler, obj.scale = location, rotation, scale
    for path in ("location", "rotation_euler", "scale"):
        obj.keyframe_insert(data_path=path, frame=frame)
