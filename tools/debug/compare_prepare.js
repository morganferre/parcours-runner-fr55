// Checks that the website (docs/prepare.js) prepares a route exactly like tools/prepare_route.py.
// Usage (from the project folder, after prepare_route.py has cached the streets of the GPX):
//   python tools/debug/compare_prepare.py tools/my_route.gpx > py.json
//   node tools/debug/compare_prepare.js tools/my_route.gpx py.json
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const P = require("../../docs/prepare.js");

const [gpx, pyJson] = process.argv.slice(2);
const width = 300;
const pts = P.readGpx(fs.readFileSync(gpx, "utf8"));
const route = P.prepareTrack(pts, P.defaultMaxPoints(pts));
const query = P.overpassQuery(P.streetsBbox(pts, route, width));
const cache = path.join(__dirname, "..", "cache",
  "osm_" + crypto.createHash("sha1").update(query).digest("hex").slice(0, 16) + ".json");
if (!fs.existsSync(cache)) {
  console.log("streets not in the cache (run prepare_route.py on this GPX first): " + cache);
  process.exit(2);
}
const osm = JSON.parse(fs.readFileSync(cache, "utf8"));
const files = P.routeFiles(P.routeBinary(route), P.tileChunks(P.splitIntoTiles(P.prepareStreets(osm, route, width))));
const py = JSON.parse(fs.readFileSync(pyJson, "utf8"));

let same = files.length === py.length;
for (let i = 0; i < Math.max(files.length, py.length); i++) {
  if (files[i] !== py[i]) {
    same = false;
    const a = files[i] || "", b = py[i] || "";
    let k = 0;
    while (k < a.length && a[k] === b[k]) k++;
    console.log("file " + i + " differs at character " + k + ":\n  js: " + a.slice(Math.max(0, k - 40), k + 60) +
      "\n  py: " + b.slice(Math.max(0, k - 40), k + 60));
  }
}
console.log(same ? "IDENTICAL: " + files.length + " files, " + files.reduce((s, t) => s + t.length, 0) + " characters"
  : "DIFFERENT");
process.exit(same ? 0 : 1);
