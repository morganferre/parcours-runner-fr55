"""
Prepares a route WITH the surrounding streets for the Parcours Runner app (Forerunner 55).

Steps:
  1. reads the GPX and simplifies the track (like the web converter);
  2. downloads the surrounding streets and paths from OpenStreetMap (Overpass server);
  3. keeps those within --width meters of the route, simplifies them
     and sorts them into 500 m tiles;
  4. generates source/RoutePack.mc and resources/route_pack/route_pack.xml;
  5. builds bin/ParcoursRunner.prg, ready to copy to the watch.

Usage (from the project folder):
  python tools/prepare_route.py my_route.gpx
  python tools/prepare_route.py my_route.gpx --width 300 --reverse
  python tools/prepare_route.py --no-map        (back to the version without a built-in route)
"""

import argparse
import base64
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "cache"
PACK_MC = ROOT / "source" / "RoutePack.mc"
PACK_RES = ROOT / "resources" / "route_pack"
PRG = ROOT / "bin" / "ParcoursRunner.prg"

# Must stay identical to the watch code (source/RouteMap.mc).
M_LAT = 110574.0
M_LON = 111320.0
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
TILE = 500

OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

# Categories drawn on the watch (same numbering as RouteMap.mc)
CAT_STREET, CAT_MAIN_ROAD, CAT_PATH, CAT_WATER = 0, 1, 2, 3
PATHS = {"footway", "path", "track", "bridleway", "cycleway", "pedestrian"}
WATERWAYS = {"river", "stream", "canal"}

MAIN_ROADS = {
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
}
IGNORED = {
    "proposed", "construction", "platform", "corridor", "elevator", "bus_stop",
    "raceway", "abandoned", "razed", "disused", "services", "rest_area",
}
# Details useless to a runner and costly to draw.
IGNORED_SERVICE = {"driveway", "parking_aisle", "drive-through", "emergency_access"}
IGNORED_FOOTWAY = {"sidewalk", "crossing", "traffic_island"}


# ---------------------------------------------------------------- helpers

def info(msg):
    print(msg, flush=True)


def stop(msg):
    print("\nERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def enc(d):
    """Signed integer -> text (zigzag + 5-bit chunks, same encoding as the watch)."""
    z = d * 2 if d >= 0 else -d * 2 - 1
    s = ""
    while z >= 32:
        s += ALPHA[32 + (z & 31)]
        z //= 32
    return s + ALPHA[z]


def simplify(p, eps):
    """Iterative Douglas-Peucker (point-to-segment distance)."""
    n = len(p)
    if n < 3:
        return list(p)
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = p[a]
        bx, by = p[b]
        vx, vy = bx - ax, by - ay
        l2 = vx * vx + vy * vy
        md, mi = 0.0, -1
        for i in range(a + 1, b):
            t = ((p[i][0] - ax) * vx + (p[i][1] - ay) * vy) / l2 if l2 else 0.0
            t = max(0.0, min(1.0, t))
            dx = p[i][0] - ax - t * vx
            dy = p[i][1] - ay - t * vy
            d = dx * dx + dy * dy
            if d > md:
                md, mi = d, i
        if mi >= 0 and md > eps * eps:
            keep[mi] = True
            stack += [(a, mi), (mi, b)]
    return [q for q, k in zip(p, keep) if k]


def round_points(points):
    out = []
    for x, y in points:
        q = (int(round(x)), int(round(y)))
        if not out or out[-1] != q:
            out.append(q)
    return out


# ---------------------------------------------------------------- route

def read_gpx(path):
    try:
        root = ET.parse(path).getroot()
    except Exception as e:
        stop(f"cannot read {path}: {e}")
    for tag in ("trkpt", "rtept", "wpt"):
        pts = []
        for el in root.iter():
            if el.tag.split("}")[-1] == tag:
                try:
                    pts.append((float(el.get("lat")), float(el.get("lon"))))
                except (TypeError, ValueError):
                    pass
        if len(pts) >= 2:
            return pts
    stop("no track found in this GPX (it needs a trkpt track or an rtept route).")


def flip_start(pts):
    """Out-and-back: starts the route from the other end (the turnaround becomes the start)."""
    c = math.cos(math.radians(pts[0][0]))
    def d(a, b):
        return math.hypot((a[1] - b[1]) * M_LON * c, (a[0] - b[0]) * M_LAT)
    if d(pts[0], pts[-1]) > 100:
        stop("--flip-start: the GPX start and finish are more than 100 m apart, "
             "this is not an out-and-back. Use --reverse instead.")
    k = max(range(len(pts)), key=lambda i: d(pts[0], pts[i]))
    info(f"     start moved to the other end, {d(pts[0], pts[k]):.0f} m from the old start")
    return pts[k:] + pts[1:k + 1]


def prepare_track(pts, max_pts):
    lat0e6 = round(pts[0][0] * 1e6)
    lon0e6 = round(pts[0][1] * 1e6)
    la0, lo0 = lat0e6 / 1e6, lon0e6 / 1e6
    cos0 = math.cos(math.radians(la0))
    xy = [((lo - lo0) * M_LON * cos0, (la - la0) * M_LAT) for la, lo in pts]

    eps = 2.0
    while True:
        ints = round_points(simplify(xy, eps))
        if len(ints) <= max_pts:
            break
        eps *= 1.25

    data, px, py = "", 0, 0
    for x, y in ints:
        data += enc(x - px) + enc(y - py)
        px, py = x, y
    text = f"P1;{len(ints)};{lat0e6};{lon0e6};{data}"
    dist = sum(math.hypot(ints[i][0] - ints[i - 1][0], ints[i][1] - ints[i - 1][1]) for i in range(1, len(ints)))
    return {
        "text": text, "ints": ints, "xy": xy, "dist": dist,
        "lat0e6": lat0e6, "lon0e6": lon0e6, "la0": la0, "lo0": lo0, "cos0": cos0,
    }


# ---------------------------------------------------------------- OpenStreetMap

def download_streets(bbox):
    s, w, n, e = bbox
    ignored = "|".join(sorted(IGNORED))
    bb = f"({s:.6f},{w:.6f},{n:.6f},{e:.6f})"
    q = (f'[out:json][timeout:180];('
         f'way["highway"]["highway"!~"^({ignored})$"]["area"!="yes"]{bb};'
         f'way["waterway"~"^(river|stream|canal)$"]{bb};'
         f'way["natural"="water"]{bb};'
         f');out geom;')

    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / ("osm_" + hashlib.sha1(q.encode()).hexdigest()[:16] + ".json")
    if cached.exists():
        info("   streets already downloaded (cache)")
        return json.loads(cached.read_text(encoding="utf-8"))

    body = urllib.parse.urlencode({"data": q}).encode()
    last_error = None
    for attempt in range(3):
        for url in OVERPASS:
            try:
                info(f"   downloading from {urllib.parse.urlparse(url).netloc}...")
                req = urllib.request.Request(url, data=body, headers={"User-Agent": "ParcoursRunner/1.0"})
                with urllib.request.urlopen(req, timeout=180) as r:
                    d = json.load(r)
                cached.write_text(json.dumps(d), encoding="utf-8")
                return d
            except Exception as e:
                last_error = e
                info(f"   server unavailable ({e}), trying the next one")
        time.sleep(10)
    stop(f"cannot reach OpenStreetMap ({last_error}). Check the internet connection and try again in a few minutes.")


class Corridor:
    """Fast distance to the route using a grid of 100 m cells."""

    def __init__(self, ints, width):
        self.c = 100.0
        self.width = width
        self.cells = {}
        r = int(math.ceil(width / self.c)) + 1
        for i in range(len(ints) - 1):
            (ax, ay), (bx, by) = ints[i], ints[i + 1]
            x0, x1 = sorted((ax, bx))
            y0, y1 = sorted((ay, by))
            for cx in range(int(math.floor(x0 / self.c)) - r, int(math.floor(x1 / self.c)) + r + 1):
                for cy in range(int(math.floor(y0 / self.c)) - r, int(math.floor(y1 / self.c)) + r + 1):
                    self.cells.setdefault((cx, cy), []).append((ax, ay, bx, by))

    def near(self, x, y):
        segs = self.cells.get((int(math.floor(x / self.c)), int(math.floor(y / self.c))))
        if not segs:
            return False
        l2max = self.width * self.width
        for ax, ay, bx, by in segs:
            vx, vy = bx - ax, by - ay
            l2 = vx * vx + vy * vy
            t = ((x - ax) * vx + (y - ay) * vy) / l2 if l2 else 0.0
            t = max(0.0, min(1.0, t))
            dx, dy = x - ax - t * vx, y - ay - t * vy
            if dx * dx + dy * dy <= l2max:
                return True
        return False


def densify(pts, step):
    """Adds points on long segments so that clipping to the corridor is accurate."""
    out = [pts[0]]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        L = math.hypot(bx - ax, by - ay)
        k = int(L // step)
        for i in range(1, k + 1):
            t = i / (k + 1)
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t))
        out.append((bx, by))
    return out


def prepare_streets(osm, route, width):
    corridor = Corridor(route["ints"], width)
    la0, lo0, cos0 = route["la0"], route["lo0"], route["cos0"]
    pieces = []   # (category, [(x, y) integers])
    for el in osm.get("elements", []):
        if el.get("type") != "way" or "geometry" not in el:
            continue
        tags = el.get("tags", {})
        hw = tags.get("highway", "")
        if tags.get("waterway") in WATERWAYS or tags.get("natural") == "water":
            cat = CAT_WATER
        elif hw in MAIN_ROADS:
            cat = CAT_MAIN_ROAD
        elif hw in PATHS:
            cat = CAT_PATH
        else:
            cat = CAT_STREET
        if hw in IGNORED:
            continue
        if hw == "service" and tags.get("service") in IGNORED_SERVICE:
            continue
        if hw in ("footway", "path") and tags.get("footway") in IGNORED_FOOTWAY:
            continue
        if hw == "steps":
            continue
        pts = [((g["lon"] - lo0) * M_LON * cos0, (g["lat"] - la0) * M_LAT) for g in el["geometry"]]
        if len(pts) < 2:
            continue
        pts = densify(pts, 20.0)
        inside = [corridor.near(x, y) for x, y in pts]
        i = 0
        while i < len(pts):
            if not inside[i]:
                i += 1
                continue
            j = i
            while j + 1 < len(pts) and inside[j + 1]:
                j += 1
            a, b = max(0, i - 1), min(len(pts) - 1, j + 1)   # extend by one point to reach the edge
            run = round_points(simplify(pts[a:b + 1], 3.0))
            if len(run) >= 2:
                pieces.append((cat, run))
            i = j + 1
    return pieces


def split_into_tiles(pieces):
    """Puts each street into the tiles it crosses (a segment straddling two tiles goes into both)."""
    def cell(p):
        return (p[0] // TILE, p[1] // TILE)

    tiles = {}
    for cat, run in pieces:
        run = round_points(densify(run, TILE / 2))
        open_lines = {}
        for p, q in zip(run, run[1:]):
            for c in {cell(p), cell(q)}:
                line = open_lines.get(c)
                if line is not None and line[-1] == p:
                    line.append(q)
                else:
                    line = [p, q]
                    open_lines[c] = line
                    tiles.setdefault(c, []).append((cat, line))
            for c in list(open_lines):
                if c not in (cell(p), cell(q)):
                    del open_lines[c]
    return tiles


def clip_segment(ax, ay, bx, by, x0, y0, x1, y1):
    """Clips the segment to the rectangle (Liang-Barsky). Returns None if it is outside."""
    t0, t1 = 0.0, 1.0
    dx, dy = bx - ax, by - ay
    for p, q in ((-dx, ax - x0), (dx, x1 - ax), (-dy, ay - y0), (dy, y1 - ay)):
        if p == 0:
            if q < 0:
                return None
        else:
            r = q / p
            if p < 0:
                if r > t1:
                    return None
                t0 = max(t0, r)
            else:
                if r < t0:
                    return None
                t1 = min(t1, r)
    return (ax + t0 * dx, ay + t0 * dy), (ax + t1 * dx, ay + t1 * dy)


def encode_tile(c, lines):
    """Bytes: for each line [point count, category], then x, y on 2 bytes (m from the corner)."""
    ox, oy = c[0] * TILE, c[1] * TILE
    out = bytearray()

    def q(p):
        return (min(TILE, max(0, int(round(p[0] - ox)))),
                min(TILE, max(0, int(round(p[1] - oy)))))

    for cat, line in lines:
        parts, cur = [], []
        for a, b in zip(line, line[1:]):
            seg = clip_segment(a[0], a[1], b[0], b[1], ox, oy, ox + TILE, oy + TILE)
            if seg is None:
                if len(cur) >= 2:
                    parts.append(cur)
                cur = []
                continue
            pa, pb = q(seg[0]), q(seg[1])
            if cur and cur[-1] == pa:
                if pb != pa:
                    cur.append(pb)
            else:
                if len(cur) >= 2:
                    parts.append(cur)
                cur = [pa, pb] if pb != pa else []
        if len(cur) >= 2:
            parts.append(cur)
        for m in parts:
            m = simplify(m, 2.0) if len(m) > 2 else m   # 1 pixel = 2 m at 200 m zoom
            for start in range(0, len(m) - 1, 254):
                part = m[start:start + 255]
                out += bytes((len(part), cat))
                for x, y in part:
                    out += bytes((x >> 8, x & 255, y >> 8, y & 255))
    return bytes(out)


# ---------------------------------------------------------------- generation

def tile_key(c):
    return (c[0] + 5000) * 10000 + (c[1] + 5000)


CHUNK_MAX = 4000    # base64 characters per chunk: the watch loads one at a time
BLOCK = 32          # points per block (same as RouteMap.mc)


def three_bytes(v):
    u = v & 0xFFFFFF
    return bytes(((u >> 16) & 255, (u >> 8) & 255, u & 255))


def route_binary(route):
    """Ready-to-use route for the watch: nothing to compute at startup.

    Points: x, y (m) and cumulative distance (m), 3 signed bytes each.
    Blocks of BLOCK points: bounding box x min, x max, y min, y max.
    """
    pts = route["ints"]
    n = len(pts)
    rec = bytearray()
    total = 0.0
    for i, (x, y) in enumerate(pts):
        if i > 0:
            total += math.hypot(x - pts[i - 1][0], y - pts[i - 1][1])
        rec += three_bytes(x) + three_bytes(y) + three_bytes(int(round(total)))
    blocks = bytearray()
    nb = (n - 2) // BLOCK + 1
    for b in range(nb):
        seg = pts[b * BLOCK: min(b * BLOCK + BLOCK, n - 1) + 1]
        xs = [p[0] for p in seg]
        ys = [p[1] for p in seg]
        blocks += three_bytes(min(xs)) + three_bytes(max(xs)) + three_bytes(min(ys)) + three_bytes(max(ys))
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys), 50)
    return [route["lat0e6"], route["lon0e6"], n, round(total, 1),
            (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, span,
            base64.b64encode(bytes(rec)).decode("ascii"),
            base64.b64encode(bytes(blocks)).decode("ascii")]


def write_pack(route, tiles, name):
    """Groups the tiles into a few large chunks (jsonData resources).

    On first launch, the watch copies each tile into its internal storage
    (Application.Storage, key "t" + tile number). During the run it reads
    the needed tile directly: no per-tile table takes up working memory.
    """
    PACK_RES.mkdir(parents=True, exist_ok=True)
    for f in PACK_RES.glob("*"):
        f.unlink()

    chunks, cur, size = [], [], 0
    count = 0
    for c, lines in sorted(tiles.items()):
        data = encode_tile(c, lines)
        if not data:
            continue
        text = base64.b64encode(data).decode("ascii")
        if cur and size + len(text) > CHUNK_MAX:
            chunks.append(cur)
            cur, size = [], 0
        cur += [tile_key(c), text]
        size += len(text)
        count += 1
    if cur:
        chunks.append(cur)

    xml_lines = ["<resources>",
                 f'    <jsonData id="RouteBin">{json.dumps(route_binary(route), separators=(",", ":"))}</jsonData>']
    for i, chunk in enumerate(chunks):
        xml_lines.append(f'    <jsonData id="C{i}">{json.dumps(chunk, separators=(",", ":"))}</jsonData>')
    xml_lines.append("</resources>")
    xml = "\n".join(xml_lines) + "\n"
    (PACK_RES / "route_pack.xml").write_text(xml, encoding="utf-8")

    pack_id = hashlib.sha1(xml.encode()).hexdigest()[:10]
    ids = ", ".join(f"Rez.JsonData.C{i}" for i in range(len(chunks)))
    mc_name = name.replace("\\", "").replace('"', "'")
    mc = f'''import Toybox.Lang;
import Toybox.WatchUi;

// GENERATED by tools/prepare_route.py: do not edit by hand.
// Route: {mc_name}
module RoutePack {{
    const HAS_MAP = true;
    const NAME = "{mc_name}";
    const PACK_ID = "{pack_id}";
    const LAT0 = {route["lat0e6"]};
    const LON0 = {route["lon0e6"]};
    const TILE = {TILE};
    const CHUNKS = {len(chunks)};

    // Precomputed route: see route_binary() in prepare_route.py
    function routeBin() {{
        return WatchUi.loadResource(Rez.JsonData.RouteBin);
    }}

    // Chunk i: [tile number, base64 text, number, text, ...]
    function chunk(i) {{
        var ids = [{ids}];
        return WatchUi.loadResource(ids[i]);
    }}
}}
'''
    PACK_MC.write_text(mc, encoding="utf-8")
    return count, len(chunks)


def write_empty_pack():
    if PACK_RES.exists():
        for f in PACK_RES.glob("*"):
            f.unlink()
        PACK_RES.rmdir()
    PACK_MC.write_text('''import Toybox.Lang;

// Version without a map: no built-in route or streets.
// This file is replaced by tools/prepare_route.py when a route is prepared.
module RoutePack {
    const HAS_MAP = false;
    const NAME = "";
    const PACK_ID = "";
    const LAT0 = 0;
    const LON0 = 0;
    const TILE = 500;
    const CHUNKS = 0;

    function routeBin() {
        return null;
    }

    function chunk(i) {
        return null;
    }
}
''', encoding="utf-8")


# ---------------------------------------------------------------- build

def find_sdk():
    cfg = Path(os.environ.get("APPDATA", "")) / "Garmin" / "ConnectIQ" / "current-sdk.cfg"
    if not cfg.exists():
        stop("Connect IQ SDK not found. Install it with Garmin's SDK Manager.")
    sdk = Path(cfg.read_text(encoding="utf-8").strip())
    monkeyc = sdk / "bin" / ("monkeyc.bat" if os.name == "nt" else "monkeyc")
    if not monkeyc.exists():
        stop(f"monkeyc not found in {sdk}")
    return monkeyc


def find_key(key_arg):
    if key_arg:
        return key_arg
    vs = Path(os.environ.get("APPDATA", "")) / "Code" / "User" / "settings.json"
    if vs.exists():
        m = re.search(r'"monkeyC\.developerKeyPath"\s*:\s*"([^"]+)"', vs.read_text(encoding="utf-8", errors="ignore"))
        if m:
            return m.group(1).replace("\\\\", "\\")
    stop("developer key not found: pass it with --key path\\developer_key")


def build(key_arg):
    monkeyc = find_sdk()
    key = find_key(key_arg)
    PRG.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(monkeyc), "-f", str(ROOT / "monkey.jungle"), "-d", "fr55", "-o", str(PRG), "-y", key]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = (r.stdout or "") + (r.stderr or "")
    errors = [l for l in output.splitlines() if "ERROR" in l]
    if r.returncode != 0 or "BUILD SUCCESSFUL" not in output:
        print(output)
        stop("the build failed (see the messages above).")
    for l in errors:
        print(l)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Prepares a route with the surrounding streets for the Forerunner 55.")
    ap.add_argument("gpx", nargs="?", help="GPX file of the route")
    ap.add_argument("--width", type=int, default=300, help="keep streets within X m of the route (default 300)")
    ap.add_argument("--points", type=int, default=0, help="max number of route points (default: 60 per km, between 800 and 4000)")
    ap.add_argument("--reverse", action="store_true", help="run the GPX in the opposite direction")
    ap.add_argument("--flip-start", action="store_true",
                    help="out-and-back: start from the other end (the old start becomes the turnaround)")
    ap.add_argument("--name", help="route name (default: file name)")
    ap.add_argument("--no-map", action="store_true", help="go back to the version without a built-in route or streets")
    ap.add_argument("--no-build", action="store_true", help="generate the files without building")
    ap.add_argument("--key", help="developer key path (default: the one set in VS Code)")
    a = ap.parse_args()

    if a.no_map:
        write_empty_pack()
        info("Version without a map restored.")
        if not a.no_build:
            build(a.key)
            info(f"App built: {PRG}")
        return

    if not a.gpx:
        ap.error("give the GPX file, for example: python tools/prepare_route.py my_route.gpx")

    info(f"1/4  Reading {a.gpx}")
    pts = read_gpx(a.gpx)
    if a.flip_start:
        pts = flip_start(pts)
    if a.reverse:
        pts.reverse()
    if a.points <= 0:
        length = sum(math.hypot((pts[i][1] - pts[i - 1][1]) * M_LON * math.cos(math.radians(pts[0][0])),
                                (pts[i][0] - pts[i - 1][0]) * M_LAT) for i in range(1, len(pts)))
        a.points = int(min(4000, max(800, length / 1000 * 60)))
    route = prepare_track(pts, min(a.points, 4000))
    info(f"     {len(pts)} points read, {len(route['ints'])} kept, {route['dist'] / 1000:.2f} km")

    info("2/4  OpenStreetMap streets around the route")
    margin = a.width + 100
    lats = [p[0] for p in pts]
    lons = [p[1] for p in pts]
    dlat = margin / M_LAT
    dlon = margin / (M_LON * route["cos0"])
    osm = download_streets((min(lats) - dlat, min(lons) - dlon, max(lats) + dlat, max(lons) + dlon))
    info(f"     {len(osm.get('elements', []))} streets and paths received")

    info(f"3/4  Keeping streets within {a.width} m and splitting into {TILE} m tiles")
    pieces = prepare_streets(osm, route, a.width)
    tiles = split_into_tiles(pieces)
    name = a.name or Path(a.gpx).stem
    n, chunk_count = write_pack(route, tiles, name)
    sizes = [len(encode_tile(c, l)) for c, l in tiles.items()]
    total = sum(sizes)
    info(f"     {len(pieces)} streets, paths and waterways, {n} tiles in {chunk_count} chunks, "
         f"{total / 1024:.0f} KB in total, largest tile {max(sizes, default=0) / 1024:.1f} KB")
    if total > 400 * 1024:
        info("     WARNING: a lot of streets for the watch storage. "
             "If some are missing, run again with --width 200.")

    if a.no_build:
        info("4/4  Build skipped (--no-build)")
        return
    info("4/4  Building the app")
    build(a.key)
    info(f"\nDone: {PRG} ({PRG.stat().st_size / 1024:.0f} KB)")
    info("Copy this file to the GARMIN\\APPS folder of the watch (see README.md),")
    info("or run: powershell -ExecutionPolicy Bypass -File tools\\install_watch.ps1")


if __name__ == "__main__":
    main()
