# Erzeugt drei Design-Vorschläge für C.O.R.D. im Spielzeug-Look.
# Aufruf:
#   Blender -b --python tools/blender/cord_designs.py -- <ausgabeordner>
# Ergebnis: cord_<variante>.glb, cord_<variante>.png, cord_lineup.png; die .blend-Datei landet neben diesem Skript
#
# Konventionen: Höhe ca. 0,8 m, Figur schaut in Blender nach -Y (= glTF +Z).
# Das Leucht-Material heißt immer "CordRing", damit Godot es später zum Blinken finden kann.

import math
import os
import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
os.makedirs(OUT, exist_ok=True)

CYAN = (0.25, 0.9, 1.0, 1.0)


# ---------------------------------------------------------------- Hilfen

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_mats = {}


def mat(name, color, rough=0.25, metal=0.0, coat=0.6, emit=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = color
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.05
    if emit > 0.0:
        p.inputs["Emission Color"].default_value = color
        p.inputs["Emission Strength"].default_value = emit
    _mats[name] = m
    return m


def finish(obj, root, material, smooth=True, bevel=0.0):
    obj.parent = root
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if smooth and obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 5
        mod.limit_method = "NONE"
        obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    return obj


def sphere(root, material, loc, scale=(1, 1, 1), r=1.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=r, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = scale
    return finish(o, root, material)


def box(root, material, loc, size, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, root, material, smooth=bevel > 0.0, bevel=bevel)


def cylinder(root, material, loc, r, depth, rot=(0, 0, 0), bevel=0.0, verts=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    return finish(o, root, material, smooth=True, bevel=bevel)


def torus(root, material, loc, major, minor, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64,
                                     minor_segments=16, location=loc, rotation=rot)
    return finish(bpy.context.object, root, material)


def cable(root, material, points, radius=0.022, plug_mat=None):
    """Weiches Kabel durch Punkte, mit Stecker am Ende; wird zu einem Mesh umgewandelt."""
    curve = bpy.data.curves.new("Cable", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (*p, 1.0)
    spline.order_u = 4
    spline.use_endpoint_u = True
    obj = bpy.data.objects.new("Cable", curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    finish(obj, root, material)
    if plug_mat:
        a, b = Vector(points[-2]), Vector(points[-1])
        d = (b - a).normalized()
        rot = d.to_track_quat("Z", "Y").to_euler()
        plug = cylinder(root, plug_mat, b + d * 0.03, radius * 1.7, 0.07, rot=rot, bevel=0.008, verts=24)
        plug.name = "Plug"
        # zwei Kontaktstifte
        for side in (-1, 1):
            off = rot.to_matrix() @ Vector((side * radius * 0.7, 0, 0.055))
            pin = cylinder(root, mat("Metal", (0.85, 0.75, 0.4, 1), rough=0.2, metal=1.0, coat=0.0),
                           b + d * 0.03 + off, radius * 0.25, 0.04, rot=rot, verts=12)
            pin.name = "Pin"
    return obj


def new_root(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    layer_col = bpy.context.view_layer.layer_collection.children[name]
    bpy.context.view_layer.active_layer_collection = layer_col
    root = bpy.data.objects.new(name, None)
    col.objects.link(root)
    return root, col


# ---------------------------------------------------------------- Materialien

def materials():
    return {
        "shell": mat("Shell", (0.92, 0.93, 0.95, 1)),
        "dark": mat("Visor", (0.03, 0.04, 0.06, 1), rough=0.1, coat=1.0),
        "ring": mat("CordRing", CYAN, rough=0.3, coat=0.0, emit=1.8),
        "orange": mat("Orange", (1.0, 0.42, 0.08, 1)),
        "red": mat("CableRed", (0.9, 0.12, 0.1, 1)),
        "yellow": mat("CableYellow", (1.0, 0.78, 0.1, 1)),
        "blue": mat("CableBlue", (0.1, 0.35, 0.95, 1)),
        "green": mat("CableGreen", (0.15, 0.75, 0.3, 1)),
        "plug": mat("Plug", (0.2, 0.2, 0.22, 1), rough=0.35),
        "led_g": mat("LedGreen", (0.2, 1.0, 0.3, 1), emit=3.0, coat=0.0),
        "led_o": mat("LedOrange", (1.0, 0.5, 0.05, 1), emit=3.0, coat=0.0),
    }


# ---------------------------------------------------------------- Variante A: Ei

def build_egg(m):
    root, col = new_root("cord_ei")
    sphere(root, m["shell"], (0, 0, 0.42), scale=(0.28, 0.28, 0.36))
    torus(root, m["ring"], (0, 0, 0.36), 0.295, 0.032)
    # Visier mit schief gestelltem Auge (überheblicher Blick)
    sphere(root, m["dark"], (0, -0.205, 0.53), scale=(0.2, 0.09, 0.1))
    # halb geschlossenes, schief gestelltes Auge
    box(root, m["ring"], (0, -0.29, 0.525), (0.15, 0.02, 0.022), bevel=0.01, rot=(0, math.radians(-7), 0))
    # zwei kurze Kabel-Tentakel
    cable(root, m["yellow"], [(0.07, 0.0, 0.12), (0.1, -0.02, 0.0), (0.16, -0.06, -0.06), (0.17, -0.1, -0.16)],
          radius=0.024, plug_mat=m["plug"])
    cable(root, m["red"], [(-0.07, 0.02, 0.12), (-0.09, 0.03, 0.0), (-0.15, 0.0, -0.04), (-0.18, -0.03, -0.13)],
          radius=0.024, plug_mat=m["plug"])
    return root, col


# ---------------------------------------------------------------- Variante B: Server-Box

def build_server(m):
    root, col = new_root("cord_server")
    box(root, m["shell"], (0, 0, 0.3), (0.42, 0.34, 0.34), bevel=0.06)
    # Lüftungsschlitze und LEDs vorne
    for i, z in enumerate((0.22, 0.27, 0.32)):
        box(root, m["dark"], (-0.05, -0.172, z), (0.22, 0.01, 0.018), bevel=0.004)
    sphere(root, m["led_g"], (0.13, -0.172, 0.32), r=0.016)
    sphere(root, m["led_o"], (0.13, -0.172, 0.27), r=0.016)
    # Kuppelkopf mit großem Kamera-Auge
    sphere(root, m["shell"], (0, 0, 0.47), scale=(0.17, 0.17, 0.14))
    cylinder(root, m["dark"], (0, -0.145, 0.52), 0.075, 0.05, rot=(math.radians(90), 0, 0), bevel=0.01)
    cylinder(root, m["ring"], (0, -0.17, 0.515), 0.04, 0.012, rot=(math.radians(90), 0, 0))
    # Lid schräg über dem Auge
    box(root, m["shell"], (0.0, -0.17, 0.575), (0.17, 0.03, 0.03), bevel=0.012, rot=(0, math.radians(10), 0))
    # schiefe Antenne mit Leuchtkugel
    cylinder(root, m["plug"], (0.04, 0.0, 0.66), 0.008, 0.12, rot=(0, math.radians(15), 0), verts=12)
    sphere(root, m["ring"], (0.056, 0.0, 0.725), r=0.022)
    # schwebender, leicht gekippter Ring
    torus(root, m["ring"], (0, 0, 0.3), 0.33, 0.022, rot=(math.radians(10), math.radians(-6), 0))
    # verhedderte Kabel unten
    cable(root, m["blue"], [(-0.1, -0.05, 0.14), (-0.12, -0.08, 0.04), (-0.04, -0.1, -0.02), (-0.08, -0.06, -0.12)],
          plug_mat=m["plug"])
    cable(root, m["yellow"], [(0.0, 0.0, 0.14), (0.04, -0.06, 0.03), (-0.06, -0.02, -0.03), (0.02, -0.04, -0.15)],
          plug_mat=m["plug"])
    cable(root, m["red"], [(0.11, 0.04, 0.14), (0.13, 0.0, 0.03), (0.08, -0.06, -0.04), (0.14, -0.08, -0.1)],
          plug_mat=m["plug"])
    return root, col


# ---------------------------------------------------------------- Variante C: Kabelrolle

def build_spool(m):
    root, col = new_root("cord_rolle")
    cylinder(root, m["orange"], (0, 0, 0.1), 0.25, 0.05, bevel=0.015)
    for i in range(5):
        torus(root, m["green"], (0, 0, 0.155 + i * 0.05), 0.17, 0.026)
    cylinder(root, m["shell"], (0, 0, 0.27), 0.15, 0.24)
    cylinder(root, m["orange"], (0, 0, 0.4), 0.25, 0.05, bevel=0.015)
    torus(root, m["ring"], (0, 0, 0.44), 0.2, 0.018)
    # Kopf mit Bildschirmgesicht
    box(root, m["shell"], (0, 0, 0.55), (0.32, 0.24, 0.2), bevel=0.06)
    box(root, m["dark"], (0, -0.118, 0.555), (0.25, 0.02, 0.14), bevel=0.02)
    # Pixel-Gesicht: ein offenes Auge, ein zugekniffenes, schiefes Grinsen
    box(root, m["ring"], (-0.055, -0.13, 0.575), (0.035, 0.008, 0.045), bevel=0.003)
    box(root, m["ring"], (0.055, -0.13, 0.575), (0.045, 0.008, 0.012), bevel=0.003)
    box(root, m["ring"], (0.01, -0.13, 0.518), (0.07, 0.008, 0.012), bevel=0.003, rot=(0, math.radians(-12), 0))
    box(root, m["ring"], (0.055, -0.13, 0.527), (0.02, 0.008, 0.012), bevel=0.003)
    # kleine Handkurbel an der Seite
    cylinder(root, m["plug"], (0.18, 0, 0.62), 0.012, 0.08, rot=(0, math.radians(90), 0), verts=16)
    box(root, m["orange"], (0.22, 0, 0.66), (0.02, 0.03, 0.1), bevel=0.008)
    cylinder(root, m["plug"], (0.24, 0, 0.7), 0.014, 0.04, rot=(0, math.radians(90), 0), verts=16)
    # loses Kabelende als Schwanz
    cable(root, m["green"], [(0.17, -0.02, 0.18), (0.22, -0.1, 0.1), (0.12, -0.18, 0.0), (0.02, -0.14, -0.06),
                             (0.0, -0.06, -0.14)], radius=0.026, plug_mat=m["plug"])
    return root, col


# ---------------------------------------------------------------- Bühne

def stage():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    # kräftige Farben wie im Spiel (AgX entsättigt zu stark)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -1.3
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.68, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6

    stage_col = bpy.data.collections.new("Buehne")
    scene.collection.children.link(stage_col)
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children["Buehne"]

    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.35))
    bpy.context.object.data.materials.append(mat("Floor", (0.72, 0.74, 0.78, 1), rough=0.6, coat=0.0))

    def light(name, loc, energy, size, color=(1, 1, 1)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        o = bpy.data.objects.new(name, data)
        stage_col.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 0.35)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

    light("Key", (-2.0, -2.5, 2.5), 400, 2.0, (1.0, 0.96, 0.9))
    light("Fill", (2.5, -1.5, 1.0), 120, 3.0, (0.85, 0.9, 1.0))
    light("Rim", (0.5, 2.5, 2.0), 250, 1.5)

    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    stage_col.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, target, dist, lens=50):
    target = Vector(target)
    direction = Vector((0.55, -1.0, 0.35)).normalized()
    cam.location = target + direction * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


def render(path, w, h):
    s = bpy.context.scene
    s.render.resolution_x = w
    s.render.resolution_y = h
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)


def export_glb(root, col, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in col.all_objects:
        o.select_set(True)
    old = root.location.copy()
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_apply=True, export_format="GLB")
    root.location = old


# ---------------------------------------------------------------- Ablauf

reset_scene()
m = materials()
variants = [build_egg(m), build_server(m), build_spool(m)]
cam = stage()

# Einzelbilder und GLB
for root, col in variants:
    for r2, c2 in variants:
        c2.hide_render = c2 is not col
    aim(cam, (0, 0, 0.3), 2.6)
    render(os.path.join(OUT, root.name + ".png"), 900, 900)
    export_glb(root, col, os.path.join(OUT, root.name + ".glb"))

# Gruppenbild
for i, (root, col) in enumerate(variants):
    col.hide_render = False
    root.location = ((i - 1) * 0.95, 0, 0)
aim(cam, (0, 0, 0.3), 4.6, lens=50)
render(os.path.join(OUT, "cord_lineup.png"), 1800, 800)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), "cord_designs.blend"))
print("FERTIG", OUT)
