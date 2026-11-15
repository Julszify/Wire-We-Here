# Erzeugt die Kabelstecker im Spielzeug-Look als eine GLB-Datei.
# Aufruf:
#   Blender -b --python tools/blender/plug_designs.py -- <ausgabeordner>
# Ergebnis: plugs.glb (Objekte plug_power, plug_hdmi, plug_network, plug_usb, plug_jack), plugs_preview.png
#
# Konventionen (wichtig für scripts/cable/plug_meshes.gd):
#   - Ursprung = Kabelende. Das Kabel kommt von -Y, der Stecker zeigt nach +Y (= Godot -Z).
#   - Jeder Stecker passt zu seinem Kabelradius (RADIUS unten, gleiche Werte in balancing.json).
#   - Farben stecken als Vertex-Farben im Mesh (ein Material für alle Stecker = wenige Draw Calls).

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))

RADIUS = {"power": 0.055, "hdmi": 0.047, "network": 0.044, "usb": 0.041, "jack": 0.038}

BLACK = (0.05, 0.05, 0.06)
DARK = (0.12, 0.12, 0.14)
WHITE = (0.92, 0.92, 0.9)
GREY = (0.55, 0.57, 0.6)
METAL = (0.75, 0.76, 0.78)
GOLD = (0.95, 0.72, 0.25)
CLEAR = (0.72, 0.85, 0.95)
BLUE = (0.1, 0.3, 0.9)
RED = (0.85, 0.12, 0.1)

# Teile werden mit Farbe gesammelt und am Ende zu einem Mesh mit Vertex-Farben verbunden
_parts = []


def _add(o, color, smooth=True):
    o["col"] = color
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    _parts.append(o)
    return o


def rbox(color, loc, size, bevel=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = min(bevel, min(size) * 0.45)
    m.segments = 3
    m.limit_method = "NONE"
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return _add(o, color)


def cyl_y(color, y0, y1, r0, r1=None, x=0.0, z=0.0, verts=16):
    """Zylinder bzw. Kegel entlang Y von y0 (Radius r0) bis y1 (Radius r1)."""
    r1 = r0 if r1 is None else r1
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=abs(y1 - y0),
                                    location=(x, (y0 + y1) / 2, z), rotation=(math.radians(-90), 0, 0))
    o = bpy.context.object
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = min(r0, r1, abs(y1 - y0)) * 0.25
    m.segments = 2
    m.limit_method = "ANGLE"
    o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return _add(o, color)


def ball(color, loc, r):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=r, location=loc)
    return _add(bpy.context.object, color)


def ring_y(color, y, major, minor):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=16, minor_segments=4,
                                     location=(0, y, 0), rotation=(math.radians(90), 0, 0))
    return _add(bpy.context.object, color)


def finish(name):
    """Alle gesammelten Teile verbinden, Farben als Vertex-Farben eintragen."""
    global _parts
    bpy.ops.object.select_all(action="DESELECT")
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.convert(target="MESH")
    # Farbe pro Teil vor dem Verbinden als Attribut setzen
    for o in _parts:
        col = o.get("col", (1, 1, 1))
        attr = o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for d in attr.data:
            d.color = (*col, 1.0)
        o.data.color_attributes.active_color = attr
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    o.data.materials.clear()
    o.data.materials.append(plug_material())
    _parts = []
    return o


_plug_mat = None


def plug_material():
    """Material, das die Vertex-Farben zeigt (für die Vorschau; Godot nimmt ein eigenes)."""
    global _plug_mat
    if _plug_mat:
        return _plug_mat
    m = bpy.data.materials.new("Plug")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.3
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.5
    _plug_mat = m
    return m


# ---------------------------------------------------------------- Stecker

def plug_power():
    r = RADIUS["power"]
    cyl_y(WHITE, -0.05, 0.03, r * 1.15, r * 1.45)                   # Knickschutz
    cyl_y(WHITE, 0.03, 0.12, 0.1, 0.1, verts=16)                    # runder Griff
    for y in (0.06, 0.09):
        ring_y(GREY, y, 0.1, 0.008)                                 # Griffrillen
    cyl_y(WHITE, 0.12, 0.15, 0.1, 0.085, verts=16)
    for x in (-0.045, 0.045):
        cyl_y(METAL, 0.15, 0.24, 0.013, 0.013, x=x, verts=10)
        ball(METAL, (x, 0.24, 0), 0.013)
    return finish("plug_power")


def plug_hdmi():
    r = RADIUS["hdmi"]
    cyl_y(BLACK, -0.05, 0.03, r * 1.15, r * 1.35)
    rbox(BLACK, (0, 0.08, 0), (0.16, 0.12, 0.075), bevel=0.025)
    rbox(METAL, (0, 0.17, 0.003), (0.12, 0.07, 0.034), bevel=0.008)
    rbox(DARK, (0, 0.2, 0.003), (0.1, 0.012, 0.02), bevel=0.004)
    return finish("plug_hdmi")


def plug_network():
    r = RADIUS["network"]
    cyl_y(GREY, -0.05, 0.05, r * 1.15, r * 1.4)                     # Tülle
    rbox(CLEAR, (0, 0.12, 0), (0.12, 0.15, 0.095), bevel=0.02)      # durchsichtiger Körper (angedeutet)
    rbox(GOLD, (0, 0.17, 0.042), (0.09, 0.05, 0.016), bevel=0.004)  # Kontakte
    rbox(CLEAR, (0, 0.09, -0.06), (0.06, 0.12, 0.014), bevel=0.005,
         rot=(math.radians(-14), 0, 0))                             # Rastnase
    return finish("plug_network")


def plug_usb():
    r = RADIUS["usb"]
    cyl_y(BLACK, -0.05, 0.03, r * 1.15, r * 1.35)
    rbox(BLACK, (0, 0.08, 0), (0.13, 0.12, 0.075), bevel=0.025)
    rbox(METAL, (0, 0.18, 0), (0.105, 0.09, 0.042), bevel=0.006)
    rbox(BLUE, (0, 0.2, -0.006), (0.085, 0.06, 0.012), bevel=0.003)  # Zunge (USB 3)
    return finish("plug_usb")


def plug_jack():
    r = RADIUS["jack"]
    cyl_y(BLACK, -0.05, 0.03, r * 1.15, r * 1.5)
    cyl_y(BLACK, 0.03, 0.12, 0.06, 0.06, verts=20)
    ring_y(RED, 0.1, 0.06, 0.012)
    cyl_y(METAL, 0.12, 0.2, 0.02, 0.02, verts=12)
    for y in (0.145, 0.175):
        cyl_y(BLACK, y, y + 0.008, 0.021, 0.021, verts=12)
    ball(METAL, (0, 0.205, 0), 0.02)
    return finish("plug_jack")


# ---------------------------------------------------------------- Ablauf

bpy.ops.wm.read_factory_settings(use_empty=True)
plugs = [plug_power(), plug_hdmi(), plug_network(), plug_usb(), plug_jack()]

bpy.ops.object.select_all(action="DESELECT")
for o in plugs:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "plugs.glb"), use_selection=True, export_apply=True,
                          export_format="GLB", export_vertex_color="ACTIVE")

# Vorschau: jeder Stecker an einem kurzen, gebogenen Kabelstück
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = -1.3
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.68, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.06))
floor_mat = bpy.data.materials.new("Floor")
floor_mat.use_nodes = True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.72, 0.74, 0.78, 1)
bpy.context.object.data.materials.append(floor_mat)

palette = [(0.84, 0.27, 0.24), (0.18, 0.44, 0.84), (0.18, 0.62, 0.36), (0.95, 0.76, 0.19), (0.54, 0.33, 0.84)]
for i, (o, (key, r)) in enumerate(zip(plugs, RADIUS.items())):
    x = (i - 2) * 0.42
    o.location = (x, 0, 0.0)
    o.rotation_euler = (0, 0, math.radians(-20))
    curve = bpy.data.curves.new("c", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = r
    curve.bevel_resolution = 3
    sp = curve.splines.new("NURBS")
    pts = [(0, 0, 0), (0, -0.25, 0), (0.15, -0.5, 0), (0.05, -0.8, 0), (-0.1, -1.1, 0)]
    sp.points.add(len(pts) - 1)
    for j, p in enumerate(pts):
        sp.points[j].co = (*p, 1)
    sp.order_u = 4
    sp.use_endpoint_u = True
    cab = bpy.data.objects.new("cable", curve)
    scene.collection.objects.link(cab)
    cab.location = o.location
    cab.rotation_euler = o.rotation_euler
    m = bpy.data.materials.new("Cable%d" % i)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*palette[i], 1)
    p.inputs["Roughness"].default_value = 0.3
    if "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = 0.5
    curve.materials.append(m)

for name, loc, energy in (("Key", (1.5, -2.0, 3.0), 300), ("Fill", (-2.5, -1.0, 1.5), 100), ("Rim", (0, 2.5, 2), 200)):
    d = bpy.data.lights.new(name, "AREA")
    d.energy = energy
    d.size = 2.0
    lo = bpy.data.objects.new(name, d)
    scene.collection.objects.link(lo)
    lo.location = loc
    lo.rotation_euler = (Vector((0, -0.2, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0.12, -0.3, 0))
cam.location = target + Vector((0.25, -1.0, 0.9)).normalized() * 3.3
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1600
scene.render.resolution_y = 800
scene.render.filepath = os.path.join(OUT, "plugs_preview.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "plug_designs.blend"))

for o in plugs:
    o.data.calc_loop_triangles()
    print("TRIS", o.name, len(o.data.loop_triangles))
print("FERTIG", OUT)
