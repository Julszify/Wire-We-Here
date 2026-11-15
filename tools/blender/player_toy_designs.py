# Zweite Runde Design-Vorschläge für die Spielfigur: Spielzeug-Proportionen (großer runder Kopf,
# birnenförmiger Körper, kurze kräftige Beine, Fausthände) mit eigenen IT-Admin-Merkmalen.
# Aufruf:
#   Blender -b --python tools/blender/player_toy_designs.py -- assets/models/player/proposals
# Ergebnis: toy_<variante>.glb, toy_<variante>.png, toy_lineup.png
#
# Gelenke wie in scenes/player.tscn (damit Godot die Teile an dieselben Nodes hängen kann):
#   Body        Rumpf + Kopf, Ursprung am Boden
#   LegL/LegR   Ursprung in der Hüfte (±0,15 | 0,62 m), Bein nach unten
#   UpperArmL/R Ursprung in der Schulter (±0,40 | 1,22 m), Oberarm nach unten (0,24 m)
#   ForearmR    Ursprung im Ellbogen, Unterarm + Hand nach unten
#   ForearmL    Ursprung im Ellbogen, Unterarm + Hand nach VORN (+Y); bleibt walzenförmig (Kabel wird darum gewickelt)
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
HEAD_Z = 1.6
HEAD_R = 0.31


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
    bpy.ops.mesh.primitive_uv_sphere_add(segments=56, ring_count=28, radius=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = semi
    return _prep(o, material)


def capsule(material, a, b, r1, r2, seg=40):
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
                                     minor_segments=16, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return _prep(o, material)


# Große, weiche Formen gleicher Farbe werden zu einer glatten Haut verschmolzen (Voxel-Remesh +
# Glätten): Kopf, Ohren und Nase gehen nahtlos ineinander über, Rumpf, Bauch und Schultern ebenso.
# Feine Teile (Brille, Augen, Streifen, Riemen) bleiben unverändert.
SMOOTH_MATS = {"Skin", "Top", "Pants", "Hood", "Beanie", "Cap", "Bib", "Shoe", "Hands", "Sleeve", "Hair", "Sole"}
VOXEL = 0.009


def _apply_all(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")


def smooth_merge(objs):
    groups = {}
    rest = []
    for o in objs:
        m = o.data.materials[0].name if o.data.materials else ""
        if m in SMOOTH_MATS:
            groups.setdefault(m, []).append(o)
        else:
            rest.append(o)
    out = list(rest)
    for m, group in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.convert(target="MESH")
        if len(group) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        rm = o.modifiers.new("Remesh", "REMESH")
        rm.mode = "VOXEL"
        rm.voxel_size = VOXEL
        rm.use_smooth_shade = True
        sm = o.modifiers.new("Smooth", "CORRECTIVE_SMOOTH")
        sm.factor = 0.8
        sm.iterations = 12
        sm.smooth_type = "LENGTH_WEIGHTED"
        sm.rest_source = "ORCO"
        dec = o.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = 0.35
        _apply_all(o)
        o.data.materials.clear()
        o.data.materials.append(bpy.data.materials[m])
        for poly in o.data.polygons:
            poly.use_smooth = True
        out.append(o)
    return out


def join(objs, name, pivot):
    """Teile zu einem Objekt verbinden (große Formen vorher glatt verschmolzen), Ursprung ins Gelenk legen."""
    objs = smooth_merge(objs)
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
    skin = mat("Skin", c["skin"], rough=0.55, coat=0.25)
    top = mat("Top", c["top"], rough=0.6, coat=0.1)
    pants = mat("Pants", c["pants"], rough=0.6, coat=0.1)
    shoe = mat("Shoe", c["shoe"], rough=0.4, coat=0.4)
    sole = mat("Sole", c.get("sole", (0.95, 0.95, 0.93)), rough=0.5, coat=0.2)
    dark = mat("Eye", (0.04, 0.04, 0.06), rough=0.15, coat=1.0)
    cheek = mat("Cheek", (0.95, 0.55, 0.52), rough=0.6, coat=0.0)
    sleeve = mat("Sleeve", c.get("sleeve", c["top"]), rough=0.6, coat=0.1)

    parts = {k: [] for k in ("Body", "LegL", "LegR", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR")}

    # Birnenförmiger Rumpf: unten breit, oben schmaler, geht in den großen Kopf über
    parts["Body"].append(ell(top, (0, 0, 0.82), (0.4, 0.31, 0.36)))
    parts["Body"].append(ell(top, (0, 0, 1.08), (0.33, 0.26, 0.26)))
    parts["Body"].append(ell(pants, (0, 0, 0.6), (0.37, 0.29, 0.16)))
    # Großer, leicht gestauchter Kopf
    parts["Body"].append(ell(skin, (0, 0, HEAD_Z), (HEAD_R, HEAD_R * 0.95, HEAD_R * 0.92)))
    for side in (-1, 1):
        parts["Body"].append(ell(skin, (side * HEAD_R * 0.98, 0, HEAD_Z - 0.02), (0.05, 0.035, 0.07)))   # Ohren
        parts["Body"].append(ell(dark, (side * 0.1, HEAD_R * 0.9, HEAD_Z + 0.01), (0.028, 0.02, 0.036)))  # Augen
        parts["Body"].append(ell(cheek, (side * 0.17, HEAD_R * 0.78, HEAD_Z - 0.09), (0.045, 0.02, 0.03)))
    parts["Body"].append(ell(skin, (0, HEAD_R * 0.97, HEAD_Z - 0.04), (0.04, 0.035, 0.034)))           # Nase
    parts["Body"].append(torus(dark, (0, HEAD_R * 0.86, HEAD_Z - 0.14), 0.035, 0.008,
                               rot=(math.radians(100), 0, 0), scale=(1.0, 1.0, 0.45)))                 # kleines Lächeln

    # Schultern weich in den Rumpf übergehen lassen (Teil des Rumpfs, wird mit ihm verschmolzen)
    for side in (-1, 1):
        parts["Body"].append(ell(top, (side * 0.3, 0, 1.17), (0.13, 0.15, 0.12)))

    # Kurze, kräftige Beine mit runden Schuhen
    for name, side in (("LegL", -1), ("LegR", 1)):
        x = side * 0.15
        parts[name].append(capsule(pants, (x, 0, HIP_Z - 0.05), (x, 0, 0.14), 0.14, 0.12))
        parts[name].append(ell(shoe, (x, 0.05, 0.1), (0.13, 0.19, 0.1)))
        parts[name].append(ell(sole, (x, 0.05, 0.035), (0.135, 0.195, 0.04)))

    # Dicke Oberarme, walzenförmige Unterarme, Fausthände
    # Oberarm mit runder Schulterkugel (im Gelenk, dreht sich mit) und rundem Ellbogen, damit beim
    # Bewegen keine Kanten zwischen den Teilen sichtbar werden
    for name, side in (("UpperArmL", -1), ("UpperArmR", 1)):
        x = side * 0.4
        parts[name].append(capsule(top, (x, 0, SHOULDER_Z), (x, 0, ELBOW_Z), 0.098, 0.08))
        parts[name].append(ell(top, (x, 0, SHOULDER_Z), (0.108, 0.108, 0.108)))
        parts[name].append(ell(top, (x, 0, ELBOW_Z), (0.08, 0.08, 0.08)))
    hand = mat("Hands", c.get("hands", c["skin"]), rough=0.55, coat=0.25)
    parts["ForearmR"].append(capsule(sleeve, (0.4, 0, ELBOW_Z), (0.4, 0, ELBOW_Z - 0.32), 0.077, 0.07))
    parts["ForearmR"].append(ell(hand, (0.4, 0, ELBOW_Z - HAND), (0.09, 0.085, 0.095)))
    parts["ForearmL"].append(capsule(sleeve, (-0.4, 0, ELBOW_Z), (-0.4, 0.32, ELBOW_Z), 0.074, 0.07))
    parts["ForearmL"].append(ell(hand, (-0.4, HAND, ELBOW_Z), (0.09, 0.095, 0.085)))

    dress(parts, c)

    pivots = {
        "Body": (0, 0, 0),
        "LegL": (-0.15, 0, HIP_Z), "LegR": (0.15, 0, HIP_Z),
        "UpperArmL": (-0.4, 0, SHOULDER_Z), "UpperArmR": (0.4, 0, SHOULDER_Z),
        "ForearmL": (-0.4, 0, ELBOW_Z), "ForearmR": (0.4, 0, ELBOW_Z),
    }
    objs = {k: join(v, k, pivots[k]) for k, v in parts.items()}
    objs["ForearmL"].rotation_euler = (math.radians(-70), 0, 0)
    objs["ForearmR"].rotation_euler = (math.radians(-11), 0, 0)
    return objs


def glasses(p, color, square=True, z=HEAD_Z + 0.01):
    """Große Nerd-Brille: eckige (bzw. runde) Rahmen vor den Augen, Steg, Bügel."""
    frame = mat("Frame", color, rough=0.2, coat=0.9)
    lens = mat("Lens", (0.85, 0.92, 1.0), rough=0.05, coat=1.0)
    y = HEAD_R * 0.93
    for side in (-1, 1):
        x = side * 0.105
        if square:
            p["Body"].append(rbox(frame, (x, y, z), (0.15, 0.025, 0.11), bevel=0.03))
            p["Body"].append(rbox(lens, (x, y + 0.006, z), (0.12, 0.02, 0.08), bevel=0.02))
        else:
            p["Body"].append(torus(frame, (x, y, z), 0.062, 0.013, rot=(math.radians(90), 0, 0)))
        p["Body"].append(cyl(frame, (side * 0.25, y * 0.5, z + 0.01), 0.01, 0.3, rot=(math.radians(90), 0, 0), verts=8))
    p["Body"].append(cyl(frame, (0, y + 0.005, z + 0.01), 0.011, 0.07, rot=(0, math.radians(90), 0), verts=8))


def hair_tufts(p, color, spots):
    hair = mat("Hair", color, rough=0.65, coat=0.1)
    for pos, r in spots:
        p["Body"].append(ell(hair, pos, (r, r, r * 0.8)))


# ---------------------------------------------------------------- Varianten

def dress_headset(p, c):
    """Wolkig-Hoodie, Headset mit Mikrofon, eckige Brille, Firmenausweis am Band, Sneaker in Signalorange."""
    hood = mat("Hood", c["hood"], rough=0.6, coat=0.1)
    white = mat("White", (0.95, 0.95, 0.94))
    black = mat("Black", (0.08, 0.08, 0.1), rough=0.3, coat=0.6)
    orange = mat("Orange", (1.0, 0.5, 0.12), rough=0.4, coat=0.4)
    hair_tufts(p, c["hair"], [((0, 0.05, HEAD_Z + 0.27), 0.12), ((0.12, 0.0, HEAD_Z + 0.24), 0.1),
                              ((-0.12, 0.02, HEAD_Z + 0.24), 0.1), ((0.04, 0.16, HEAD_Z + 0.22), 0.08),
                              ((0, -0.13, HEAD_Z + 0.22), 0.12)])
    glasses(p, (0.1, 0.1, 0.12))
    # Kapuze im Nacken, Bauchtasche, Wolkenlogo auf der Brust
    p["Body"].append(torus(hood, (0, -0.12, 1.3), 0.2, 0.08, rot=(math.radians(-20), 0, 0), scale=(1.2, 1, 1)))
    p["Body"].append(rbox(hood, (0, 0.29, 0.78), (0.36, 0.05, 0.17), bevel=0.04))
    for dx, r in ((-0.04, 0.035), (0.0, 0.045), (0.045, 0.032)):
        p["Body"].append(ell(white, (0.15 + dx, 0.255, 1.06 + (0.01 if dx == 0 else 0)), (r, 0.012, r * 0.8)))
    # Headset: Bügel über den Kopf, Muscheln, Mikrofonarm
    p["Body"].append(torus(black, (0, 0, HEAD_Z + 0.02), HEAD_R + 0.02, 0.018, rot=(math.radians(90), 0, 0)))
    for side in (-1, 1):
        p["Body"].append(cyl(black, (side * (HEAD_R + 0.025), 0, HEAD_Z - 0.01), 0.075, 0.05,
                             rot=(0, math.radians(90), 0)))
        p["Body"].append(cyl(orange, (side * (HEAD_R + 0.052), 0, HEAD_Z - 0.01), 0.05, 0.012,
                             rot=(0, math.radians(90), 0)))
    p["Body"].append(capsule(black, (-(HEAD_R + 0.03), 0.03, HEAD_Z - 0.04), (-0.12, HEAD_R * 0.85, HEAD_Z - 0.16), 0.012, 0.012))
    p["Body"].append(ell(orange, (-0.11, HEAD_R * 0.88, HEAD_Z - 0.165), (0.03, 0.025, 0.025)))
    # Firmenausweis am Band (rot durchgestrichen – gefeuert)
    red = mat("Red", (0.9, 0.15, 0.12))
    p["Body"].append(torus(red, (0, 0.12, 1.2), 0.15, 0.008, rot=(math.radians(-35), 0, 0), scale=(1.0, 1.0, 1.6)))
    p["Body"].append(rbox(white, (0, 0.31, 0.98), (0.1, 0.015, 0.13), bevel=0.012))
    p["Body"].append(rbox(red, (0, 0.32, 0.98), (0.12, 0.006, 0.016), bevel=0.003, rot=(0, math.radians(35), 0)))
    # Bündchen und orange Sneaker
    p["ForearmR"].append(torus(hood, (0.4, 0, ELBOW_Z - 0.32), 0.07, 0.022))
    p["ForearmL"].append(torus(hood, (-0.4, 0.32, ELBOW_Z), 0.07, 0.022, rot=(math.radians(90), 0, 0)))
    for name, side in (("LegL", -1), ("LegR", 1)):
        p[name].append(rbox(white, (side * 0.15, 0.2, 0.12), (0.06, 0.03, 0.04), bevel=0.012))


def dress_jacket(p, c):
    """Orange Warnjacke mit Reflexstreifen, Strickmütze mit Bommel, dicke Brille, Werkzeuggürtel mit Kabelbindern."""
    stripe = mat("Stripe", (0.85, 0.88, 0.9), rough=0.15, coat=1.0)
    beanie = mat("Beanie", c["beanie"], rough=0.8, coat=0.0)
    pom = mat("Pom", (1.0, 0.85, 0.2), rough=0.9, coat=0.0)
    belt = mat("Belt", (0.3, 0.2, 0.12), rough=0.6, coat=0.1)
    tie = mat("Tie", (0.95, 0.95, 0.95), rough=0.4)
    glasses(p, (0.12, 0.3, 0.75))
    # Mütze mit Umschlag und Bommel
    p["Body"].append(ell(beanie, (0, 0, HEAD_Z + 0.1), (HEAD_R * 1.02, HEAD_R * 1.0, HEAD_R * 0.78)))
    p["Body"].append(torus(beanie, (0, 0, HEAD_Z + 0.08), HEAD_R * 0.98, 0.045, scale=(1, 0.97, 1)))
    p["Body"].append(ell(pom, (0, 0, HEAD_Z + 0.36), (0.08, 0.08, 0.08)))
    # Reflexstreifen um Rumpf und Arme, Reißverschluss
    for z, k in ((0.86, 1.0), (1.05, 0.9)):
        p["Body"].append(torus(stripe, (0, 0, z), 0.38 * k, 0.018, scale=(1, 0.79, 1)))
    p["Body"].append(rbox(stripe, (0, 0.315, 0.95), (0.025, 0.012, 0.42), bevel=0.006))
    for name, side in (("UpperArmL", -1), ("UpperArmR", 1)):
        p[name].append(torus(stripe, (side * 0.4, 0, SHOULDER_Z - 0.15), 0.09, 0.014))
    # Gürtel mit Taschen, Seitenschneider und Bündel Kabelbinder
    p["Body"].append(torus(belt, (0, 0, 0.64), 0.36, 0.035, scale=(1, 0.8, 1)))
    for side in (-1, 1):
        p["Body"].append(rbox(belt, (side * 0.26, 0.2, 0.58), (0.1, 0.07, 0.11), bevel=0.02))
    for k in range(5):
        p["Body"].append(torus(tie, (0.33, 0.06, 0.6 - k * 0.012), 0.05, 0.004, rot=(0, math.radians(90), 0)))
    red = mat("Handle", (0.85, 0.12, 0.1))
    p["Body"].append(capsule(red, (-0.26, 0.24, 0.62), (-0.24, 0.24, 0.72), 0.012, 0.012))
    p["Body"].append(capsule(red, (-0.28, 0.24, 0.62), (-0.3, 0.24, 0.72), 0.012, 0.012))
    # Arbeitshandschuhe
    for name in ("ForearmR", "ForearmL"):
        pass


def dress_overall(p, c):
    """Latzhose über Ringelshirt, Schirmmütze mit Wolkenlogo, Kopfhörer um den Hals, Kabelrolle über der Schulter."""
    bib = mat("Bib", c["pants"], rough=0.6, coat=0.1)
    stripe = mat("Ringel", c["stripe"], rough=0.6, coat=0.1)
    cap = mat("Cap", c["cap"], rough=0.5, coat=0.2)
    white = mat("White", (0.95, 0.95, 0.94))
    black = mat("Black", (0.08, 0.08, 0.1), rough=0.3, coat=0.6)
    metal = mat("Metal", (0.85, 0.82, 0.7), rough=0.25, metal=1.0)
    cable = mat("Cable", (0.2, 0.75, 0.35), rough=0.3, coat=0.6)
    hair_tufts(p, c["hair"], [((side * 0.25, -0.05, HEAD_Z + 0.06), 0.09) for side in (-1, 1)] +
               [((0, -0.22, HEAD_Z + 0.04), 0.13)])
    glasses(p, (0.55, 0.3, 0.12), square=False)
    # Ringel auf dem Shirt (Querstreifen um den oberen Rumpf und die Oberarme)
    for z in (1.0, 1.08, 1.16):
        p["Body"].append(torus(stripe, (0, 0, z), 0.31 if z > 1.1 else 0.33, 0.02, scale=(1, 0.8, 1)))
    for name, side in (("UpperArmL", -1), ("UpperArmR", 1)):
        for dz in (0.06, 0.14):
            p[name].append(torus(stripe, (side * 0.4, 0, SHOULDER_Z - dz), 0.095, 0.016))
    # Latz und Träger mit Knöpfen
    p["Body"].append(ell(bib, (0, 0.2, 0.9), (0.2, 0.12, 0.17)))
    p["Body"].append(rbox(bib, (0, 0.31, 0.92), (0.13, 0.02, 0.09), bevel=0.015))         # Brusttasche
    for side in (-1, 1):
        p["Body"].append(capsule(bib, (side * 0.14, 0.27, 1.02), (side * 0.2, 0.18, 1.24), 0.028, 0.028))
        p["Body"].append(capsule(bib, (side * 0.2, 0.18, 1.24), (side * 0.18, -0.22, 1.16), 0.028, 0.028))
        p["Body"].append(ell(metal, (side * 0.14, 0.31, 1.02), (0.026, 0.012, 0.026)))
    # Schirmmütze mit Wolkenlogo
    p["Body"].append(ell(cap, (0, 0, HEAD_Z + 0.14), (HEAD_R * 1.0, HEAD_R * 1.0, HEAD_R * 0.62)))
    p["Body"].append(rbox(cap, (0, HEAD_R * 0.98, HEAD_Z + 0.12), (0.34, 0.24, 0.025), bevel=0.012,
                          rot=(math.radians(-8), 0, 0)))
    for dx, r in ((-0.035, 0.03), (0.0, 0.04), (0.04, 0.028)):
        p["Body"].append(ell(white, (dx, HEAD_R * 0.97, HEAD_Z + 0.24), (r, 0.012, r * 0.8)))
    # Kopfhörer um den Hals
    p["Body"].append(torus(black, (0, 0.02, 1.27), 0.2, 0.02, scale=(1.05, 1.0, 1.0)))
    for side in (-1, 1):
        p["Body"].append(cyl(black, (side * 0.18, 0.12, 1.26), 0.06, 0.05, rot=(math.radians(70), 0, 0)))
    # Kabelrolle über der rechten Schulter
    for k in range(3):
        p["Body"].append(torus(cable, (0.3, 0.02 + k * 0.012, 1.06), 0.24, 0.022,
                               rot=(math.radians(8), math.radians(-25), 0), scale=(0.55, 1, 1)))


VARIANTS = [
    ("headset", dress_headset, {
        "skin": (0.97, 0.8, 0.66), "top": (0.2, 0.5, 0.9), "hood": (0.15, 0.4, 0.78),
        "pants": (0.25, 0.27, 0.33), "shoe": (1.0, 0.5, 0.12), "hair": (0.38, 0.22, 0.12),
    }),
    ("warnjacke", dress_jacket, {
        "skin": (0.88, 0.66, 0.5), "top": (1.0, 0.45, 0.08), "beanie": (0.25, 0.32, 0.45),
        "pants": (0.2, 0.24, 0.32), "shoe": (0.32, 0.2, 0.12), "sole": (0.2, 0.2, 0.22), "hair": (0.2, 0.14, 0.1),
        "hands": (0.32, 0.34, 0.38), "sleeve": (1.0, 0.45, 0.08),
    }),
    ("latzhose", dress_overall, {
        "skin": (0.75, 0.55, 0.42), "top": (0.96, 0.95, 0.92), "stripe": (0.2, 0.45, 0.85),
        "pants": (0.32, 0.72, 0.68), "cap": (0.95, 0.3, 0.25), "shoe": (0.95, 0.95, 0.95),
        "sole": (0.2, 0.45, 0.85), "hair": (0.12, 0.09, 0.08),
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
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "toy_%s.glb" % key), use_selection=True,
                              export_apply=True, export_format="GLB")
    cam, _ = stage()
    aim(cam, (0, 0, 0.95), 4.2)
    render(os.path.join(OUT, "toy_%s.png" % key), 900, 900)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "player_toy_designs.blend"))

bpy.ops.wm.read_factory_settings(use_empty=True)
_mats.clear()
for i, (key, _, _) in enumerate(VARIANTS):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "toy_%s.glb" % key))
    for o in set(bpy.data.objects) - before:
        if o.parent is None:
            o.location.x += (i - 1) * 1.15
cam, _ = stage()
aim(cam, (0, 0, 1.0), 7.8)
render(os.path.join(OUT, "toy_lineup.png"), 1800, 800)
print("FERTIG", OUT)
