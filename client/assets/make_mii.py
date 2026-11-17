import bpy
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mii.glb")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):
    bpy.data.materials.remove(m)
for c in list(bpy.data.curves):
    bpy.data.curves.remove(c)
for a in list(bpy.data.armatures):
    bpy.data.armatures.remove(a)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)


def mat(name, color, rough=0.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


SKIN = mat("Skin", (0.95, 0.78, 0.6), 0.55)
SKIN_D = mat("SkinDark", (0.85, 0.66, 0.48), 0.55)
SHIRT = mat("Shirt", (0.2, 0.6, 0.3), 0.7)
HAIR = mat("Hair", (0.15, 0.1, 0.05), 0.85)
DARK = mat("Dark", (0.06, 0.05, 0.07), 0.4)
MOUTH = mat("Mouth", (0.4, 0.14, 0.1), 0.5)
PANTS = mat("Pants", (0.15, 0.15, 0.2), 0.8)

parts = []


def add_sphere(name, loc, scale, material, segments=32, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=loc
    )
    o = bpy.context.object
    o.name = name
    o.scale = scale
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    parts.append(o)
    return o


def add_cone(name, loc, radius, depth, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(
        radius1=radius, depth=depth, vertices=16, location=loc, rotation=rot
    )
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    parts.append(o)
    return o


def _curve_obj(name, pts, bevel, material):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1.0)
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    parts.append(ob)
    return ob


def add_arc(name, center, radius, a0, a1, bevel, material, n=14):
    pts = []
    for i in range(n):
        t = math.radians(a0 + (a1 - a0) * i / (n - 1))
        pts.append((
            center[0] + radius * math.cos(t),
            center[1],
            center[2] + radius * math.sin(t),
        ))
    return _curve_obj(name, pts, bevel, material)


def add_line(name, pts, bevel, material):
    return _curve_obj(name, pts, bevel, material)


def add_torus(name, loc, major, minor, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=24, minor_segments=8,
        location=loc, rotation=rot,
    )
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    parts.append(o)
    return o


# Corps + bassin
add_sphere("Torso", (0, 0, 0.95), (0.17, 0.15, 0.22), SHIRT)
add_sphere("Lap", (0, 0.02, 0.74), (0.19, 0.17, 0.09), PANTS)

# Tête + nez (partagés entre tous les visages)
add_sphere("Head", (0, 0, 1.29), (0.155, 0.152, 0.167), SKIN)
add_sphere("Nose", (0, 0.148, 1.285), (0.014, 0.01, 0.02), SKIN_D, 20, 12)

# ---------- Visages ----------
# Face0 : yeux points + sourire
for side in (-1.0, 1.0):
    add_sphere(f"Face0_Eye_{side:+.0f}", (side * 0.055, 0.138, 1.31), (0.017, 0.009, 0.028), DARK, 20, 12)
    add_arc(f"Face0_Brow_{side:+.0f}", (side * 0.055, 0.145, 1.342), 0.026, 20, 160, 0.005, HAIR)
add_arc("Face0_Smile", (0, 0.148, 1.245), 0.035, 195, 345, 0.007, MOUTH, 18)

# Face1 : joyeux (yeux en ∩) + grand sourire
for side in (-1.0, 1.0):
    add_arc(f"Face1_Eye_{side:+.0f}", (side * 0.05, 0.145, 1.295), 0.024, 15, 165, 0.007, DARK)
add_arc("Face1_Smile", (0, 0.148, 1.24), 0.046, 195, 345, 0.011, MOUTH, 18)

# Face2 : en colère (sourcils inclinés + moue)
for side in (-1.0, 1.0):
    add_sphere(f"Face2_Eye_{side:+.0f}", (side * 0.055, 0.138, 1.30), (0.014, 0.008, 0.022), DARK, 20, 12)
    add_line(
        f"Face2_Brow_{side:+.0f}",
        [(side * 0.02, 0.148, 1.335), (side * 0.09, 0.148, 1.36)],
        0.006, HAIR,
    )
add_arc("Face2_Frown", (0, 0.148, 1.21), 0.03, 30, 150, 0.007, MOUTH, 14)

# Face3 : surpris (petits yeux + bouche en O)
for side in (-1.0, 1.0):
    add_sphere(f"Face3_Eye_{side:+.0f}", (side * 0.055, 0.138, 1.315), (0.012, 0.007, 0.018), DARK, 20, 12)
add_torus("Face3_Mouth", (0, 0.145, 1.24), 0.02, 0.008, MOUTH, (math.pi / 2, 0, 0))

# ---------- Cheveux ----------
# Hair0 : calotte
add_sphere("Hair0_Cap", (0, -0.02, 1.36), (0.168, 0.163, 0.125), HAIR)
# Hair1 : chauve (aucun objet)
# Hair2 : calotte + frange
add_sphere("Hair2_Cap", (0, -0.02, 1.36), (0.168, 0.163, 0.125), HAIR)
add_sphere("Hair2_Fringe", (0, 0.1, 1.38), (0.1, 0.045, 0.045), HAIR)
# Hair3 : pics
add_sphere("Hair3_Cap", (0, -0.02, 1.365), (0.166, 0.161, 0.12), HAIR)
for i, (hx, hy) in enumerate([(-0.06, 0.0), (-0.02, 0.04), (0.03, 0.04), (0.07, -0.01)]):
    add_cone(f"Hair3_Spike{i}", (hx, hy, 1.47), 0.03, 0.08, HAIR)
# Hair4 : coupe au carré (calotte élargie + mèches latérales)
add_sphere("Hair4_Cap", (0, -0.02, 1.35), (0.17, 0.166, 0.13), HAIR)
for side in (-1.0, 1.0):
    add_sphere(f"Hair4_Side{side:+.0f}", (side * 0.14, 0.01, 1.28), (0.05, 0.06, 0.12), HAIR, 20, 12)
# Hair5 : calotte + chignon
add_sphere("Hair5_Cap", (0, -0.02, 1.36), (0.168, 0.163, 0.125), HAIR)
add_sphere("Hair5_Bun", (0, -0.04, 1.47), (0.07, 0.07, 0.06), HAIR, 20, 12)

# Bras + mains
for side in (-1.0, 1.0):
    arm = add_sphere(f"Arm_{side:+.0f}", (side * 0.19, 0.08, 0.92), (0.048, 0.048, 0.13), SHIRT, 24, 14)
    arm.rotation_euler = (math.radians(72), 0, -side * math.radians(18))
    add_sphere(f"Hand_{side:+.0f}", (side * 0.175, 0.28, 0.80), (0.047, 0.047, 0.047), SKIN, 20, 12)

# Lunettes
for side in (-1.0, 1.0):
    add_torus(f"Glasses_{side:+.0f}", (side * 0.055, 0.148, 1.31), 0.033, 0.004, DARK, (math.pi / 2, 0, 0))
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.152, 1.315))
bridge = bpy.context.object
bridge.name = "Glasses_B"
bridge.scale = (0.017, 0.003, 0.003)
bridge.data.materials.append(DARK)
parts.append(bridge)

# ---------- Application des transforms ----------
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# ---------- Rig ----------
arm_data = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
b_root = eb.new("Root")
b_root.head = (0, 0, 0.55)
b_root.tail = (0, 0, 0.75)
b_body = eb.new("Body")
b_body.head = (0, 0, 0.75)
b_body.tail = (0, 0, 1.1)
b_body.parent = b_root
b_head = eb.new("Head")
b_head.head = (0, 0, 1.1)
b_head.tail = (0, 0, 1.45)
b_head.parent = b_body
bpy.ops.object.mode_set(mode="OBJECT")

HEAD_PARTS = ("Head", "Nose", "Hair", "Face", "Eye", "Brow", "Smile", "Frown", "Mouth", "Glasses")
BODY_PARTS = ("Torso", "Arm", "Hand")


def bone_of(name):
    if name.startswith(HEAD_PARTS):
        return "Head"
    if name.startswith(BODY_PARTS):
        return "Body"
    return "Root"


for o in parts:
    bone = bone_of(o.name)
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    o.parent = rig

# ---------- Animation flinch ----------
sc = bpy.context.scene
sc.frame_start = 1
sc.frame_end = 16
rig.animation_data_create()
act = bpy.data.actions.new("flinch")
rig.animation_data.action = act

pb_h = rig.pose.bones["Head"]
pb_b = rig.pose.bones["Body"]
pb_h.rotation_mode = "XYZ"
pb_b.rotation_mode = "XYZ"

poses = [
    (1, (1, 1, 1), (1, 1, 1), 0.0),
    (4, (1.12, 0.68, 1.12), (1.06, 0.88, 1.06), -0.16),
    (7, (0.94, 1.14, 0.94), (0.97, 1.06, 0.97), 0.05),
    (11, (1.03, 0.95, 1.03), (1.0, 0.98, 1.0), -0.02),
    (16, (1, 1, 1), (1, 1, 1), 0.0),
]
for frame, hscale, bscale, brot in poses:
    pb_h.scale = hscale
    pb_h.keyframe_insert("scale", frame=frame)
    pb_b.scale = bscale
    pb_b.keyframe_insert("scale", frame=frame)
    pb_b.rotation_euler = (brot, 0, 0)
    pb_b.keyframe_insert("rotation_euler", frame=frame)

# ---------- Export ----------
bpy.ops.object.select_all(action="DESELECT")
for o in parts + [rig]:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("EXPORTED", OUT)
