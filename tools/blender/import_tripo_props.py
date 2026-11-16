# Übernimmt Tripo3D-Modelle für die Ausstattung ins Projekt: Polygonzahl auf ein Ziel reduzieren
# (Tripo liefert oft ~100.000 Dreiecke, im Spiel stehen dutzende Exemplare), Texturen auf 1024 px
# verkleinern, als GLB nach assets/models/props/tripo/ schreiben, Werte ausgeben.
# Aufruf:
#   Blender -b --python tools/blender/import_tripo_props.py -- <zielordner> <datei.glb> [<datei.glb> …]
# Der Dateiname wird klein geschrieben (Baum_Gruen_1.glb -> baum_gruen_1.glb).
# Auch für Figuren mit Skelett (Chefs): das Skelett bleibt erhalten, nur das Mesh wird reduziert.

import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]
os.makedirs(out_dir, exist_ok=True)
MAX = 1024
# Ziel-Dreiecke je Modell (nach Namensanfang); sonst DEFAULT
TARGETS = {"baum": 5000, "herbstbaum": 5000, "nadelbaum": 3500, "busch": 3000, "blumenkuebel": 3000,
           "laterne": 3000, "felsen": 2000, "chef_": 20000, "jukebox": 7500}
DEFAULT = 5000


def target_for(name):
    for prefix, t in TARGETS.items():
        if name.startswith(prefix):
            return t
    return DEFAULT

for path in args[1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    name = os.path.splitext(os.path.basename(path))[0].lower()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    total = 0
    for o in meshes:
        o.data.calc_loop_triangles()
        total += len(o.data.loop_triangles)
    ratio = min(1.0, target_for(name) / max(total, 1))
    for o in meshes:
        if ratio < 1.0:
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new("Decimate", "DECIMATE")
            m.ratio = ratio
            m.use_collapse_triangulate = True
            m.delimit = {"UV", "SEAM"}  # UV-Grenzen erhalten, sonst verrutscht die Textur (dunkle Risse)
            bpy.ops.object.modifier_apply(modifier=m.name)
    # Normal Map passt nach dem Reduzieren nicht mehr zur Geometrie (sichtbare Risse): weglassen, glatt schattieren
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in list(mat.node_tree.nodes):
            if node.type == "NORMAL_MAP":
                mat.node_tree.nodes.remove(node)
    for o in meshes:
        for poly in o.data.polygons:
            poly.use_smooth = True
    for im in list(bpy.data.images):
        if im.users == 0 or "normal" in im.name.lower():
            continue
        if im.size[0] > MAX:
            im.scale(MAX, MAX)
            im.pack()
    tris = 0
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    dst = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="AUTO")
    size = [round(hi[i] - lo[i], 3) for i in range(3)]
    print("TRIPO %-16s tris=%6d  groesse(x,y,z)=%s  datei=%.1f MB" % (name, tris, size, os.path.getsize(dst) / 1e6))
