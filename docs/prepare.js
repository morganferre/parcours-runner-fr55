// Route preparation for the Parcours Runner watch app, in the browser.
// Same steps and same output as tools/prepare_route.py (keep both in sync):
// GPX points -> simplified route -> OpenStreetMap streets around it -> 500 m tiles
// -> gist files that the watch downloads (Routes > Download).
// Also loaded by tools/debug/compare_prepare.js (Node) to check it against the Python script.
"use strict";

(function (exports) {

  // Must stay identical to the watch code (source/route/Route.mc) and prepare_route.py.
  const M_LAT = 110574.0;
  const M_LON = 111320.0;
  const TILE = 500;
  const BLOCK = 32;            // points per block (Route.mc)
  const CHUNK_MAX = 4000;      // base64 characters per chunk of tiles
  const FILE_MAX = 8000;       // characters per downloaded file
  const POINTS_PART = 6000;    // base64 characters per part of the points (multiple of 4)
  const LINE_MAX = 63;         // points per line: the count shares its byte with the category

  const OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
  ];

  // Categories drawn on the watch (StreetLayer.mc)
  const CAT_STREET = 0, CAT_MAIN_ROAD = 1, CAT_PATH = 2, CAT_WATER = 3;
  const PATHS = new Set(["footway", "path", "track", "bridleway", "cycleway", "pedestrian"]);
  const WATERWAYS = new Set(["river", "stream", "canal"]);
  const MAIN_ROADS = new Set(["motorway", "trunk", "primary", "secondary", "tertiary",
    "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"]);
  const IGNORED = new Set(["proposed", "construction", "platform", "corridor", "elevator", "bus_stop",
    "raceway", "abandoned", "razed", "disused", "services", "rest_area"]);
  const IGNORED_SERVICE = new Set(["driveway", "parking_aisle", "drive-through", "emergency_access"]);
  const IGNORED_FOOTWAY = new Set(["sidewalk", "crossing", "traffic_island"]);

  // Python's round(): halves go to the even number (keeps the output identical to the script).
  function pyRound(x) {
    const f = Math.floor(x);
    const d = x - f;
    if (d > 0.5) return f + 1;
    if (d < 0.5) return f;
    return f % 2 === 0 ? f : f + 1;
  }

  // ---------------------------------------------------------------- GPX

  // [[lat, lon], ...] of the first track found (trkpt, otherwise rtept, otherwise wpt).
  function readGpx(text) {
    for (const tag of ["trkpt", "rtept", "wpt"]) {
      const re = new RegExp("<(?:\\w+:)?" + tag + "\\b([^>]*)>", "g");
      const pts = [];
      let m;
      while ((m = re.exec(text)) !== null) {
        const lat = /\blat\s*=\s*["']([^"']+)["']/.exec(m[1]);
        const lon = /\blon\s*=\s*["']([^"']+)["']/.exec(m[1]);
        if (lat && lon && isFinite(+lat[1]) && isFinite(+lon[1])) pts.push([+lat[1], +lon[1]]);
      }
      if (pts.length >= 2) return pts;
    }
    throw new Error("no track found in this GPX");
  }

  function toGpx(pts, name) {
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    return '<?xml version="1.0" encoding="UTF-8"?>\n' +
      '<gpx version="1.1" creator="Parcours Runner" xmlns="http://www.topografix.com/GPX/1/1">\n' +
      "<trk><name>" + esc(name) + "</name><trkseg>\n" +
      pts.map((p) => '<trkpt lat="' + p[0].toFixed(6) + '" lon="' + p[1].toFixed(6) + '"/>').join("\n") +
      "\n</trkseg></trk>\n</gpx>\n";
  }

  function lengthOf(pts) {
    const c = Math.cos(pts[0][0] * Math.PI / 180);
    let s = 0;
    for (let i = 1; i < pts.length; i++) {
      s += Math.hypot((pts[i][1] - pts[i - 1][1]) * M_LON * c, (pts[i][0] - pts[i - 1][0]) * M_LAT);
    }
    return s;
  }

  // ---------------------------------------------------------------- geometry

  // Iterative Douglas-Peucker (point-to-segment distance).
  function simplify(p, eps) {
    const n = p.length;
    if (n < 3) return p.slice();
    const keep = new Array(n).fill(false);
    keep[0] = keep[n - 1] = true;
    const stack = [[0, n - 1]];
    while (stack.length) {
      const [a, b] = stack.pop();
      const ax = p[a][0], ay = p[a][1];
      const vx = p[b][0] - ax, vy = p[b][1] - ay;
      const l2 = vx * vx + vy * vy;
      let md = 0, mi = -1;
      for (let i = a + 1; i < b; i++) {
        let t = l2 ? ((p[i][0] - ax) * vx + (p[i][1] - ay) * vy) / l2 : 0;
        t = Math.max(0, Math.min(1, t));
        const dx = p[i][0] - ax - t * vx, dy = p[i][1] - ay - t * vy;
        const d = dx * dx + dy * dy;
        if (d > md) { md = d; mi = i; }
      }
      if (mi >= 0 && md > eps * eps) {
        keep[mi] = true;
        stack.push([a, mi], [mi, b]);
      }
    }
    return p.filter((q, i) => keep[i]);
  }

  function roundPoints(points) {
    const out = [];
    for (const [x, y] of points) {
      const q = [pyRound(x), pyRound(y)];
      const last = out[out.length - 1];
      if (!last || last[0] !== q[0] || last[1] !== q[1]) out.push(q);
    }
    return out;
  }

  // Adds points on long segments so that clipping to the corridor is accurate.
  function densify(pts, step) {
    const out = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
      const [ax, ay] = pts[i - 1], [bx, by] = pts[i];
      const L = Math.hypot(bx - ax, by - ay);
      const k = Math.floor(L / step);
      for (let j = 1; j <= k; j++) {
        const t = j / (k + 1);
        out.push([ax + (bx - ax) * t, ay + (by - ay) * t]);
      }
      out.push([bx, by]);
    }
    return out;
  }

  // ---------------------------------------------------------------- route

  function prepareTrack(pts, maxPts) {
    const lat0e6 = pyRound(pts[0][0] * 1e6), lon0e6 = pyRound(pts[0][1] * 1e6);
    const la0 = lat0e6 / 1e6, lo0 = lon0e6 / 1e6;
    const cos0 = Math.cos(la0 * Math.PI / 180);
    const xy = pts.map(([la, lo]) => [(lo - lo0) * M_LON * cos0, (la - la0) * M_LAT]);
    let eps = 2.0, ints;
    for (;;) {
      ints = roundPoints(simplify(xy, eps));
      if (ints.length <= maxPts) break;
      eps *= 1.25;
    }
    let dist = 0;
    for (let i = 1; i < ints.length; i++) dist += Math.hypot(ints[i][0] - ints[i - 1][0], ints[i][1] - ints[i - 1][1]);
    return { ints, dist, lat0e6, lon0e6, la0, lo0, cos0 };
  }

  function defaultMaxPoints(pts) {
    return Math.floor(Math.min(4000, Math.max(800, lengthOf(pts) / 1000 * 60)));
  }

  function threeBytes(out, v) {
    const u = v & 0xFFFFFF;
    out.push((u >> 16) & 255, (u >> 8) & 255, u & 255);
  }

  function base64(bytes) {
    let s = "";
    for (let i = 0; i < bytes.length; i += 8192) s += String.fromCharCode.apply(null, bytes.slice(i, i + 8192));
    return btoa(s);
  }

  // Ready-to-use route for the watch: points (x, y, cumulative distance, 3 bytes each)
  // and bounding boxes per block of BLOCK points.
  function routeBinary(route) {
    const pts = route.ints, n = pts.length;
    const rec = [];
    let total = 0;
    for (let i = 0; i < n; i++) {
      if (i > 0) total += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
      threeBytes(rec, pts[i][0]);
      threeBytes(rec, pts[i][1]);
      threeBytes(rec, pyRound(total));
    }
    const blocks = [];
    const nb = Math.floor((n - 2) / BLOCK) + 1;
    for (let b = 0; b < nb; b++) {
      const seg = pts.slice(b * BLOCK, Math.min(b * BLOCK + BLOCK, n - 1) + 1);
      const xs = seg.map((p) => p[0]), ys = seg.map((p) => p[1]);
      threeBytes(blocks, Math.min(...xs));
      threeBytes(blocks, Math.max(...xs));
      threeBytes(blocks, Math.min(...ys));
      threeBytes(blocks, Math.max(...ys));
    }
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
    const span = Math.max(maxX - minX, maxY - minY, 50);
    return [route.lat0e6, route.lon0e6, n, Math.round(total * 10) / 10,
      (minX + maxX) / 2, (minY + maxY) / 2, span, base64(rec), base64(blocks)];
  }

  // ---------------------------------------------------------------- OpenStreetMap

  function overpassQuery(bbox) {
    const [s, w, n, e] = bbox.map((v) => v.toFixed(6));
    const ignored = [...IGNORED].sort().join("|");
    const bb = "(" + s + "," + w + "," + n + "," + e + ")";
    return "[out:json][timeout:180];(" +
      'way["highway"]["highway"!~"^(' + ignored + ')$"]["area"!="yes"]' + bb + ";" +
      'way["waterway"~"^(river|stream|canal)$"]' + bb + ";" +
      'way["natural"="water"]' + bb + ";" +
      ");out geom;";
  }

  function streetsBbox(pts, route, width) {
    const margin = width + 100;
    const lats = pts.map((p) => p[0]), lons = pts.map((p) => p[1]);
    const dlat = margin / M_LAT, dlon = margin / (M_LON * route.cos0);
    return [Math.min(...lats) - dlat, Math.min(...lons) - dlon, Math.max(...lats) + dlat, Math.max(...lons) + dlon];
  }

  // Tries each Overpass server in turn. log(message) shows the progress.
  async function downloadStreets(bbox, log) {
    const body = "data=" + encodeURIComponent(overpassQuery(bbox));
    let last = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      for (const url of OVERPASS) {
        try {
          log && log("server " + new URL(url).host + "...");
          const r = await fetch(url, { method: "POST", body,
            headers: { "Content-Type": "application/x-www-form-urlencoded" } });
          if (!r.ok) throw new Error("HTTP " + r.status);
          return await r.json();
        } catch (e) {
          last = e;
        }
      }
      await new Promise((ok) => setTimeout(ok, 5000));
    }
    throw new Error("OpenStreetMap unavailable (" + (last && last.message) + "), try again in a few minutes");
  }

  // Fast distance to the route using a grid of 100 m cells.
  class Corridor {
    constructor(ints, width) {
      this.c = 100.0;
      this.width = width;
      this.cells = new Map();
      const r = Math.ceil(width / this.c) + 1;
      for (let i = 0; i < ints.length - 1; i++) {
        const [ax, ay] = ints[i], [bx, by] = ints[i + 1];
        const x0 = Math.min(ax, bx), x1 = Math.max(ax, bx), y0 = Math.min(ay, by), y1 = Math.max(ay, by);
        for (let cx = Math.floor(x0 / this.c) - r; cx <= Math.floor(x1 / this.c) + r; cx++) {
          for (let cy = Math.floor(y0 / this.c) - r; cy <= Math.floor(y1 / this.c) + r; cy++) {
            const k = cx + "," + cy;
            if (!this.cells.has(k)) this.cells.set(k, []);
            this.cells.get(k).push([ax, ay, bx, by]);
          }
        }
      }
    }

    near(x, y) {
      const segs = this.cells.get(Math.floor(x / this.c) + "," + Math.floor(y / this.c));
      if (!segs) return false;
      const l2max = this.width * this.width;
      for (const [ax, ay, bx, by] of segs) {
        const vx = bx - ax, vy = by - ay;
        const l2 = vx * vx + vy * vy;
        let t = l2 ? ((x - ax) * vx + (y - ay) * vy) / l2 : 0;
        t = Math.max(0, Math.min(1, t));
        const dx = x - ax - t * vx, dy = y - ay - t * vy;
        if (dx * dx + dy * dy <= l2max) return true;
      }
      return false;
    }
  }

  function prepareStreets(osm, route, width) {
    const corridor = new Corridor(route.ints, width);
    const { la0, lo0, cos0 } = route;
    const pieces = [];
    for (const el of osm.elements || []) {
      if (el.type !== "way" || !el.geometry) continue;
      const tags = el.tags || {};
      const hw = tags.highway || "";
      let cat;
      if (WATERWAYS.has(tags.waterway) || tags.natural === "water") cat = CAT_WATER;
      else if (MAIN_ROADS.has(hw)) cat = CAT_MAIN_ROAD;
      else if (PATHS.has(hw)) cat = CAT_PATH;
      else cat = CAT_STREET;
      if (IGNORED.has(hw)) continue;
      if (hw === "service" && IGNORED_SERVICE.has(tags.service)) continue;
      if ((hw === "footway" || hw === "path") && IGNORED_FOOTWAY.has(tags.footway)) continue;
      if (hw === "steps") continue;
      let pts = el.geometry.map((g) => [(g.lon - lo0) * M_LON * cos0, (g.lat - la0) * M_LAT]);
      if (pts.length < 2) continue;
      pts = densify(pts, 20.0);
      const inside = pts.map(([x, y]) => corridor.near(x, y));
      let i = 0;
      while (i < pts.length) {
        if (!inside[i]) { i++; continue; }
        let j = i;
        while (j + 1 < pts.length && inside[j + 1]) j++;
        const a = Math.max(0, i - 1), b = Math.min(pts.length - 1, j + 1);   // reach the edge
        const run = roundPoints(simplify(pts.slice(a, b + 1), 3.0));
        if (run.length >= 2) pieces.push([cat, run]);
        i = j + 1;
      }
    }
    return pieces;
  }

  // Each street goes into the tiles it crosses (a segment straddling two tiles goes into both).
  function splitIntoTiles(pieces) {
    const cell = (p) => [Math.floor(p[0] / TILE), Math.floor(p[1] / TILE)];
    const key = (c) => c[0] + "," + c[1];
    const tiles = new Map();
    for (const [cat, run0] of pieces) {
      const run = roundPoints(densify(run0, TILE / 2));
      const open = new Map();
      for (let s = 1; s < run.length; s++) {
        const p = run[s - 1], q = run[s];
        const cp = cell(p), cq = cell(q);
        const cs = key(cp) === key(cq) ? [cp] : [cp, cq];
        for (const c of cs) {
          const k = key(c);
          let line = open.get(k);
          if (line && line[line.length - 1][0] === p[0] && line[line.length - 1][1] === p[1]) {
            line.push(q);
          } else {
            line = [p, q];
            open.set(k, line);
            if (!tiles.has(k)) tiles.set(k, { c, lines: [] });
            tiles.get(k).lines.push([cat, line]);
          }
        }
        for (const k of [...open.keys()]) {
          if (k !== key(cp) && k !== key(cq)) open.delete(k);
        }
      }
    }
    return tiles;
  }

  // Clips the segment to the rectangle (Liang-Barsky). null if it is outside.
  function clipSegment(ax, ay, bx, by, x0, y0, x1, y1) {
    let t0 = 0, t1 = 1;
    const dx = bx - ax, dy = by - ay;
    for (const [p, q] of [[-dx, ax - x0], [dx, x1 - ax], [-dy, ay - y0], [dy, y1 - ay]]) {
      if (p === 0) {
        if (q < 0) return null;
      } else {
        const r = q / p;
        if (p < 0) {
          if (r > t1) return null;
          t0 = Math.max(t0, r);
        } else {
          if (r < t0) return null;
          t1 = Math.min(t1, r);
        }
      }
    }
    return [[ax + t0 * dx, ay + t0 * dy], [ax + t1 * dx, ay + t1 * dy]];
  }

  // Signed step in m: 1 byte from -64 to 63, otherwise 2 bytes (StreetLayer.mc decodes it).
  function varint(out, d) {
    if (d >= -64 && d <= 63) { out.push(d + 64); return; }
    const u = d + 16384;
    out.push(0x80 | (u >> 8), u & 255);
  }

  // For each line one byte (category << 6 | point count), then each point x, y (m from the
  // corner) as a step from the previous point, the first one from the end of the previous line.
  function encodeTile(c, lines) {
    const ox = c[0] * TILE, oy = c[1] * TILE;
    const out = [];
    let last = [0, 0];
    const q = (p) => [Math.min(TILE, Math.max(0, pyRound(p[0] - ox))), Math.min(TILE, Math.max(0, pyRound(p[1] - oy)))];
    for (const [cat, line] of lines) {
      const parts = [];
      let cur = [];
      for (let s = 1; s < line.length; s++) {
        const a = line[s - 1], b = line[s];
        const seg = clipSegment(a[0], a[1], b[0], b[1], ox, oy, ox + TILE, oy + TILE);
        if (!seg) {
          if (cur.length >= 2) parts.push(cur);
          cur = [];
          continue;
        }
        const pa = q(seg[0]), pb = q(seg[1]);
        const same = (u, v) => u[0] === v[0] && u[1] === v[1];
        if (cur.length && same(cur[cur.length - 1], pa)) {
          if (!same(pb, pa)) cur.push(pb);
        } else {
          if (cur.length >= 2) parts.push(cur);
          cur = same(pb, pa) ? [] : [pa, pb];
        }
      }
      if (cur.length >= 2) parts.push(cur);
      for (let m of parts) {
        m = m.length > 2 ? simplify(m, 2.0) : m;     // 1 pixel = 2 m at 200 m zoom
        for (let start = 0; start < m.length - 1; start += LINE_MAX - 1) {
          const part = m.slice(start, start + LINE_MAX);
          out.push((cat << 6) | part.length);
          for (const [x, y] of part) {
            varint(out, x - last[0]);
            varint(out, y - last[1]);
            last = [x, y];
          }
        }
      }
    }
    return out;
  }

  function tileKey(c) {
    return (c[0] + 5000) * 10000 + (c[1] + 5000);
  }

  // Tiles of one route grouped into chunks of at most CHUNK_MAX base64 characters.
  function tileChunks(tiles) {
    const sorted = [...tiles.values()].sort((a, b) => a.c[0] - b.c[0] || a.c[1] - b.c[1]);
    const chunks = [];
    let cur = [], size = 0;
    for (const { c, lines } of sorted) {
      const data = encodeTile(c, lines);
      if (!data.length) continue;
      const text = base64(data);
      if (cur.length && size + text.length > CHUNK_MAX) {
        chunks.push(cur);
        cur = [];
        size = 0;
      }
      cur.push(tileKey(c), text);
      size += text.length;
    }
    if (cur.length) chunks.push(cur);
    return chunks;
  }

  // ---------------------------------------------------------------- gist files

  function fmt1(v) { return (Math.round(v * 10) / 10).toFixed(1); }

  // Texts of the files <id>_<j>.txt: lines "key=value" (m meta, p<j> points, t<tile> tile).
  function routeFiles(binary, chunks) {
    const pts = binary[7];
    const parts = [];
    for (let i = 0; i < pts.length; i += POINTS_PART) parts.push(pts.slice(i, i + POINTS_PART));
    const meta = [String(binary[0]), String(binary[1]), String(binary[2]), fmt1(binary[3]),
      fmt1(binary[4]), fmt1(binary[5]), fmt1(binary[6]), String(parts.length), binary[8]].join(";");
    const entries = ["m=" + meta].concat(parts.map((t, j) => "p" + j + "=" + t));
    for (const chunk of chunks) {
      for (let k = 0; k < chunk.length; k += 2) entries.push("t" + chunk[k] + "=" + chunk[k + 1]);
    }
    const files = [];
    let cur = "";
    for (const e of entries) {
      if (cur && cur.length + e.length + 1 > FILE_MAX) {
        files.push(cur);
        cur = "";
      }
      cur += e + "\n";
    }
    if (cur) files.push(cur);
    return files;
  }

  async function sha1hex(text) {
    const d = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
    return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  // Everything for one route: GPX points -> {id, name, length, files, size, stats}.
  async function prepareRoute(pts, name, width, log) {
    const route = prepareTrack(pts, defaultMaxPoints(pts));
    log && log("route: " + route.ints.length + " points, " + (route.dist / 1000).toFixed(2) + " km");
    const osm = await downloadStreets(streetsBbox(pts, route, width), log);
    const pieces = prepareStreets(osm, route, width);
    const tiles = splitIntoTiles(pieces);
    const binary = routeBinary(route);
    const chunks = tileChunks(tiles);
    const files = routeFiles(binary, chunks);
    const id = (await sha1hex(JSON.stringify(binary) + JSON.stringify(chunks))).slice(0, 8);
    const size = files.reduce((s, t) => s + t.length, 0);
    return { id, name, length: Math.round(binary[3]), files, size,
      streets: pieces.length, tiles: tiles.size, osmWays: (osm.elements || []).length };
  }

  Object.assign(exports, {
    M_LAT, M_LON, TILE, pyRound, readGpx, toGpx, lengthOf, simplify, prepareTrack, defaultMaxPoints,
    routeBinary, overpassQuery, streetsBbox, downloadStreets, prepareStreets, splitIntoTiles,
    encodeTile, tileChunks, routeFiles, prepareRoute,
  });
})(typeof module !== "undefined" ? module.exports : (window.Prepare = {}));
