#!/usr/bin/env python3
"""Rückt die Viertel in data/world.json zusammen (kürzere Laufwege), ohne die Viertel selbst zu verkleinern.

Aufruf (im Projektordner):  python3 tools/shrink_world.py [--factor 0.55] [--gap 60] [--dry]

1. Viertel-Mitten werden um die Kartenmitte mit `factor` zusammengeschoben.
2. Überlappungen werden aufgelöst, bis zwischen den Rechtecken `gap` Meter Abstand bleiben (der Krater zählt mit
   seinem Kraterring).
3. Alles, was zu einem Viertel gehört (feste Haufen, freie Flächen, Turm, Kern, Hinterhof, Start, Krater,
   Hafenbecken), wandert mit seinem Viertel. Punkte dazwischen (Vororte, Seilbahnmasten) wandern anteilig nach
   Abstand. Küste und Hügel folgen dem neuen Stadtrand. Seilbahnmasten werden von den Hauptstraßen weggerückt.
"""
import json
import math
import sys

PATH = "data/world.json"
args = sys.argv[1:]
FACTOR = float(args[args.index("--factor") + 1]) if "--factor" in args else 0.55
GAP = float(args[args.index("--gap") + 1]) if "--gap" in args else 60.0
DRY = "--dry" in args

with open(PATH, encoding="utf-8") as f:
    text = f.read()
w = json.loads(text)
D = w["districts"]
crater = w["crater"]


def half(d):
    hx, hz = d["size"][0] / 2, d["size"][1] / 2
    if d["id"] == "krater":  # Kraterring reicht über das Viertel hinaus
        r = crater["rim_radius_m"] + 20
        hx, hz = max(hx, r), max(hz, r)
    return hx, hz


old = {d["id"]: tuple(d["center"]) for d in D}
pos = {k: [v[0] * FACTOR, v[1] * FACTOR] for k, v in old.items()}

# Überlappungen auflösen (in Richtung der kleinsten Durchdringung, beide Seiten je zur Hälfte)
for _ in range(400):
    moved = False
    for i, a in enumerate(D):
        for b in D[i + 1:]:
            pa, pb = pos[a["id"]], pos[b["id"]]
            ha, hb = half(a), half(b)
            dx, dz = pb[0] - pa[0], pb[1] - pa[1]
            ox = ha[0] + hb[0] + GAP - abs(dx)
            oz = ha[1] + hb[1] + GAP - abs(dz)
            if ox > 0 and oz > 0:
                moved = True
                if ox < oz:
                    s = (ox / 2 + 0.01) * (1 if dx >= 0 else -1)
                    pa[0] -= s
                    pb[0] += s
                else:
                    s = (oz / 2 + 0.01) * (1 if dz >= 0 else -1)
                    pa[1] -= s
                    pb[1] += s
    if not moved:
        break

# Hafen liegt an der Küste (Küste = Hafen-Mitte + Abstand wie vorher); die Küste muss unterhalb des Kraterrings
# bleiben, sonst läuft Meer in den Krater. Darum den Hafen notfalls wieder nach Süden schieben.
coast_off = w["coast"]["z_m"] - old["hafen"][1]
rim_south = pos["krater"][1] + crater["rim_radius_m"] + w["coast"]["wobble_m"] + 30
if pos["hafen"][1] + coast_off < rim_south:
    pos["hafen"][1] = rim_south - coast_off

delta = {k: (round(pos[k][0]) - old[k][0], round(pos[k][1]) - old[k][1]) for k in old}


def inside(p, d, margin=0.0):
    c, s = old[d["id"]], d["size"]
    return abs(p[0] - c[0]) <= s[0] / 2 + margin and abs(p[1] - c[1]) <= s[1] / 2 + margin


def rect_dist(p, d):
    c, s = old[d["id"]], d["size"]
    ex = max(abs(p[0] - c[0]) - s[0] / 2, 0)
    ez = max(abs(p[1] - c[1]) - s[1] / 2, 0)
    return math.hypot(ex, ez)


def warp(p):
    """Verschiebung eines Punkts: im Viertel wie das Viertel, sonst nach Abstand gewichtet"""
    for d in D:
        if inside(p, d, 5):
            return delta[d["id"]]
    ws = [(1.0 / max(rect_dist(p, d), 1.0) ** 2, delta[d["id"]]) for d in D]
    t = sum(x for x, _ in ws)
    return (sum(x * v[0] for x, v in ws) / t, sum(x * v[1] for x, v in ws) / t)


def shift(p, dl):
    out = [round(p[0] + dl[0], 1), round(p[1] + dl[1], 1)] + list(p[2:])
    return [int(v) if isinstance(v, float) and v.is_integer() else v for v in out]


by_id = {d["id"]: d for d in D}
for d in D:
    dl = delta[d["id"]]
    d["center"] = shift(d["center"], dl)
    for h in d.get("cables", {}).get("extra_heaps", []):
        h["at"] = shift(h["at"], dl)
    bo = d.get("blockout", {})
    if "keep_free" in bo:
        bo["keep_free"] = [shift(k[:2], dl) + k[2:] for k in bo["keep_free"]]
    if "post" in d:
        d["post"] = shift(d["post"], dl)

campus = delta["campus"]
w["spawn"] = shift(w["spawn"], campus)
w["backyard"]["center"] = shift(w["backyard"]["center"], campus)
for l in w.get("landmarks", []):
    l["pos"] = shift(l["pos"], delta[l.get("district", "campus")])
for site in w.get("sites", []):
    dl = warp(site["at"])
    site["at"] = shift(site["at"], dl)
    for h in site.get("heaps", []):
        h["at"] = shift(h["at"], dl)
tf = w.get("tower_finale", {})
for st in tf.get("stops", []):
    st["at"] = shift(st["at"], campus)
if "core" in tf:
    tf["core"]["at"] = shift(tf["core"]["at"], campus)
crater["center"] = shift(crater["center"], delta["krater"])
hafen = delta["hafen"]
w["harbor_basin"]["center"] = shift(w["harbor_basin"]["center"], hafen)
w["coast"]["z_m"] = round(w["coast"]["z_m"] + hafen[1], 1)

# Hügel folgen dem Stadtrand (gleicher Abstand wie vorher)
def edges(centers):
    xs0 = min(centers[d["id"]][0] - half(d)[0] for d in D)
    xs1 = max(centers[d["id"]][0] + half(d)[0] for d in D)
    zs0 = min(centers[d["id"]][1] - half(d)[1] for d in D)
    return xs0, xs1, zs0
o_w, o_e, o_n = edges(old)
n_w, n_e, n_n = edges({d["id"]: d["center"] for d in D})
for h in w.get("hills", []):
    shift_by = {"north": n_n - o_n, "east": n_e - o_e, "west": n_w - o_w}[h["side"]]
    h["from_m"] = round(h["from_m"] + shift_by)
    h["to_m"] = round(h["to_m"] + shift_by)

# Vororte: anteilig mitwandern; liegt einer dann in einem Viertel, an die nächste freie Stelle rücken
cs = w.get("countryside", {})
coast_limit = w["coast"]["z_m"] - w["coast"]["wobble_m"] - 70


def sub_free(c, size, placed):
    if c[1] + size[1] / 2 > coast_limit or c[0] - size[0] / 2 < n_w - 120 or c[0] + size[0] / 2 > n_e + 120 \
            or c[1] - size[1] / 2 < n_n - 120:
        return False
    for d in D:
        dc, ds = d["center"], half(d)
        if abs(c[0] - dc[0]) < ds[0] + size[0] / 2 + 30 and abs(c[1] - dc[1]) < ds[1] + size[1] / 2 + 30:
            return False
    for o in placed:
        if abs(c[0] - o["center"][0]) < (o["size"][0] + size[0]) / 2 + 40 and \
                abs(c[1] - o["center"][1]) < (o["size"][1] + size[1]) / 2 + 40:
            return False
    return True


kept = []
for sub in cs.get("suburbs", []):
    start = shift(sub["center"], warp(sub["center"]))
    spot = None
    for r in range(0, 600, 15):  # Spirale nach außen
        for k in range(max(1, r // 5)):
            a = k / max(1, r // 5) * 2 * math.pi
            c = [round(start[0] + math.cos(a) * r), round(start[1] + math.sin(a) * r)]
            if sub_free(c, sub["size"], kept):
                spot = c
                break
        if spot:
            break
    if spot is None:
        print("Vorort entfällt (kein Platz mehr):", sub["name"])
        continue
    sub["center"] = spot
    kept.append(sub)
cs["suburbs"] = kept


# Seilbahnen: Masten anteilig mit, Endstationen mit ihrem Viertel; Masten nicht auf Hauptstraßen
def exit_point(a, b):
    ca, cb = a["center"], b["center"]
    hx, hz = a["size"][0] / 2, a["size"][1] / 2
    dx, dz = cb[0] - ca[0], cb[1] - ca[1]
    if abs(dx) > abs(dz):
        return (ca[0] + math.copysign(hx, dx), ca[1])
    return (ca[0], ca[1] + math.copysign(hz, dz))


roads = []
for link in w["roads"]["links"]:
    a, b = by_id[link[0]], by_id[link[1]]
    roads.append((exit_point(a, b), exit_point(b, a)))
road_half = w["roads"]["width_m"] / 2


def push_off_roads(p):
    for (a, b) in roads:
        ax, az = a
        bx, bz = b
        vx, vz = bx - ax, bz - az
        L2 = vx * vx + vz * vz or 1
        t = max(0, min(1, ((p[0] - ax) * vx + (p[1] - az) * vz) / L2))
        qx, qz = ax + vx * t, az + vz * t
        d = math.hypot(p[0] - qx, p[1] - qz)
        need = road_half + 6
        if d < need:
            nx, nz = (-vz, vx) if d < 1e-3 else (p[0] - qx, p[1] - qz)
            n = math.hypot(nx, nz) or 1
            p = [qx + nx / n * need, qz + nz / n * need] + list(p[2:])
    return [round(p[0], 1), round(p[1], 1)] + list(p[2:])


old_by = {d["id"]: {"center": list(old[d["id"]]), "size": d["size"]} for d in D}
for z in w.get("ziplines", []):
    pts = z["points"]
    for i, p in enumerate(pts):
        np_ = shift(p, warp(p))
        if 0 < i < len(pts) - 1:
            np_ = push_off_roads(np_)
        pts[i] = np_

print("Neue Viertel-Mitten (Verschiebung):")
for d in D:
    print(f"  {d['id']:14s} {str(old[d['id']]):18s} -> {d['center']}  {delta[d['id']]}")
print("Stadtrand alt W/O/N:", round(o_w), round(o_e), round(o_n), "neu:", round(n_w), round(n_e), round(n_n))
print("Küste z:", w["coast"]["z_m"], " Hügel:", [(h["side"], h["from_m"], h["to_m"]) for h in w["hills"]])

if not DRY:
    with open(PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(w, ensure_ascii=False, indent="\t") + "\n")
    print("geschrieben:", PATH)
