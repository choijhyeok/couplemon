"""Original-pixel 2.5D rig: curved UV grid with continuous, normalized skin weights.

Inspired by LivLiv's head paraboloid / anchor-driven deformation; independently
implemented for Blender/glTF. No LivLiv code, characters or service is bundled.
"""
import math
import os
from array import array

import bpy
from mathutils import Vector


def _point(value):
    if len(value) != 2 or not all(math.isfinite(v) and 0 <= v <= 1 for v in value):
        raise ValueError("Image anchors must be finite normalized (x,y) coordinates")
    return tuple(value)


def _smooth(value):
    t = max(0.0, min(1.0, value))
    return t * t * (3 - 2 * t)


def build_image_character(root, workspace, head, neck, face, limbs, eyes=None):
    if len(head) != 4:
        raise ValueError("Head needs cx, cy, rx, ry")
    cx, cy = _point(head[:2])
    rx, ry = head[2:]
    if not all(math.isfinite(v) and 0 < v <= 1 for v in (rx, ry)):
        raise ValueError("Head radii must be positive and at most 1")
    neck, face = _point(neck), _point(face)
    eyes = eyes or []
    if len(eyes) > 2:
        raise ValueError("At most two visible eyes are supported")
    for eye in eyes:
        if len(eye) != 4:
            raise ValueError("Eye box needs x0,y0,x1,y1")
        x0, y0 = _point(eye[:2])
        x1, y1 = _point(eye[2:])
        if not (0.004 <= x1 - x0 <= rx and 0.004 <= y1 - y0 <= ry):
            raise ValueError("Eye boxes must be small, positive and inside the face")
        if not (cx - rx <= x0 < x1 <= cx + rx and cy - ry <= y0 < y1 <= cy + ry):
            raise ValueError("Eye boxes must lie inside the head")
    allowed = {"pet_arm_l", "pet_arm_r", "pet_leg_l", "pet_leg_r", "pet_tail", "pet_ear_l", "pet_ear_r"}
    if len(limbs) > len(allowed):
        raise ValueError("Too many image limbs")
    seen = set()
    for limb in limbs:
        name = limb["name"]
        if name not in allowed or name in seen:
            raise ValueError("Invalid or duplicate image limb")
        seen.add(name)
        _point(limb["pivot"])
        _point(limb["tip"])
        radius = limb["radius"]
        if not math.isfinite(radius) or not 0 < radius <= 0.3:
            raise ValueError("Limb radius must be in (0,0.3]")
        if math.dist(limb["pivot"], limb["tip"]) < 0.01:
            raise ValueError("Limb pivot and tip must be distinct")

    image = bpy.data.images.load(os.path.join(workspace, "texture.png"), check_existing=False)
    image.colorspace_settings.name = "sRGB"
    image.pack()
    width, height = image.size
    pixels = array("f", [0.0]) * (width * height * 4)
    image.pixels.foreach_get(pixels)
    # Blender pixels start at the bottom; anchors start at the top.
    xmin, xmax, ymin, ymax = width, -1, height, -1
    for py in range(height):
        for px in range(width):
            if pixels[(py * width + px) * 4 + 3] > 0.02:
                xmin, xmax = min(xmin, px), max(xmax, px)
                ymin, ymax = min(ymin, py), max(ymax, py)
    if xmax <= xmin or ymax <= ymin:
        raise ValueError("Reference texture has no visible character")
    x0, x1 = max(0, xmin - 1) / width, min(width, xmax + 2) / width
    y0, y1 = 1 - min(height, ymax + 2) / height, 1 - max(0, ymin - 1) / height
    scale = 2 / ((y1 - y0) * height)
    aspect = width / height

    def position(x, y):
        # Paraboloid depth fades continuously at the head outline.
        r2 = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
        head_depth = 0.11 * max(0, 1 - r2)
        body_depth = 0.025 * max(0, 1 - ((x - (x0 + x1) / 2) / ((x1 - x0) / 2)) ** 2)
        return Vector(((x - (x0 + x1) / 2) * width * scale,
                       -body_depth - head_depth, (y1 - y) * height * scale))

    cols = max(8, min(128, round(96 * (x1 - x0) * width / ((y1 - y0) * height))))
    rows = 96
    vertices, uvs, weights = [], [], []
    for row in range(rows + 1):
        y = y0 + (y1 - y0) * row / rows
        for col in range(cols + 1):
            x = x0 + (x1 - x0) * col / cols
            vertices.append(position(x, y))
            uvs.append((x, 1 - y))
            # A shared transition band avoids a cut seam at the neck.
            head_weight = _smooth((neck[1] + ry * 0.12 - y) / max(ry * 0.5, 0.01))
            values = {"pet_head": head_weight}
            for limb in limbs:
                ax, ay = limb["pivot"]
                bx, by = limb["tip"]
                dx, dy = (bx - ax) * aspect, by - ay
                length2 = dx * dx + dy * dy
                t = ((x - ax) * aspect * dx + (y - ay) * dy) / length2
                projected = max(0, min(1, t))
                distance = math.hypot((x - ax) * aspect - projected * dx, y - ay - projected * dy)
                radius = limb["radius"] * aspect
                weight = _smooth((radius - distance) / max(radius * 0.45, 0.001)) * _smooth(t / 0.4)
                if limb["name"].startswith("pet_ear_"):
                    values[limb["name"]] = weight * values["pet_head"]
                    values["pet_head"] *= 1 - weight
                else:
                    values[limb["name"]] = weight * (1 - head_weight)
            values["pet_body"] = max(0, 1 - sum(values.values()))
            total = sum(values.values())
            weights.append({name: value / total for name, value in values.items() if value > 0})
    faces = []
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            # Winding points toward -Y, the front in the Blender contract.
            faces.extend(((a, a + cols + 1, a + 1), (a + 1, a + cols + 1, a + cols + 2)))
    mesh = bpy.data.meshes.new("original_pixel_grid")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    obj = bpy.data.objects.new("original_illustration", mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    for polygon in mesh.polygons:
        polygon.use_smooth = True

    # The unlit shader retains the source palette regardless of viewer lighting.
    material = bpy.data.materials.new("Original illustration · unlit")
    material.use_nodes = True
    material.use_backface_culling = False
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    else:
        material.blend_method = "BLEND"
    nodes = material.node_tree.nodes
    nodes.clear()
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    output = nodes.new("ShaderNodeOutputMaterial")
    links = material.node_tree.links
    links.new(texture.outputs["Alpha"], mix.inputs[0])
    links.new(transparent.outputs[0], mix.inputs[1])
    # Color -> shader is Blender's implicit emission and the exporter's unlit pattern.
    links.new(texture.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])
    mesh.materials.append(material)

    armature = bpy.data.armatures.new("image_deformation")
    rig = bpy.data.objects.new("pet_image_rig", armature)
    bpy.context.collection.objects.link(rig)
    rig.parent = root
    obj.parent = rig
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    anchors = {"pet_body": ((x0 + x1) / 2, y1), "pet_head": neck}
    anchors.update({limb["name"]: limb["pivot"] for limb in limbs})
    for name, point in anchors.items():
        bone = armature.edit_bones.new(name)
        bone.head = position(*point)
        # Local axes match world axes, as expected by pet-actions.py.
        bone.tail = bone.head + Vector((0, 0.1, 0))
        if name != "pet_body":
            bone.parent = armature.edit_bones["pet_head" if name.startswith("pet_ear_") else "pet_body"]
    bpy.ops.object.mode_set(mode="OBJECT")
    for name in anchors:
        group = obj.vertex_groups.new(name=name)
        for index, values in enumerate(weights):
            if values.get(name, 0) > 0:
                group.add([index], values[name], "REPLACE")
    modifier = obj.modifiers.new("Continuous image deformation", "ARMATURE")
    modifier.object = rig
    root["couplemon_render_mode"] = "illustrated"
    root["couplemon_head_radius"] = rx * width * scale
    root["couplemon_motion_version"] = 2
    rig["couplemon_image_rig"] = True
    bpy.context.view_layer.update()

    def contact(name, bone, point):
        anchor = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(anchor)
        anchor.parent, anchor.parent_type, anchor.parent_bone = rig, "BONE", bone
        bpy.context.view_layer.update()
        # Bone parenting includes the tail offset; solve it from the evaluated matrix.
        anchor.matrix_world.translation = position(*point)
    contact("pet_anchor_face", "pet_head", face)
    for limb in limbs:
        if limb["name"].startswith("pet_arm_"):
            contact("pet_anchor_hand_" + limb["name"][-1], limb["name"], limb["tip"])
    if eyes:
        _add_eyes(obj, rig, image, pixels, material, eyes, position)
    return obj


def _add_eyes(surface, rig, image, pixels, original_material, eyes, position):
    """Build original eye cutouts, painted backing, closing lids and closed-eye strokes.

    Lids cover the original iris rather than squashing it. The backing interpolates
    nearby skin/fur; no remote image generator or substituted character art is used.
    """
    width, height = image.size
    backing = array("f", pixels)

    def offset(x, y):
        px = max(0, min(width - 1, round(x * (width - 1))))
        py = max(0, min(height - 1, round((1 - y) * (height - 1))))
        return (py * width + px) * 4

    colors = []
    for x0, y0, x1, y1 in eyes:
        w, h = x1 - x0, y1 - y0
        darkest, luminance = (0.03, 0.02, 0.02), float("inf")
        for py in range(max(0, int(y0 * height)), min(height, math.ceil(y1 * height))):
            y = py / (height - 1)
            for px in range(max(0, int(x0 * width)), min(width, math.ceil(x1 * width))):
                x = px / (width - 1)
                target = offset(x, y)
                if pixels[target + 3] > 0.9:
                    light = sum(pixels[target:target + 3])
                    if light < luminance:
                        luminance, darkest = light, tuple(pixels[target:target + 3])
                tx, ty = (x - x0) / w, (y - y0) / h
                left, right = offset(x0 - w * 0.18, y), offset(x1 + w * 0.18, y)
                top, bottom = offset(x, y0 - h * 0.18), offset(x, y1 + h * 0.18)
                for channel in range(3):
                    horizontal = pixels[left + channel] * (1 - tx) + pixels[right + channel] * tx
                    vertical = pixels[top + channel] * (1 - ty) + pixels[bottom + channel] * ty
                    backing[target + channel] = (horizontal + vertical) * 0.5
        colors.append(darkest)
        # Solve a small harmonic fill with the original border held fixed. This
        # keeps cheek/fur gradients continuous at the cutout edge while removing
        # the iris; a simple rectangular color interpolation leaves visible seams.
        left = max(1, math.floor(x0 * (width - 1)))
        right = min(width - 2, math.ceil(x1 * (width - 1)))
        bottom = max(1, math.floor((1 - y1) * (height - 1)))
        top = min(height - 2, math.ceil((1 - y0) * (height - 1)))
        for _ in range(140):
            change = 0.0
            for py in range(bottom, top + 1):
                for px in range(left, right + 1):
                    target = (py * width + px) * 4
                    neighbors = (target - 4, target + 4, target - width * 4, target + width * 4)
                    for channel in range(3):
                        value = sum(backing[n + channel] for n in neighbors) * 0.25
                        change = max(change, abs(backing[target + channel] - value))
                        backing[target + channel] = value
            if change < 0.0002:
                break
    painted = bpy.data.images.new("eye_backing", width=width, height=height, alpha=True)
    painted.colorspace_settings.name = "sRGB"
    painted.pixels.foreach_set(backing)
    painted.update()
    painted.pack()
    painted_material = original_material.copy()
    painted_material.name = "Eye backing · unlit"
    for node in painted_material.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            node.image = painted
    surface.data.materials[0] = painted_material

    def opaque_copy(source, name):
        # These small patches sit wholly inside the face. Opaque depth writes keep
        # the lids above the iris regardless of transparent-object sorting.
        material = source.copy()
        material.name = name
        nodes = material.node_tree.nodes
        texture = next(node for node in nodes if node.type == "TEX_IMAGE")
        output = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
        for link in list(output.inputs["Surface"].links):
            material.node_tree.links.remove(link)
        material.node_tree.links.new(texture.outputs["Color"], output.inputs["Surface"])
        return material
    open_material = opaque_copy(original_material, "Original eye patch · unlit")
    lid_material = opaque_copy(painted_material, "Closing eye lid · unlit")

    def mesh_part(name, coords, faces, material, role, depth, uv_coords=None):
        points = [position(x, y) + Vector((0, -depth, 0)) for x, y in coords]
        data = bpy.data.meshes.new(name)
        data.from_pydata(points, [], faces)
        data.update()
        uv = data.uv_layers.new(name="UVMap")
        for loop in data.loops:
            x, y = (uv_coords or coords)[loop.vertex_index]
            uv.data[loop.index].uv = (x, 1 - y)
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.parent, obj.parent_type, obj.parent_bone = rig, "BONE", "pet_head"
        bpy.context.view_layer.update()
        obj.matrix_world = rig.matrix_world.copy()
        obj["couplemon_eye_role"] = role
        data.materials.append(material)
        obj.shape_key_add(name="Basis")
        return obj

    def shape(obj, name, coords, depth):
        key = obj.shape_key_add(name=name)
        key.slider_min = -1 if name.startswith("look") else 0
        for point, (x, y) in zip(key.data, coords):
            point.co = position(x, y) + Vector((0, -depth, 0))

    cols, rows = 12, 6
    triangles = []
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            triangles.extend(((a, a + cols + 1, a + 1), (a + 1, a + cols + 1, a + cols + 2)))
    for index, (x0, y0, x1, y1) in enumerate(eyes):
        w, h, mid = x1 - x0, y1 - y0, y0 + (y1 - y0) * 0.55
        def grid(top, bottom):
            return [(x0 + w * col / cols, top + (bottom - top) * row / rows)
                    for row in range(rows + 1) for col in range(cols + 1)]
        coords = grid(y0, y1)
        eye = mesh_part(f"pet_eye_{index}_open", coords, triangles, open_material, "open", 0.002)
        shape(eye, "lookX", [(x + w * 0.10, y) for x, y in coords], 0.002)
        shape(eye, "lookY", [(x, y - h * 0.08) for x, y in coords], 0.002)
        for role, edge, top, bottom in [("upper", y0, y0, mid), ("lower", y1, mid, y1)]:
            target = grid(top, bottom)
            lid = mesh_part(f"pet_eye_{index}_{role}", grid(edge, edge), triangles,
                            lid_material, role, 0.004, uv_coords=target)
            shape(lid, "blink", target, 0.004)
        # A distinct curved closed-eye stroke, grown only at the end of the blink.
        material = bpy.data.materials.new(f"Eye {index} closed stroke")
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        rgb, output = nodes.new("ShaderNodeRGB"), nodes.new("ShaderNodeOutputMaterial")
        def linear(c):
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        rgb.outputs[0].default_value = (*[linear(c) for c in colors[index]], 1)
        material.node_tree.links.new(rgb.outputs[0], output.inputs["Surface"])
        curve, faces = [], []
        for i in range(25):
            t = i / 24
            x, y = x0 + w * (0.06 + 0.88 * t), mid + h * 0.13 * (1 - (2 * t - 1) ** 2)
            curve.extend(((x, y - h * 0.035), (x, y + h * 0.035)))
            if i:
                a = (i - 1) * 2
                faces.extend(((a, a + 1, a + 2), (a + 2, a + 1, a + 3)))
        lash = mesh_part(f"pet_eye_{index}_lash", [((x0 + x1) / 2, mid)] * len(curve),
                         faces, material, "lash", 0.006)
        shape(lash, "blink", curve, 0.006)
