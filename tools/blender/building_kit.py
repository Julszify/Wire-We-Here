# Gebäude-Bausatz im Spielzeug-Look: Dächer, Dachaufbauten, Markisen, Leuchtschilder.
# Aufruf (im Projektordner):
#   Blender -b --python tools/blender/building_kit.py -- assets/models/buildings
# Ergebnis: kit.glb (Objekte siehe Ablauf unten), kit_preview.png
#
# Konventionen (wichtig für scripts/world/city_blockout.gd):
#   - Dächer und Markise sind Einheitsmodelle: Grundfläche 1 x 1 um den Ursprung, Höhe 1 (Boden z = 0).
#     Godot skaliert sie auf das Gebäude. Firstlinie der Satteldächer entlang X (= parallel zur Straße).
#   - Dachaufbauten (Klimagerät, Wassertank, Antenne …) haben echte Maße in Metern und werden nicht skaliert.
#   - Vorderseite zeigt nach -Y (= Godot +Z). Markise: hängt an der Wand bei y = 0 und ragt nach -Y.
#   - Farben als Vertex-Farben. Vertex-Alpha sagt Godot, was damit passiert: 1,0 = wird je Gebäude
#     eingefärbt (helle Grautöne), 0,8 = feste Farbe (Glas, Metall, Holz), 0,5 = leuchtet und wird eingefärbt.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))

TINT = (0.92, 0.92, 0.92)       # wird in Godot eingefärbt
TINT_DARK = (0.7, 0.7, 0.7)
WHITE = (0.95, 0.95, 0.93)
GREY = (0.62, 0.64, 0.68)
DARK = (0.22, 0.24, 0.28)
METAL = (0.75, 0.77, 0.8)
GLASS = (0.45, 0.68, 0.9)
RED = (0.85, 0.22, 0.18)
YELLOW = (0.97, 0.8, 0.3)
ORANGE = (0.96, 0.56, 0.15)
GREEN = (0.3, 0.62, 0.34)
WOOD = (0.62, 0.42, 0.26)
SOLAR = (0.12, 0.2, 0.42)

_parts = []


def _add(o, color, glow=False, smooth=False):
    o["col"] = color
    o["glow"] = glow
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    _parts.append(o)
    return o


def box(color, lo, hi, bevel=0.0, glow=False):
    size = [hi[i] - lo[i] for i in range(3)]
    loc = [(hi[i] + lo[i]) * 0.5 for i in range(3)]
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0.0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = min(bevel, min(size) * 0.45)
        m.segments = 2
        m.limit_method = "NONE"
    return _add(o, color, glow)


def cyl(color, loc, radius, height, verts=12, top=None, glow=False, axis="z"):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius if top is None else top,
                                    depth=height, location=(0, 0, height * 0.5))
    o = bpy.context.object
    bpy.ops.object.transform_apply(location=True)
    if axis == "x":
        o.rotation_euler = (0, math.radians(90), 0)
    elif axis == "y":
        o.rotation_euler = (math.radians(-90), 0, 0)
    o.location = loc
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return _add(o, color, glow)


def poly(color, verts, faces):
    me = bpy.data.meshes.new("p")
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in verts]
    for f in faces:
        bm.faces.new([v[i] for i in f])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("p", me)
    bpy.context.scene.collection.objects.link(o)
    return _add(o, color)


_mat = None


def material():
    global _mat
    if _mat:
        return _mat
    m = bpy.data.materials.new("Kit")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    _mat = m
    return m


def finish(name):
    global _parts
    bpy.ops.object.select_all(action="DESELECT")
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.convert(target="MESH")
    for o in _parts:
        col = o.get("col", (1, 1, 1))
        # Alpha: 1,0 = wird eingefärbt (helle Grautöne), 0,8 = feste Farbe (Glas, Metall …), 0,5 = leuchtet (eingefärbt)
        tintable = tuple(col) in (TINT, TINT_DARK)
        a = 0.5 if o.get("glow", False) else (1.0 if tintable else 0.8)
        attr = o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for d in attr.data:
            d.color = (*col, a)
        o.data.color_attributes.active_color = attr
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(material())
    _parts = []
    return o


# ---------------------------------------------------------------- Dächer (Einheitsgröße)

E = 0.03  # Dachüberstand (relativ)


def roof_gable():
    """Satteldach, First entlang X; Giebelwände in Fassadenfarbe (dunkler Rand), Dachfläche eingefärbt."""
    lo, hi = -0.5 - E, 0.5 + E
    poly(TINT, [(lo, lo, 0), (hi, lo, 0), (hi, 0, 1), (lo, 0, 1)], [(0, 1, 2, 3)])
    poly(TINT, [(hi, hi, 0), (lo, hi, 0), (lo, 0, 1), (hi, 0, 1)], [(0, 1, 2, 3)])
    poly(TINT_DARK, [(-0.5, -0.5, 0), (-0.5, 0.5, 0), (-0.5, 0, 0.97)], [(0, 1, 2)])
    poly(TINT_DARK, [(0.5, 0.5, 0), (0.5, -0.5, 0), (0.5, 0, 0.97)], [(0, 1, 2)])
    box(DARK, (lo, -0.03, 0.97), (hi, 0.03, 1.03))                # Firstziegel
    return finish("RoofGable")


def roof_hip():
    lo, hi = -0.5 - E, 0.5 + E
    i = 0.28
    poly(TINT, [(lo, lo, 0), (hi, lo, 0), (hi, hi, 0), (lo, hi, 0), (-i, 0, 1), (i, 0, 1)],
         [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4)])
    box(DARK, (-i, -0.03, 0.97), (i, 0.03, 1.03))
    return finish("RoofHip")


def roof_mansard():
    """Mansarddach: steile Seiten, flache Kappe, Gauben."""
    lo, hi = -0.5 - E, 0.5 + E
    t = 0.36
    poly(TINT, [(lo, lo, 0), (hi, lo, 0), (hi, hi, 0), (lo, hi, 0),
                (-t, -t, 0.8), (t, -t, 0.8), (t, t, 0.8), (-t, t, 0.8)],
         [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)])
    poly(TINT_DARK, [(-t, -t, 0.8), (t, -t, 0.8), (t, t, 0.8), (-t, t, 0.8)], [(0, 1, 2, 3)])
    for x in (-0.25, 0.0, 0.25):
        box(WHITE, (x - 0.06, -0.47, 0.18), (x + 0.06, -0.38, 0.5), bevel=0.01)
        box(GLASS, (x - 0.04, -0.475, 0.22), (x + 0.04, -0.46, 0.44))
    return finish("RoofMansard")


def roof_parapet():
    """Flachdach: Brüstung rundum (Höhe 1 = Godot skaliert auf ca. 1 m), Kiesfläche."""
    w = 0.025
    box(TINT, (-0.5 - 0.005, -0.5 - 0.005, 0), (0.5 + 0.005, -0.5 + w, 1), bevel=0.004)
    box(TINT, (-0.5 - 0.005, 0.5 - w, 0), (0.5 + 0.005, 0.5 + 0.005, 1), bevel=0.004)
    box(TINT, (-0.5 - 0.005, -0.5, 0), (-0.5 + w, 0.5, 1), bevel=0.004)
    box(TINT, (0.5 - w, -0.5, 0), (0.5 + 0.005, 0.5, 1), bevel=0.004)
    box(TINT_DARK, (-0.5 + w, -0.5 + w, 0), (0.5 - w, 0.5 - w, 0.08))   # Dachfläche (eingefärbt)
    # Abdeckung oben auf der Brüstung (nur der Rand, nicht über die ganze Dachfläche)
    c = 0.008
    box(WHITE, (-0.5 - c, -0.5 - c, 0.95), (0.5 + c, -0.5 + w + c, 1.0))
    box(WHITE, (-0.5 - c, 0.5 - w - c, 0.95), (0.5 + c, 0.5 + c, 1.0))
    box(WHITE, (-0.5 - c, -0.5, 0.95), (-0.5 + w + c, 0.5, 1.0))
    box(WHITE, (0.5 - w - c, -0.5, 0.95), (0.5 + c, 0.5, 1.0))
    return finish("RoofParapet")


def roof_sawtooth():
    """Sheddach für Hallen: vier Zähne entlang Y, steile Seite verglast."""
    n = 4
    for k in range(n):
        y0 = -0.5 + k / n
        y1 = y0 + 1.0 / n
        poly(TINT, [(-0.5, y0, 0), (0.5, y0, 0), (0.5, y1, 1), (-0.5, y1, 1)], [(0, 1, 2, 3)])
        poly(GLASS, [(0.5, y1, 0), (-0.5, y1, 0), (-0.5, y1, 1), (0.5, y1, 1)], [(0, 1, 2, 3)])
        poly(TINT_DARK, [(-0.5, y0, 0), (-0.5, y1, 1), (-0.5, y1, 0)], [(0, 1, 2)])
        poly(TINT_DARK, [(0.5, y0, 0), (0.5, y1, 0), (0.5, y1, 1)], [(0, 1, 2)])
    return finish("RoofSawtooth")


def awning():
    """Markise, Einheitsbreite entlang X, ragt 1 nach -Y, gestreift."""
    stripes = 8
    for k in range(stripes):
        x0 = -0.5 + k / stripes
        x1 = x0 + 1.0 / stripes
        col = TINT if k % 2 == 0 else WHITE
        poly(col, [(x0, 0, 1), (x1, 0, 1), (x1, -1, 0.35), (x0, -1, 0.35)], [(0, 1, 2, 3)])
        poly(col, [(x0, -1, 0.35), (x1, -1, 0.35), (x1, -1, 0), (x0, -1, 0)], [(3, 2, 1, 0)])
    box(DARK, (-0.5, -0.02, 0.97), (0.5, 0.02, 1.03))
    return finish("Awning")


# ---------------------------------------------------------------- Aufbauten (echte Maße)

def ac_unit():
    box(GREY, (-0.8, -0.55, 0), (0.8, 0.55, 0.9), bevel=0.06)
    cyl(DARK, (-0.35, 0, 0.9), 0.32, 0.06, verts=16)
    cyl(DARK, (0.4, 0, 0.9), 0.32, 0.06, verts=16)
    for x in (-0.35, 0.4):
        box(METAL, (x - 0.3, -0.02, 0.96), (x + 0.3, 0.02, 0.98))
    box(DARK, (-0.82, -0.57, 0.1), (0.82, 0.57, 0.18))
    return finish("AcUnit")


def water_tank():
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            box(DARK, (x - 0.06, y - 0.06, 0), (x + 0.06, y + 0.06, 1.6))
    box(DARK, (-0.75, -0.75, 1.5), (0.75, 0.75, 1.62))
    cyl(WOOD, (0, 0, 1.62), 0.95, 2.2, verts=16)
    cyl(DARK, (0, 0, 3.82), 1.0, 0.6, verts=16, top=0.08)
    for z in (2.0, 2.9, 3.6):
        cyl(DARK, (0, 0, z), 0.97, 0.05, verts=16)
    return finish("WaterTank")


def antenna():
    cyl(METAL, (0, 0, 0), 0.08, 7.0, verts=8, top=0.04)
    for z, w in ((2.5, 1.2), (4.0, 0.9), (5.4, 0.6)):
        box(METAL, (-w, -0.03, z), (w, 0.03, z + 0.05))
    cyl(RED, (0, 0, 7.0), 0.12, 0.2, verts=8, glow=True)
    box(DARK, (-0.4, -0.4, 0), (0.4, 0.4, 0.15))
    return finish("Antenna")


def dish():
    box(DARK, (-0.3, -0.3, 0), (0.3, 0.3, 0.15))
    cyl(METAL, (0, 0, 0.15), 0.06, 0.9, verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.8, segments=16, ring_count=8, location=(0, -0.15, 1.2))
    o = bpy.context.object
    o.scale = (1.0, 0.25, 1.0)
    o.rotation_euler = (math.radians(-30), 0, 0)
    _add(o, WHITE, smooth=True)
    return finish("Dish")


def chimney():
    box(RED, (-0.35, -0.35, 0), (0.35, 0.35, 1.8), bevel=0.03)
    box(DARK, (-0.42, -0.42, 1.75), (0.42, 0.42, 1.92), bevel=0.02)
    return finish("Chimney")


def solar_panels():
    for k in range(3):
        y = -1.0 + k * 1.0
        for x in (-0.5, 0.5):
            box(METAL, (x - 0.05, y - 0.05, 0), (x + 0.05, y + 0.05, 0.5 - 0.25 * (x < 0)))
        o = box(SOLAR, (-0.9, y - 0.4, 0.35), (0.9, y + 0.4, 0.4))
        o.rotation_euler = (0, math.radians(-14), 0)
    return finish("SolarPanels")


def vent_stack():
    cyl(METAL, (0, 0, 0), 0.25, 1.4, verts=12)
    cyl(DARK, (0, 0, 1.4), 0.38, 0.1, verts=12)
    cyl(METAL, (0, 0, 1.5), 0.2, 0.25, verts=12, top=0.32)
    return finish("VentStack")


def skylight():
    box(GREY, (-1.2, -0.8, 0), (1.2, 0.8, 0.3), bevel=0.04)
    poly(GLASS, [(-1.1, -0.7, 0.3), (1.1, -0.7, 0.3), (1.1, 0, 0.75), (-1.1, 0, 0.75)], [(0, 1, 2, 3)])
    poly(GLASS, [(1.1, 0.7, 0.3), (-1.1, 0.7, 0.3), (-1.1, 0, 0.75), (1.1, 0, 0.75)], [(0, 1, 2, 3)])
    return finish("Skylight")


def helipad():
    cyl(DARK, (0, 0, 0), 5.0, 0.25, verts=24)
    cyl(YELLOW, (0, 0, 0.25), 4.6, 0.03, verts=24)
    cyl(DARK, (0, 0, 0.27), 4.3, 0.03, verts=24)
    box(WHITE, (-1.6, -0.25, 0.3), (1.6, 0.25, 0.33))
    box(WHITE, (-1.6, -2.0, 0.3), (-1.0, 2.0, 0.33))
    box(WHITE, (1.0, -2.0, 0.3), (1.6, 2.0, 0.33))
    for a in range(8):
        ang = a * math.tau / 8
        cyl(YELLOW, (4.8 * math.cos(ang), 4.8 * math.sin(ang), 0.25), 0.12, 0.15, verts=8, glow=True)
    return finish("Helipad")


def neon_sign():
    """Senkrechtes Leuchtschild an der Fassade (hängt bei y = 0, ragt nach -Y)."""
    box(DARK, (-0.08, -0.15, 0), (0.08, 0.0, 3.2))
    box(TINT, (-0.1, -1.0, 0.2), (0.1, -0.2, 3.0), bevel=0.05, glow=True)
    box(DARK, (-0.12, -1.04, 0.15), (0.12, -0.16, 0.25))
    box(DARK, (-0.12, -1.04, 2.95), (0.12, -0.16, 3.05))
    return finish("NeonSign")


def billboard():
    for x in (-2.2, 2.2):
        box(DARK, (x - 0.1, -0.1, 0), (x + 0.1, 0.1, 2.0))
    box(DARK, (-3.2, -0.25, 1.9), (3.2, 0.1, 4.6), bevel=0.05)
    box(TINT, (-3.0, -0.3, 2.05), (3.0, -0.24, 4.45), glow=True)
    box(METAL, (-3.2, -0.6, 4.6), (3.2, -0.5, 4.7))
    return finish("Billboard")


def floodlight():
    cyl(GREY, (0, 0, 0), 0.4, 26.0, verts=10, top=0.25)
    box(DARK, (-2.2, -0.4, 25.0), (2.2, 0.4, 28.0), bevel=0.1)
    for x in (-1.5, -0.5, 0.5, 1.5):
        for z in (25.7, 27.2):
            box(YELLOW, (x - 0.38, -0.45, z - 0.5), (x + 0.38, -0.4, z + 0.5), glow=True)
    return finish("Floodlight")


def shop_sign():
    """Flaches Ladenschild über dem Schaufenster, Einheitsbreite entlang X (Höhe 1 m, Tiefe 0,2 m)."""
    box(TINT, (-0.5, -0.2, 0), (0.5, 0, 1.0), bevel=0.02, glow=True)
    box(DARK, (-0.5, -0.22, -0.04), (0.5, 0, 0.0))
    return finish("ShopSign")


# ---------------------------------------------------------------- Ablauf

bpy.ops.wm.read_factory_settings(use_empty=True)
units = [roof_gable(), roof_hip(), roof_mansard(), roof_parapet(), roof_sawtooth(), awning(), shop_sign()]
props = [ac_unit(), water_tank(), antenna(), dish(), chimney(), solar_panels(), vent_stack(), skylight(),
         helipad(), neon_sign(), billboard(), floodlight()]
bpy.ops.object.select_all(action="DESELECT")
for o in units + props:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "kit.glb"), use_selection=True, export_apply=True,
                          export_format="GLB", export_vertex_color="ACTIVE")

# Vorschau: Einheitsteile auf 6 m vergrößert in der ersten Reihe, Aufbauten dahinter
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = -1.0
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.72, 0.9, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
bpy.ops.mesh.primitive_plane_add(size=300, location=(0, 0, 0))
fm = bpy.data.materials.new("Floor")
fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.7, 0.72, 0.74, 1)
bpy.context.object.data.materials.append(fm)
for i, o in enumerate(units):
    o.scale = (6, 6, 3)
    o.location = ((i - 3) * 8.0, 0, 0)
for i, o in enumerate(props):
    o.location = ((i - 5.5) * 5.0, 14, 0)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 7, 2))
cam.location = target + Vector((0.2, -1.0, 0.55)).normalized() * 70
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1800
scene.render.resolution_y = 800
scene.render.filepath = os.path.join(OUT, "kit_preview.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "building_kit.blend"))
for o in units + props:
    o.data.calc_loop_triangles()
    print("TRIS", o.name, len(o.data.loop_triangles))
print("FERTIG", OUT)
