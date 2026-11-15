# Vereinfachte Stecker für die Blöcke ruhender Kabel (scripts/cable/cable_batch.gd).
# Liest plugs.glb, verringert die Polygone (Decimate, Vertex-Farben bleiben) und schreibt plugs_lod.glb.
# Aufruf:
#   Blender -b --python tools/blender/plug_lod.py -- assets/models/cable
# Ziel: ca. 48 Dreiecke je Stecker (Original 750–1600).

import os
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//"
TARGET_TRIS = 48

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "plugs.glb"))
plugs = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("plug_")]
for o in plugs:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    mod = o.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = min(1.0, TARGET_TRIS / max(tris, 1))
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print("PLUG", o.name, tris, "->", sum(len(p.vertices) - 2 for p in o.data.polygons))
bpy.ops.object.select_all(action="DESELECT")
for o in plugs:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "plugs_lod.glb"), use_selection=True, export_apply=True,
                          export_format="GLB", export_vertex_color="ACTIVE")
