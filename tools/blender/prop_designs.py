# Erzeugt die Ausstattung für den Hinterhof im Spielzeug-Look als eine GLB-Datei.
# Aufruf (im Projektordner):
#   Blender -b --python tools/blender/prop_designs.py -- assets/models/props
# Ergebnis: yard_props.glb (Objekte siehe NAMES unten), yard_props_preview.png
#
# Konventionen (wichtig für scripts/world/yard_props.gd):
#   - Echte Maße in Metern, Ursprung = Mitte der Standfläche am Boden.
#   - Vorderseite zeigt nach -Y (= Godot +Z).
#   - Farben stecken als Vertex-Farben im Mesh (ein Material für alles).

import math
import os
import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))

LEAF = (0.3, 0.62, 0.3)
LEAF2 = (0.42, 0.7, 0.32)
PINE = (0.2, 0.48, 0.32)
TRUNK = (0.45, 0.3, 0.2)
WOOD = (0.75, 0.58, 0.38)
CARD = (0.78, 0.62, 0.42)
DARK = (0.2, 0.22, 0.26)
GREY = (0.6, 0.62, 0.66)
LIGHT = (0.85, 0.86, 0.88)
WHITE = (0.94, 0.94, 0.92)
BLUE = (0.2, 0.5, 0.9)
ORANGE = (0.95, 0.55, 0.15)
YELLOW = (0.97, 0.8, 0.35)
RED = (0.8, 0.25, 0.2)
GREEN = (0.25, 0.5, 0.35)
GLASS = (0.45, 0.68, 0.9)
SOIL = (0.35, 0.25, 0.18)

_parts = []


def _add(o, color, smooth=False):
    o["col"] = color
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    _parts.append(o)
    return o


def box(color, lo, hi, bevel=0.0):
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
    return _add(o, color)


def cyl(color, loc, radius, height, verts=12, top=None, axis="z"):
    """Zylinder oder Kegelstumpf (top = oberer Radius) ab loc nach oben bzw. entlang der Achse."""
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
    return _add(o, color)


def ball(color, loc, radius, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=loc)
    o = bpy.context.object
    o.scale = scale
    return _add(o, color, smooth=True)


_mat = None


def material():
    global _mat
    if _mat:
        return _mat
    m = bpy.data.materials.new("Prop")
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
        attr = o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for d in attr.data:
            d.color = (*col, 1.0)
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


# ---------------------------------------------------------------- Ausstattung

def tree_round():
    """Laubbaum mit Kugelkrone, ca. 6 m."""
    cyl(TRUNK, (0, 0, 0), 0.28, 2.6, top=0.2)
    ball(LEAF, (0, 0, 4.0), 1.9)
    ball(LEAF2, (0.9, 0.4, 3.3), 1.2)
    ball(LEAF2, (-0.8, -0.5, 3.5), 1.3)
    ball(LEAF, (0.1, 0.6, 5.0), 1.2)
    return finish("TreeRound")


def tree_pine():
    """Nadelbaum aus drei Kegeln, ca. 7 m."""
    cyl(TRUNK, (0, 0, 0), 0.22, 1.6, top=0.18)
    cyl(PINE, (0, 0, 1.2), 1.9, 2.4, top=0.5, verts=10)
    cyl(PINE, (0, 0, 2.9), 1.5, 2.2, top=0.3, verts=10)
    cyl(PINE, (0, 0, 4.5), 1.0, 2.4, top=0.0, verts=10)
    return finish("TreePine")


def bush():
    ball(LEAF, (0, 0, 0.55), 0.75, scale=(1.2, 1.0, 0.8))
    ball(LEAF2, (0.55, 0.15, 0.45), 0.5)
    ball(LEAF2, (-0.5, -0.2, 0.5), 0.55)
    return finish("Bush")


def planter():
    """Pflanzkübel mit kleinem Busch."""
    box(LIGHT, (-0.6, -0.6, 0), (0.6, 0.6, 0.7), bevel=0.08)
    box(SOIL, (-0.5, -0.5, 0.62), (0.5, 0.5, 0.72))
    ball(LEAF2, (0, 0, 1.15), 0.6, scale=(1.0, 1.0, 0.9))
    ball(LEAF, (0.25, -0.2, 1.45), 0.35)
    return finish("Planter")


def bench():
    for x in (-0.75, 0.75):
        box(DARK, (x - 0.06, -0.25, 0), (x + 0.06, 0.25, 0.45))
        box(DARK, (x - 0.06, 0.2, 0.45), (x + 0.06, 0.28, 0.95))
    for y in (-0.2, -0.02, 0.16):
        box(WOOD, (-0.95, y - 0.07, 0.45), (0.95, y + 0.07, 0.51), bevel=0.015)
    for z in (0.62, 0.8):
        box(WOOD, (-0.95, 0.22, z), (0.95, 0.28, z + 0.13), bevel=0.015)
    return finish("Bench")


def lamp():
    """Hoflaterne, 4 m."""
    cyl(DARK, (0, 0, 0), 0.16, 0.3, top=0.1)
    cyl(DARK, (0, 0, 0.3), 0.07, 3.4)
    box(DARK, (-0.08, -0.7, 3.6), (0.08, 0.08, 3.72))
    box(DARK, (-0.22, -0.95, 3.5), (0.22, -0.5, 3.66), bevel=0.04)
    box(YELLOW, (-0.17, -0.9, 3.45), (0.17, -0.55, 3.51))
    return finish("Lamp")


def pallet_stack():
    """Palette mit gestapelten Kartons."""
    for y in (-0.5, 0.0, 0.5):
        box(WOOD, (-0.6, y - 0.07, 0), (0.6, y + 0.07, 0.1))
    for x in (-0.5, -0.25, 0.0, 0.25, 0.5):
        box(WOOD, (x - 0.07, -0.6, 0.1), (x + 0.07, 0.6, 0.14))
    box(CARD, (-0.55, -0.55, 0.14), (0.0, 0.0, 0.64), bevel=0.02)
    box(CARD, (0.02, -0.55, 0.14), (0.55, 0.05, 0.56), bevel=0.02)
    box(CARD, (-0.5, 0.03, 0.14), (0.5, 0.55, 0.7), bevel=0.02)
    box(CARD, (-0.4, -0.45, 0.66), (0.2, 0.15, 1.1), bevel=0.02)
    box(BLUE, (-0.4, -0.16, 0.66), (0.2, -0.12, 1.105))            # Klebeband mit Wolkig-Blau
    box(ORANGE, (-0.2, 0.5, 0.3), (0.2, 0.555, 0.5))               # Aufkleber
    return finish("PalletStack")


def dumpster():
    box(GREEN, (-0.9, -0.55, 0.12), (0.9, 0.55, 1.1), bevel=0.06)
    box(DARK, (-0.95, -0.6, 1.08), (0.95, 0.6, 1.2), bevel=0.04)
    for x in (-0.7, 0.7):
        for y in (-0.4, 0.4):
            cyl(DARK, (x - 0.04, y, 0.1), 0.1, 0.08, axis="x", verts=10)
    box(YELLOW, (-0.3, -0.565, 0.5), (0.3, -0.55, 0.8))
    return finish("Dumpster")


def cable_drum():
    """Leere Kabeltrommel aus Holz, liegt auf der Seite."""
    cyl(WOOD, (-0.45, 0, 0.75), 0.75, 0.08, axis="x", verts=20)
    cyl(WOOD, (0.37, 0, 0.75), 0.75, 0.08, axis="x", verts=20)
    cyl(TRUNK, (-0.4, 0, 0.75), 0.32, 0.8, axis="x", verts=14)
    cyl(DARK, (-0.47, 0, 0.75), 0.1, 0.94, axis="x", verts=10)
    return finish("CableDrum")


def van():
    """Lieferwagen von C.O.R.D.s Bestelldienst."""
    box(WHITE, (-1.0, -1.2, 0.45), (1.0, 2.6, 2.4), bevel=0.12)                # Laderaum
    box(WHITE, (-0.95, -2.6, 0.45), (0.95, -1.2, 1.9), bevel=0.15)             # Fahrerhaus
    box(GLASS, (-0.85, -2.63, 1.15), (0.85, -2.5, 1.75), bevel=0.03)           # Frontscheibe
    for x in (-0.97, 0.97):
        box(GLASS, (min(x, x * 1.01), -2.35, 1.2), (max(x, x * 1.01), -1.5, 1.75))
        box(BLUE, (min(x, x * 1.012), -1.0, 1.1), (max(x, x * 1.012), 2.4, 1.5))   # Streifen
        box(ORANGE, (min(x, x * 1.016), 0.2, 1.6), (max(x, x * 1.016), 1.2, 2.1))  # Logo-Feld
    box(DARK, (-1.02, -2.68, 0.35), (1.02, -2.5, 0.6), bevel=0.04)             # Stoßstange
    box(YELLOW, (-0.85, -2.66, 0.7), (-0.5, -2.6, 0.9))
    box(YELLOW, (0.5, -2.66, 0.7), (0.85, -2.6, 0.9))
    for y in (-1.8, 1.7):
        for x in (-1.0, 0.78):
            cyl(DARK, (x, y, 0.42), 0.42, 0.22, axis="x", verts=16)
    return finish("Van")


def fence():
    """Zaunfeld, 3 m breit (entlang x)."""
    for x in (-1.45, 1.45):
        box(DARK, (x - 0.05, -0.05, 0), (x + 0.05, 0.05, 1.5))
    for z in (0.25, 0.75, 1.25):
        box(GREY, (-1.45, -0.02, z), (1.45, 0.02, z + 0.05))
    for i in range(11):
        x = -1.25 + i * 0.25
        box(GREY, (x - 0.015, -0.015, 0.15), (x + 0.015, 0.015, 1.4))
    return finish("Fence")


# ---------------------------------------------------------------- Ablauf

bpy.ops.wm.read_factory_settings(use_empty=True)
props = [tree_round(), tree_pine(), bush(), planter(), bench(), lamp(), pallet_stack(), dumpster(), cable_drum(),
         van(), fence()]
bpy.ops.object.select_all(action="DESELECT")
for o in props:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "yard_props.glb"), use_selection=True, export_apply=True,
                          export_format="GLB", export_vertex_color="ACTIVE")

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = -1.0
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.72, 0.9, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
floor_mat = bpy.data.materials.new("Floor")
floor_mat.use_nodes = True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.7, 0.72, 0.74, 1)
bpy.context.object.data.materials.append(floor_mat)
for i, o in enumerate(props):
    o.location = ((i - (len(props) - 1) * 0.5) * 3.6, 0, 0)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 0, 2.0))
cam.location = target + Vector((0.15, -1.0, 0.35)).normalized() * 42
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1800
scene.render.resolution_y = 600
scene.render.filepath = os.path.join(OUT, "yard_props_preview.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "prop_designs.blend"))

for o in props:
    o.location = (0, 0, 0)
    o.data.calc_loop_triangles()
    print("TRIS", o.name, len(o.data.loop_triangles))
print("FERTIG", OUT)
