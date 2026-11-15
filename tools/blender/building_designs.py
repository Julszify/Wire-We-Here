# Erzeugt die ersten Gebäude im Spielzeug-Look: Wohnhäuser fürs Wohnviertel und die Hülle des Serverraums.
# Aufruf (im Projektordner):
#   Blender -b --python tools/blender/building_designs.py -- assets/models/buildings
# Ergebnis: houses.glb (Objekte House1 … House4), server_room.glb, buildings_preview.png
#
# Konventionen (wichtig für scripts/world/city_blockout.gd und scripts/rack/server_room_view.gd):
#   - Wohnhäuser sind Einheitsmodelle: Grundfläche 1 x 1 m um den Ursprung, Höhe 1 m (Boden bei z = 0,
#     Sockel reicht darunter). Godot skaliert sie auf das Grundstück (Breite, Höhe, Tiefe).
#     Entworfen werden sie in "Entwurfs-Metern" (REF), damit Fenster und Türen stimmige Maße haben.
#     Vorderseite (Haustür) zeigt nach -Y (= Godot +Z).
#   - Der Serverraum hat echte Maße aus data/balancing.json (server_room); Ursprung = Mitte des Bodens,
#     Tür in der Wand nach +Y (= Godot -Z, Richtung Kabelberg). Kollision baut Godot selbst.
#   - Farben stecken als Vertex-Farben im Mesh (ein Material für alles = wenige Draw Calls).

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# Entwurfsmaße eines Wohnhauses: Breite (x, an der Straße), Tiefe (y), Höhe (z, mit Dach)
REF = (12.0, 15.0, 9.0)
PLINTH = 3.0  # Sockel unter dem Boden (für Grundstücke am Hang)

WHITE = (0.93, 0.93, 0.9)
CREAM = (0.95, 0.88, 0.72)
SKY = (0.62, 0.8, 0.92)
YELLOW = (0.97, 0.8, 0.35)
MINT = (0.66, 0.88, 0.76)
RED = (0.8, 0.25, 0.2)
BROWN = (0.5, 0.3, 0.2)
SLATE = (0.28, 0.31, 0.37)
DARK = (0.2, 0.22, 0.26)
GREY = (0.6, 0.62, 0.66)
LIGHT = (0.82, 0.84, 0.87)
GLASS = (0.45, 0.68, 0.9)
BLUE = (0.2, 0.5, 0.9)
ORANGE = (0.95, 0.55, 0.15)
GREEN = (0.35, 0.65, 0.35)

_parts = []


def _add(o, color):
    o["col"] = color
    _parts.append(o)
    return o


def box(color, lo, hi, bevel=0.0):
    """Kiste von Ecke lo bis Ecke hi, Kanten leicht abgerundet."""
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


def cyl(color, loc, radius, height, verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height,
                                        location=(loc[0], loc[1], loc[2] + height * 0.5))
    o = bpy.context.object
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return _add(o, color)


def gable(color, x0, x1, y0, y1, z0, z1, along_x=True):
    """Satteldach: First entlang x (along_x) oder entlang y."""
    me = bpy.data.meshes.new("roof")
    bm = bmesh.new()
    if along_x:
        ym = (y0 + y1) * 0.5
        v = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, ym, z1), (x1, ym, z1))]
        faces = ((0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0))
    else:
        xm = (x0 + x1) * 0.5
        v = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (xm, y0, z1), (xm, y1, z1))]
        faces = ((1, 2, 5, 4), (3, 0, 4, 5), (0, 1, 4), (2, 3, 5), (3, 2, 1, 0))
    for f in faces:
        bm.faces.new([v[i] for i in f])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("roof", me)
    bpy.context.scene.collection.objects.link(o)
    return _add(o, color)


def hip(color, x0, x1, y0, y1, z0, z1, inset):
    """Walmdach: oben eine kleinere Fläche."""
    me = bpy.data.meshes.new("roof")
    bm = bmesh.new()
    lo = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0))]
    hi = [bm.verts.new(p) for p in ((x0 + inset, y0 + inset, z1), (x1 - inset, y0 + inset, z1),
                                    (x1 - inset, y1 - inset, z1), (x0 + inset, y1 - inset, z1))]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(hi)
    bm.faces.new(lo[::-1])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("roof", me)
    bpy.context.scene.collection.objects.link(o)
    return _add(o, color)


_mat = None


def material():
    """Material, das die Vertex-Farben zeigt (für die Vorschau; Godot nimmt ein eigenes)."""
    global _mat
    if _mat:
        return _mat
    m = bpy.data.materials.new("Building")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    _mat = m
    return m


def finish(name, scale=(1.0, 1.0, 1.0)):
    """Alle gesammelten Teile verbinden, Farben als Vertex-Farben eintragen, auf Einheitsgröße bringen."""
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
    o.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(material())
    _parts = []
    return o


# ---------------------------------------------------------------- Wohnhäuser

W, D, H = REF
HX, HY = W * 0.5, D * 0.5


def window(x, y, z, facing, w=1.3, h=1.5):
    """Fenster mit weißem Rahmen an einer Außenwand. facing: 'f' (-y), 'b' (+y), 'l' (-x), 'r' (+x)."""
    t = 0.12
    if facing in "fb":
        s = -1.0 if facing == "f" else 1.0
        box(WHITE, (x - w * 0.5 - 0.12, min(y, y + s * t), z - 0.12), (x + w * 0.5 + 0.12, max(y, y + s * t), z + h + 0.12))
        box(GLASS, (x - w * 0.5, min(y, y + s * (t + 0.04)), z), (x + w * 0.5, max(y, y + s * (t + 0.04)), z + h))
    else:
        s = -1.0 if facing == "l" else 1.0
        box(WHITE, (min(x, x + s * t), y - w * 0.5 - 0.12, z - 0.12), (max(x, x + s * t), y + w * 0.5 + 0.12, z + h + 0.12))
        box(GLASS, (min(x, x + s * (t + 0.04)), y - w * 0.5, z), (max(x, x + s * (t + 0.04)), y + w * 0.5, z + h))


def door(x, color, w=1.3, h=2.3):
    box(WHITE, (x - w * 0.5 - 0.15, -HY - 0.14, 0.3), (x + w * 0.5 + 0.15, -HY, 0.3 + h + 0.15))
    box(color, (x - w * 0.5, -HY - 0.2, 0.3), (x + w * 0.5, -HY, 0.3 + h))
    box(GREY, (x - w * 0.5 - 0.3, -HY - 0.7, 0.0), (x + w * 0.5 + 0.3, -HY, 0.3), bevel=0.04)  # Stufe


def shell(wall, top, floors=2, door_x=0.0, door_color=RED):
    """Sockel, Wände bis `top`, Fenster in Reihen, Haustür."""
    box(DARK, (-HX, -HY, -PLINTH), (HX, HY, 0.35))
    box(wall, (-HX, -HY, 0.3), (HX, HY, top), bevel=0.12)
    floor_h = (top - 0.3) / floors
    for f in range(floors):
        z = 0.3 + f * floor_h + floor_h * 0.35
        for x in (-3.6, 0.0, 3.6):
            if f == 0 and abs(x - door_x) < 1.2:
                continue
            window(x, -HY, z, "f")
            window(x, HY, z, "b")
        for y in (-4.6, 0.0, 4.6):
            window(-HX, y, z, "l")
            window(HX, y, z, "r")
    door(door_x, door_color)


def house1():
    """Cremefarben, rotes Satteldach mit First parallel zur Straße, Schornstein."""
    shell(CREAM, 6.0, door_x=0.0, door_color=BROWN)
    gable(RED, -HX - 0.3, HX + 0.3, -HY - 0.3, HY + 0.3, 5.9, H, along_x=True)
    box(BROWN, (3.0, 1.5, 6.5), (4.0, 2.5, H + 0.0), bevel=0.05)
    return finish("House1", (1 / W, 1 / D, 1 / H))


def house2():
    """Hellblau, graues Walmdach, Gaube."""
    shell(SKY, 6.3, door_x=-3.6, door_color=WHITE)
    hip(SLATE, -HX - 0.3, HX + 0.3, -HY - 0.3, HY + 0.3, 6.2, H, 3.4)
    box(SKY, (-1.2, -HY + 1.2, 6.4), (1.2, -HY + 3.4, 7.9), bevel=0.06)
    box(GLASS, (-0.7, -HY + 1.1, 6.8), (0.7, -HY + 1.25, 7.6))
    return finish("House2", (1 / W, 1 / D, 1 / H))


def house3():
    """Gelb, braunes Satteldach mit Giebel zur Straße, Balkon."""
    shell(YELLOW, 5.6, door_x=3.6, door_color=GREEN)
    gable(BROWN, -HX - 0.3, HX + 0.3, -HY - 0.3, HY + 0.3, 5.5, H, along_x=False)
    box(WHITE, (-3.0, -HY - 1.1, 3.0), (1.6, -HY, 3.2), bevel=0.03)        # Balkonplatte
    box(WHITE, (-3.0, -HY - 1.1, 3.2), (1.6, -HY - 1.0, 4.0))             # Geländer
    window(0.0, -HY, 6.2, "f", w=1.6, h=1.2)                              # Giebelfenster
    return finish("House3", (1 / W, 1 / D, 1 / H))


def house4():
    """Modern: mintgrün und weiß, Flachdach mit Dachterrasse."""
    shell(MINT, 7.6, floors=2, door_x=0.0, door_color=ORANGE)
    box(WHITE, (-HX - 0.15, -HY - 0.15, 7.5), (HX + 0.15, HY + 0.15, 8.0), bevel=0.05)   # Dachrand
    box(WHITE, (-3.0, -1.0, 8.0), (3.0, 5.5, H), bevel=0.1)                              # Aufbau
    box(GLASS, (-2.2, -1.12, 8.15), (2.2, -1.0, 8.85))
    box(GREEN, (-5.2, -6.6, 8.0), (-3.6, -5.0, 8.6), bevel=0.2)                          # Pflanzkübel
    return finish("House4", (1 / W, 1 / D, 1 / H))


# ---------------------------------------------------------------- Serverraum

def server_room():
    with open(os.path.join(ROOT, "data", "balancing.json"), encoding="utf-8") as f:
        cfg = json.load(f)["server_room"]
    sx, sz, sy = cfg["size"]            # Breite (x), Höhe, Tiefe; Blender: x, z, y
    wall = cfg["wall_m"]
    dw, dh = cfg["door_width_m"], cfg["door_height_m"]
    hx, hy = sx * 0.5, sy * 0.5
    side = (sx - dw) * 0.5
    # Wände (Tür in der Wand bei +y)
    box(LIGHT, (-hx, -hy, 0), (hx, -hy + wall, sz))                    # Rückwand
    box(LIGHT, (-hx, -hy, 0), (-hx + wall, hy, sz))
    box(LIGHT, (hx - wall, -hy, 0), (hx, hy, sz))
    box(LIGHT, (-hx, hy - wall, 0), (-hx + side, hy, sz))
    box(LIGHT, (hx - side, hy - wall, 0), (hx, hy, sz))
    box(LIGHT, (-dw * 0.5, hy - wall, dh), (dw * 0.5, hy, sz))         # Sturz
    # Dach mit Überstand und Rand
    box(SLATE, (-hx - 0.3, -hy - 0.3, sz), (hx + 0.3, hy + 0.3, sz + 0.3), bevel=0.06)
    box(DARK, (-hx - 0.35, -hy - 0.35, sz + 0.25), (hx + 0.35, hy + 0.35, sz + 0.45), bevel=0.05)
    # Sockelband und Wolkig-Streifen außen herum
    e = 0.05
    for lo, hi in (((-hx - e, -hy - e, 0), (hx + e, -hy, 0.5)), ((-hx - e, -hy, 0), (-hx, hy + e, 0.5)),
                   ((hx, -hy, 0), (hx + e, hy + e, 0.5)), ((-hx, hy, 0), (-hx + side, hy + e, 0.5)),
                   ((hx - side, hy, 0), (hx, hy + e, 0.5))):
        box(DARK, lo, hi)
        box(BLUE, (lo[0], lo[1], sz - 0.9), (hi[0], hi[1], sz - 0.6))
    # Türrahmen
    box(ORANGE, (-dw * 0.5 - 0.25, hy - 0.05, 0), (-dw * 0.5, hy + 0.12, dh + 0.25), bevel=0.03)
    box(ORANGE, (dw * 0.5, hy - 0.05, 0), (dw * 0.5 + 0.25, hy + 0.12, dh + 0.25), bevel=0.03)
    box(ORANGE, (-dw * 0.5 - 0.25, hy - 0.05, dh), (dw * 0.5 + 0.25, hy + 0.12, dh + 0.25), bevel=0.03)
    # Technik auf dem Dach: Klimageräte, Lüfter, Schüssel
    for x in (-hx + 2.5, -hx + 6.0):
        box(GREY, (x, -2.0, sz + 0.45), (x + 2.4, 0.0, sz + 1.5), bevel=0.1)
        cyl(DARK, (x + 1.2, -1.0, sz + 1.5), 0.75, 0.12, verts=16)
    for x in (2.0, 4.0, 6.0):
        cyl(GREY, (x, 2.5, sz + 0.45), 0.35, 0.9)
        cyl(DARK, (x, 2.5, sz + 1.35), 0.5, 0.12)
    cyl(GREY, (hx - 2.0, -3.0, sz + 0.45), 0.12, 1.6, verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=16, ring_count=8, location=(hx - 2.0, -3.0, sz + 2.2))
    dish = bpy.context.object
    dish.scale = (1.0, 0.25, 1.0)
    dish.rotation_euler = (math.radians(-35), 0, math.radians(25))
    for p in dish.data.polygons:
        p.use_smooth = True
    _add(dish, WHITE)
    # Kabelkanal an der Vorderwand und Lampe über der Tür
    box(GREY, (-hx + 0.6, hy + e, 0.5), (-hx + 0.9, hy + 0.25, sz - 0.9))
    box(GREY, (-hx + 0.6, hy + e, sz - 1.3), (-dw * 0.5 - 0.6, hy + 0.25, sz - 1.0))
    box(YELLOW, (-0.5, hy + 0.05, dh + 0.3), (0.5, hy + 0.35, dh + 0.5), bevel=0.04)
    return finish("ServerRoom")


# ---------------------------------------------------------------- Ablauf

def export(objects, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, filename), use_selection=True, export_apply=True,
                              export_format="GLB", export_vertex_color="ACTIVE")


bpy.ops.wm.read_factory_settings(use_empty=True)
houses = [house1(), house2(), house3(), house4()]
export(houses, "houses.glb")
room = server_room()
export([room], "server_room.glb")

# Vorschau: Häuser in Entwurfsgröße nebeneinander, Serverraum dahinter
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
floor_mat = bpy.data.materials.new("Floor")
floor_mat.use_nodes = True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.45, 0.62, 0.38, 1)
bpy.context.object.data.materials.append(floor_mat)
for i, o in enumerate(houses):
    o.scale = REF
    o.location = ((i - 1.5) * 16.0, 0, 0)
room.location = (0, 34, 0)
room.rotation_euler = (0, 0, math.pi)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 8, 4))
cam.location = target + Vector((0.35, -1.0, 0.5)).normalized() * 105
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1600
scene.render.resolution_y = 800
scene.render.filepath = os.path.join(OUT, "buildings_preview.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "building_designs.blend"))

for o in houses + [room]:
    o.data.calc_loop_triangles()
    print("TRIS", o.name, len(o.data.loop_triangles))
print("FERTIG", OUT)
