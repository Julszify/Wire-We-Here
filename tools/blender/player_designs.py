# Erzeugt drei Design-Vorschläge für die Spielfigur (gefeuerter IT-Admin) im Spielzeug-Look.
# Aufruf:
#   Blender -b --python tools/blender/player_designs.py -- <ausgabeordner>
# Ergebnis: figur_<variante>.glb, figur_<variante>.png, figur_lineup.png;
# die .blend-Datei der zuletzt gebauten Variante landet neben diesem Skript.
#
# Die Figur besteht aus Einzelteilen, deren Ursprung jeweils im Gelenk liegt. Namen und Maße
# entsprechen scenes/player.tscn, damit Godot sie an die vorhandenen Gelenk-Nodes hängen kann:
#   Body        Rumpf + Kopf, Ursprung am Boden (0, 0, 0)
#   LegL/LegR   Ursprung in der Hüfte (±0,15 | 0,62 m hoch), Bein nach unten
#   UpperArmL/R Ursprung in der Schulter (±0,40 | 1,22 m hoch), Oberarm nach unten (0,24 m)
#   ForearmR    Ursprung im Ellbogen, Unterarm + Hand nach unten (Hand bei 0,40 m)
#   ForearmL    Ursprung im Ellbogen, Unterarm + Hand nach VORN (+Y), um ihn wird das Kabel gewickelt
# Blickrichtung in Blender +Y (= Godot -Z). Links ist -X.

import math
import os
import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))

SHOULDER_Z = 1.22
HIP_Z = 0.62
ELBOW_Z = SHOULDER_Z - 0.24
HAND = 0.40


# ---------------------------------------------------------------- Hilfen

_mats = {}


def mat(name, color, rough=0.35, coat=0.4, metal=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.1
    _mats[name] = m
    return m


def _prep(o, material, smooth=True):
    o.data.materials.clear()
    o.data.materials.append(material)
    if smooth:
        for poly in o.data.polygons:
            poly.use_smooth = True
    return o


def ell(material, loc, semi, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = semi
    return _prep(o, material)


def capsule(material, a, b, r1, r2, seg=32):
    """Glatte, leicht konische Kapsel von Punkt a (Radius r1) nach b (Radius r2)."""
    import bmesh
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    mesh = bpy.data.meshes.new("Capsule")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2 + 1, radius=1.0)
    for v in bm.verts:
        if v.co.z >= 0.0:
            v.co = Vector((v.co.x * r2, v.co.y * r2, v.co.z * r2 + length))
        else:
            v.co = v.co * r1
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("Capsule", mesh)
    bpy.context.collection.objects.link(o)
    o.location = a
    o.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return _prep(o, material)


def rbox(material, loc, size, bevel=0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    _prep(o, material)
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = min(bevel, min(size) * 0.49)
    mod.segments = 4
    mod.limit_method = "NONE"
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return o


def cyl(material, loc, r, depth, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    _prep(o, material)
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = min(r * 0.3, depth * 0.3)
    mod.segments = 3
    mod.limit_method = "ANGLE"
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return o


def torus(material, loc, major, minor, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48,
                                     minor_segments=12, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return _prep(o, material)


def join(objs, name, pivot):
    """Teile zu einem Objekt verbinden, Modifier anwenden, Ursprung ins Gelenk legen."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    bpy.context.scene.cursor.location = pivot
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return o


# ---------------------------------------------------------------- Grundfigur

def build_figure(c, dress):
    """c: Farben, dress: Funktion, die variantenspezifische Teile in die Listen hängt."""
    skin = mat("Skin", c["skin"], rough=0.5, coat=0.2)
    top = mat("Top", c["top"])
    pants = mat("Pants", c["pants"])
    shoe = mat("Shoe", c["shoe"])
    dark = mat("Eye", (0.05, 0.05, 0.07), rough=0.15, coat=1.0)
    bags = mat("EyeBags", (0.62, 0.5, 0.58), rough=0.6, coat=0.0)
    sleeve_lower = mat("SleeveLower", c.get("forearm", c["top"]))
    hand_mat = mat("Hands", c.get("hands", c["skin"]), rough=0.5, coat=0.2)

    parts = {k: [] for k in ("Body", "LegL", "LegR", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR")}
    sx = c.get("torso_x", 0.34)
    sy = c.get("torso_y", 0.24)

    # Rumpf und Kopf
    parts["Body"].append(ell(top, (0, 0, 0.98), (sx, sy, 0.45)))
    parts["Body"].append(ell(skin, (0, 0, 1.56), (0.25, 0.25, 0.25)))
    for side in (-1, 1):
        parts["Body"].append(ell(skin, (side * 0.245, 0, 1.56), (0.04, 0.03, 0.055)))          # Ohren
        parts["Body"].append(ell(dark, (side * 0.085, 0.226, 1.58), (0.03, 0.02, 0.042)))     # Augen
        parts["Body"].append(ell(bags, (side * 0.085, 0.226, 1.535), (0.032, 0.012, 0.011)))  # Augenringe
        parts["Body"].append(rbox(mat("Brow", c["hair"]), (side * 0.085, 0.222, 1.645), (0.065, 0.016, 0.016),
                                  bevel=0.007, rot=(0, math.radians(side * 12), 0)))          # müde Brauen
    parts["Body"].append(ell(skin, (0, 0.25, 1.54), (0.035, 0.035, 0.035)))                   # Nase
    parts["Body"].append(rbox(dark, (0.01, 0.228, 1.47), (0.07, 0.012, 0.012), bevel=0.005,
                              rot=(0, math.radians(-8), 0)))                                   # schiefer Mund

    # Beine mit Schuhen
    for name, side in (("LegL", -1), ("LegR", 1)):
        x = side * 0.15
        parts[name].append(capsule(pants, (x, 0, HIP_Z - 0.02), (x, 0, 0.11), 0.125, 0.095))
        parts[name].append(rbox(shoe, (x, 0.04, c.get("shoe_h", 0.1) / 2), (0.17, 0.28, c.get("shoe_h", 0.1)),
                                bevel=0.045))

    # Oberarme als glatte Kapseln, oben etwas dicker (Schulter)
    for name, side in (("UpperArmL", -1), ("UpperArmR", 1)):
        x = side * 0.4
        parts[name].append(capsule(top, (x, 0, SHOULDER_Z), (x, 0, ELBOW_Z), 0.088, 0.07))

    # rechter Unterarm hängt nach unten, linker zeigt nach vorn; Kapseln gehen weich ins Handgelenk über
    parts["ForearmR"].append(capsule(sleeve_lower, (0.4, 0, ELBOW_Z), (0.4, 0, ELBOW_Z - 0.33), 0.068, 0.056))
    parts["ForearmR"].append(ell(hand_mat, (0.4, 0, ELBOW_Z - HAND), (0.072, 0.072, 0.072)))
    parts["ForearmL"].append(capsule(sleeve_lower, (-0.4, 0, ELBOW_Z), (-0.4, 0.33, ELBOW_Z), 0.068, 0.056))
    parts["ForearmL"].append(ell(hand_mat, (-0.4, HAND, ELBOW_Z), (0.072, 0.072, 0.072)))

    dress(parts, c)

    pivots = {
        "Body": (0, 0, 0),
        "LegL": (-0.15, 0, HIP_Z), "LegR": (0.15, 0, HIP_Z),
        "UpperArmL": (-0.4, 0, SHOULDER_Z), "UpperArmR": (0.4, 0, SHOULDER_Z),
        "ForearmL": (-0.4, 0, ELBOW_Z), "ForearmR": (0.4, 0, ELBOW_Z),
    }
    objs = {k: join(v, k, pivots[k]) for k, v in parts.items()}
    # Ruhepose wie im Spiel ohne Kabel: linker Unterarm hängt angewinkelt herunter
    objs["ForearmL"].rotation_euler = (math.radians(-70), 0, 0)
    objs["ForearmR"].rotation_euler = (math.radians(-11), 0, 0)
    return objs


# ---------------------------------------------------------------- Varianten

def dress_hoodie(p, c):
    hood = mat("Hood", c["hood"])
    hair = mat("Hair", c["hair"], rough=0.6, coat=0.1)
    white = mat("String", (0.95, 0.95, 0.95))
    black = mat("Frame", (0.05, 0.05, 0.06), rough=0.2, coat=0.8)
    p["Body"].append(torus(hood, (0, -0.07, 1.37), 0.17, 0.075, rot=(math.radians(-25), 0, 0), scale=(1.15, 1, 1)))
    p["Body"].append(rbox(hood, (0, 0.212, 0.8), (0.32, 0.045, 0.15), bevel=0.03))   # Bauchtasche
    for side in (-1, 1):
        p["Body"].append(cyl(white, (side * 0.055, 0.215, 1.18), 0.011, 0.16, verts=12))
        p["Body"].append(torus(black, (side * 0.085, 0.247, 1.58), 0.047, 0.008, rot=(math.radians(90), 0, 0)))
    p["Body"].append(cyl(black, (0, 0.25, 1.585), 0.007, 0.08, rot=(0, math.radians(90), 0), verts=8))
    # verstrubbelte Haare
    for pos, r in (((0, 0, 1.76), 0.11), ((0.1, 0.05, 1.74), 0.09), ((-0.1, 0.03, 1.745), 0.095),
                   ((0.05, -0.1, 1.72), 0.1), ((-0.07, -0.12, 1.71), 0.1), ((0.15, -0.04, 1.67), 0.08),
                   ((-0.16, -0.05, 1.67), 0.08), ((0.02, 0.13, 1.73), 0.08), ((-0.06, 0.15, 1.71), 0.06)):
        p["Body"].append(ell(hair, pos, (r, r, r * 0.85)))
    # Bündchen an den Handgelenken und rote Sohlen
    p["ForearmR"].append(torus(hood, (0.4, 0, ELBOW_Z - 0.33), 0.055, 0.02))
    p["ForearmL"].append(torus(hood, (-0.4, 0.33, ELBOW_Z), 0.055, 0.02, rot=(math.radians(90), 0, 0)))
    red = mat("Sole", (0.85, 0.15, 0.12))
    for name, side in (("LegL", -1), ("LegR", 1)):
        p[name].append(rbox(red, (side * 0.15, 0.04, 0.015), (0.175, 0.285, 0.03), bevel=0.012))


def dress_shirt(p, c):
    shirt_dark = mat("ShirtDark", (0.6, 0.72, 0.88))
    tie = mat("Tie", (0.8, 0.1, 0.12))
    hair = mat("Hair", c["hair"], rough=0.6, coat=0.1)
    belt = mat("Belt", (0.3, 0.18, 0.08))
    brown = mat("Frame", (0.25, 0.12, 0.05), rough=0.2, coat=0.8)
    for side in (-1, 1):
        p["Body"].append(rbox(c_top(), (side * 0.06, 0.13, 1.37), (0.1, 0.03, 0.055), bevel=0.012,
                              rot=(math.radians(-30), 0, math.radians(side * -25))))
        p["Body"].append(torus(brown, (side * 0.085, 0.247, 1.58), 0.045, 0.011, rot=(math.radians(90), 0, 0),
                               scale=(1.25, 1, 0.85)))
    p["Body"].append(cyl(brown, (0, 0.25, 1.585), 0.008, 0.06, rot=(0, math.radians(90), 0), verts=8))
    # locker hängende Krawatte
    p["Body"].append(rbox(tie, (0, 0.17, 1.33), (0.06, 0.045, 0.05), bevel=0.015))
    p["Body"].append(rbox(tie, (0.02, 0.247, 1.1), (0.085, 0.03, 0.34), bevel=0.012,
                          rot=(math.radians(12), math.radians(6), 0)))
    # Brusttasche mit Stiften
    p["Body"].append(rbox(shirt_dark, (-0.15, 0.226, 1.16), (0.1, 0.015, 0.11), bevel=0.01))
    for x, col in ((-0.175, (0.1, 0.3, 0.9)), (-0.145, (0.85, 0.1, 0.1)), (-0.12, (0.1, 0.1, 0.1))):
        p["Body"].append(cyl(mat("Pen%.3f" % x, col), (x, 0.232, 1.235), 0.011, 0.07, verts=10))
    p["Body"].append(torus(belt, (0, 0, 0.66), 0.245, 0.028, scale=(1, 0.78, 1)))
    p["Body"].append(rbox(mat("Buckle", (0.85, 0.7, 0.3), metal=1.0, rough=0.25), (0, 0.195, 0.66),
                          (0.06, 0.02, 0.05), bevel=0.01))
    # Haarkranz um den kahlen Kopf, Schnurrbart
    for i in range(9):
        a = math.radians(70 + i * 27.5)
        p["Body"].append(ell(hair, (0.225 * math.sin(a), 0.225 * math.cos(a), 1.6), (0.07, 0.07, 0.075)))
    p["Body"].append(ell(hair, (0, 0.245, 1.505), (0.07, 0.025, 0.025)))
    # Kurzarm: Ärmelsaum am Oberarm; Kaffeetasse in der rechten Hand
    for name, side in (("UpperArmL", -1), ("UpperArmR", 1)):
        p[name].append(torus(c_top(), (side * 0.4, 0, SHOULDER_Z - 0.2), 0.07, 0.022))
    white = mat("Mug", (0.95, 0.95, 0.93), rough=0.2, coat=0.8)
    p["ForearmR"].append(cyl(white, (0.4, 0.085, ELBOW_Z - HAND), 0.05, 0.11, verts=24))
    p["ForearmR"].append(torus(white, (0.45, 0.085, ELBOW_Z - HAND), 0.03, 0.01, rot=(math.radians(90), 0, 0)))
    p["ForearmR"].append(cyl(mat("Coffee", (0.25, 0.12, 0.05)), (0.4, 0.085, ELBOW_Z - HAND + 0.052),
                             0.044, 0.005, verts=24))


def c_top():
    return _mats["Top"]


def dress_tech(p, c):
    vest = mat("Vest", (1.0, 0.82, 0.08))
    stripe = mat("Stripe", (0.82, 0.84, 0.88), rough=0.15, coat=1.0)
    cap = mat("Cap", (0.85, 0.15, 0.12))
    beard = mat("Hair", c["hair"], rough=0.7, coat=0.0)
    belt = mat("Belt", (0.42, 0.26, 0.12))
    orange = mat("CableOrange", (1.0, 0.45, 0.1))
    p["Body"].append(ell(vest, (0, 0, 1.03), (0.352, 0.252, 0.39)))
    for z, k in ((0.95, 0.985), (1.13, 0.97)):
        p["Body"].append(torus(stripe, (0, 0, z), 0.352 * k, 0.016, scale=(1, 0.715, 1)))
    # Kappe verkehrt herum
    p["Body"].append(ell(cap, (0, 0, 1.7), (0.262, 0.262, 0.13)))
    p["Body"].append(rbox(cap, (0, -0.27, 1.66), (0.2, 0.15, 0.022), bevel=0.01, rot=(math.radians(-12), 0, 0)))
    p["Body"].append(ell(cap, (0, 0, 1.83), (0.025, 0.025, 0.015)))
    # Vollbart
    p["Body"].append(ell(beard, (0, 0.16, 1.43), (0.19, 0.12, 0.12)))
    # Werkzeuggürtel mit Taschen, Zange und einer Kabelrolle am Haken
    p["Body"].append(torus(belt, (0, 0, 0.62), 0.215, 0.032, scale=(1, 0.8, 1)))
    for side in (-1, 1):
        p["Body"].append(rbox(belt, (side * 0.17, 0.1, 0.57), (0.085, 0.055, 0.095), bevel=0.015))
    red = mat("Handle", (0.85, 0.12, 0.1))
    for dx in (-0.012, 0.012):
        p["Body"].append(cyl(red, (-0.17 + dx, 0.11, 0.64), 0.008, 0.08, rot=(0, math.radians(dx * 300), 0),
                             verts=8))
    p["Body"].append(torus(orange, (0.235, -0.03, 0.52), 0.075, 0.02, rot=(0, math.radians(90), 0)))
    p["Body"].append(torus(orange, (0.245, -0.03, 0.52), 0.075, 0.02, rot=(0, math.radians(90), 0)))
    # Arbeitshandschuhe-Stulpen
    glove = c.get("hands")
    if glove:
        g = mat("Hands", glove)
        p["ForearmR"].append(cyl(g, (0.4, 0, ELBOW_Z - 0.33), 0.065, 0.05))
        p["ForearmL"].append(cyl(g, (-0.4, 0.33, ELBOW_Z), 0.065, 0.05, rot=(math.radians(90), 0, 0)))


VARIANTS = [
    ("hoodie", dress_hoodie, {
        "skin": (0.96, 0.78, 0.62), "top": (0.22, 0.34, 0.4), "hood": (0.16, 0.26, 0.31),
        "pants": (0.18, 0.28, 0.52), "shoe": (0.95, 0.95, 0.95), "hair": (0.32, 0.19, 0.1),
    }),
    ("hemd", dress_shirt, {
        "skin": (0.98, 0.8, 0.66), "top": (0.78, 0.87, 0.98), "forearm": (0.98, 0.8, 0.66),
        "pants": (0.42, 0.38, 0.32), "shoe": (0.35, 0.2, 0.1), "hair": (0.62, 0.62, 0.64),
        "torso_x": 0.36, "torso_y": 0.27,
    }),
    ("techniker", dress_tech, {
        "skin": (0.86, 0.63, 0.46), "top": (0.16, 0.22, 0.38), "pants": (0.16, 0.22, 0.38),
        "shoe": (0.28, 0.17, 0.09), "hair": (0.36, 0.2, 0.1), "hands": (0.35, 0.36, 0.38), "shoe_h": 0.14,
    }),
]


# ---------------------------------------------------------------- Bühne, Rendern, Export

def stage():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -1.3
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.68, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    floor = bpy.context.object
    floor.name = "Floor"
    floor.data.materials.append(mat("Floor", (0.72, 0.74, 0.78), rough=0.6, coat=0.0))
    for name, loc, energy, size in (("Key", (2.5, 3.0, 3.5), 700, 2.5), ("Fill", (-3.0, 2.0, 1.5), 220, 3.0),
                                    ("Rim", (-0.5, -3.0, 3.0), 400, 2.0)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        o = bpy.data.objects.new(name, data)
        scene.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 0.9)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam, floor


def aim(cam, target, dist):
    target = Vector(target)
    cam.location = target + Vector((0.55, 1.0, 0.22)).normalized() * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()


def render(path, w, h):
    s = bpy.context.scene
    s.render.resolution_x = w
    s.render.resolution_y = h
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)


for key, dress, colors in VARIANTS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    objs = build_figure(colors, dress)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs.values():
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "figur_%s.glb" % key), use_selection=True,
                              export_apply=True, export_format="GLB")
    cam, _ = stage()
    aim(cam, (0, 0, 0.92), 3.9)
    render(os.path.join(OUT, "figur_%s.png" % key), 900, 900)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "player_designs.blend"))

# Gruppenbild aus den exportierten GLBs (prüft gleichzeitig den Export)
bpy.ops.wm.read_factory_settings(use_empty=True)
_mats.clear()
for i, (key, _, _) in enumerate(VARIANTS):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "figur_%s.glb" % key))
    for o in set(bpy.data.objects) - before:
        if o.parent is None:
            o.location.x += (i - 1) * 1.05
cam, _ = stage()
aim(cam, (0, 0, 0.95), 7.4)
render(os.path.join(OUT, "figur_lineup.png"), 1800, 800)
print("FERTIG", OUT)
