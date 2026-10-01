// Parcours Runner website: draw or import a route, add the streets, send it to the watch.
// The route preparation itself is in prepare.js (same output as tools/prepare_route.py).
// The routes go to a secret GitHub gist that the watch downloads (Routes > Download).
"use strict";

const GIST_DESCRIPTION = "Parcours Runner - routes for the watch";   // same as prepare_route.py
const CAPACITY_KB = 110;                                             // watch storage for the routes

// ---------------------------------------------------------------- texts

const TEXTS = {
  en: {
    tagline: "Draw your route, add the streets around it and send it to your Forerunner 55.",
    s1: "Route", foot: "On foot", bike: "Cycling", straight: "Straight lines",
    undo: "Undo", loop: "Back to start", clear: "Clear", locate: "Locate me",
    import: "Import a GPX", export: "Save as GPX",
    drawHelp: "tap the map to add points: the route follows the streets and paths.",
    s2: "Streets", namePh: "Route name", widthHelp: "Streets kept on each side of the route. Less = lighter and faster to send.",
    prepare: "Prepare the streets",
    s3: "Send to the watch",
    tokenHelp: "The routes go to a secret gist of your GitHub account, read by the watch through the phone. The key stays in this browser.",
    tokenLink: "Create a GitHub key with the \"gist\" right only", tokenPaste: "Paste it here:",
    connect: "Connect", gistIs: "Secret gist:", logout: "forget the key", send: "Send to the watch",
    online: "Routes online", del: "Delete", s4: "On the watch",
    watch1: "Phone nearby, Garmin Connect open.",
    watch2: "Parcours Runner › Routes › Download..., then choose the route (about 1 KB per second).",
    watch3: "Choose it in the Routes menu, then Running or Cycling: go!",
    firstTime: "First time?",
    firstTimeText: "The app must be installed once on the watch with the cable, from a PC (see the README). If the gist was just created here, rebuild the app once with tools/prepare_route.py so that it knows the gist (put its address in tools/gist.txt).",
    readme: "Project and installation (README)",
    credits: "Map and streets © OpenStreetMap contributors (ODbL). Routing: BRouter.",
    needRoute: "Draw or import a route first.", preparing: "Preparing...",
    streetsOk: "{streets} streets in {tiles} tiles: {kb} KB, about {s} s to download on the watch.",
    tooBig: "Heavy for the watch (about {cap} KB in all): try 200 m.",
    noGist: "No gist yet.", createGist: "Create the gist", sending: "Sending...",
    sent: "Sent! On the watch: Routes › Download... (the list can take a few minutes to refresh).",
    deleted: "Deleted.", confirmDelete: "Delete \"{name}\" from the online list?",
    badToken: "GitHub refused the key ({code}). Check that it has the \"gist\" right.",
    routingErr: "Routing unavailable ({msg}): straight line used.",
    gpxErr: "Cannot read this GPX: {msg}", none: "No route online.", replace: "replaces the route with the same name",
  },
  fr: {
    tagline: "Dessinez votre parcours, ajoutez les rues autour et envoyez-le sur votre Forerunner 55.",
    s1: "Parcours", foot: "À pied", bike: "Vélo", straight: "Lignes droites",
    undo: "Annuler", loop: "Retour au départ", clear: "Effacer", locate: "Me localiser",
    import: "Importer un GPX", export: "Enregistrer en GPX",
    drawHelp: "touchez la carte pour poser des points : le tracé suit les rues et les chemins.",
    s2: "Rues", namePh: "Nom du parcours", widthHelp: "Rues gardées de chaque côté du parcours. Moins = plus léger et plus rapide à envoyer.",
    prepare: "Préparer les rues",
    s3: "Envoyer vers la montre",
    tokenHelp: "Les parcours vont dans un gist secret de votre compte GitHub, que la montre lit via le téléphone. La clé reste dans ce navigateur.",
    tokenLink: "Créer une clé GitHub avec seulement le droit « gist »", tokenPaste: "La coller ici :",
    connect: "Connecter", gistIs: "Gist secret :", logout: "oublier la clé", send: "Envoyer vers la montre",
    online: "Parcours en ligne", del: "Supprimer", s4: "Sur la montre",
    watch1: "Téléphone à côté, Garmin Connect ouvert.",
    watch2: "Parcours Runner › Parcours › Télécharger..., puis choisir le parcours (environ 1 Ko par seconde).",
    watch3: "Le choisir dans le menu Parcours, puis Course à pied ou Vélo : c'est parti !",
    firstTime: "Première fois ?",
    firstTimeText: "L'appli doit être installée une fois sur la montre avec le câble, depuis un PC (voir le README). Si le gist vient d'être créé ici, recompilez l'appli une fois avec tools/prepare_route.py pour qu'elle le connaisse (mettez son adresse dans tools/gist.txt).",
    readme: "Projet et installation (README)",
    credits: "Carte et rues © les contributeurs OpenStreetMap (ODbL). Calcul d'itinéraire : BRouter.",
    needRoute: "Dessinez ou importez d'abord un parcours.", preparing: "Préparation...",
    streetsOk: "{streets} rues en {tiles} carrés : {kb} Ko, environ {s} s de téléchargement sur la montre.",
    tooBig: "Lourd pour la montre (environ {cap} Ko en tout) : essayez 200 m.",
    noGist: "Pas encore de gist.", createGist: "Créer le gist", sending: "Envoi...",
    sent: "Envoyé ! Sur la montre : Parcours › Télécharger... (la liste peut mettre quelques minutes à se rafraîchir).",
    deleted: "Supprimé.", confirmDelete: "Supprimer « {name} » de la liste en ligne ?",
    badToken: "GitHub a refusé la clé ({code}). Vérifiez qu'elle a le droit « gist ».",
    routingErr: "Calcul d'itinéraire indisponible ({msg}) : ligne droite utilisée.",
    gpxErr: "Impossible de lire ce GPX : {msg}", none: "Aucun parcours en ligne.", replace: "remplace le parcours du même nom",
  },
};
const LANG = (navigator.language || "en").toLowerCase().startsWith("fr") ? "fr" : "en";
function t(key, values) {
  let s = TEXTS[LANG][key] || TEXTS.en[key] || key;
  for (const k in values || {}) s = s.replace("{" + k + "}", values[k]);
  return s;
}
document.documentElement.lang = LANG;
document.querySelectorAll("[data-t]").forEach((el) => { el.textContent = t(el.dataset.t); });

const $ = (id) => document.getElementById(id);
let prepared = null;       // route ready to send (Prepare.prepareRoute)
let token = null;          // GitHub key, kept in this browser
let gist = null;           // {id, owner, files: names, index}
function store(key, value) {
  try {
    if (value === undefined) return localStorage.getItem(key);
    if (value === null) localStorage.removeItem(key); else localStorage.setItem(key, value);
  } catch (e) { /* private window: nothing kept */ }
  return null;
}
function show(el, text, cls) {
  el.classList.remove("hidden");
  const line = document.createElement("div");
  if (cls) line.className = cls;
  line.textContent = text;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
}

// ---------------------------------------------------------------- map and drawing

const map = L.map("map", { zoomControl: true }).setView([46.6, 2.4], 6);
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19, attribution: "© OpenStreetMap",
}).addTo(map);

// Waypoints tapped on the map, and the path between each one and the previous one.
let waypoints = [];      // [{lat, lon, marker}]
let segments = [];       // segments[i]: [[lat, lon], ...] from waypoints[i] to waypoints[i + 1]
let imported = null;     // points of an imported GPX (replaces the drawing)
const line = L.polyline([], { color: "#e0457b", weight: 5 }).addTo(map);

function track() {
  if (imported) return imported;
  if (waypoints.length === 1) return [[waypoints[0].lat, waypoints[0].lon]];
  const out = [];
  for (const s of segments) {
    for (const p of s) {
      const last = out[out.length - 1];
      if (!last || last[0] !== p[0] || last[1] !== p[1]) out.push(p);
    }
  }
  return out;
}

function refresh() {
  const pts = track();
  line.setLatLngs(pts);
  $("dist").textContent = (pts.length > 1 ? Prepare.lengthOf(pts) / 1000 : 0).toFixed(1) + " km";
  prepared = null;
  $("send").disabled = true;
}

async function routeBetween(a, b) {
  const profile = $("profile").value;
  if (profile === "straight") return [[a.lat, a.lon], [b.lat, b.lon]];
  try {
    const url = "https://brouter.de/brouter?lonlats=" + a.lon + "," + a.lat + "|" + b.lon + "," + b.lat +
      "&profile=" + profile + "&alternativeidx=0&format=geojson";
    const r = await fetch(url);
    if (!r.ok) throw new Error("HTTP " + r.status);
    const g = await r.json();
    return g.features[0].geometry.coordinates.map((c) => [c[1], c[0]]);
  } catch (e) {
    alert(t("routingErr", { msg: e.message }));
    return [[a.lat, a.lon], [b.lat, b.lon]];
  }
}

async function addPoint(lat, lon) {
  if (imported) return;
  const marker = L.circleMarker([lat, lon], { radius: 6, color: "#ffffff", weight: 2,
    fillColor: waypoints.length ? "#e0457b" : "#1f8a4c", fillOpacity: 1 }).addTo(map);
  const wp = { lat, lon, marker };
  waypoints.push(wp);
  if (waypoints.length > 1) {
    const seg = await routeBetween(waypoints[waypoints.length - 2], wp);
    if (waypoints[waypoints.length - 1] !== wp) return;     // undone meanwhile
    segments.push(seg);
  }
  refresh();
}

map.on("click", (e) => addPoint(e.latlng.lat, e.latlng.lng));

$("undo").onclick = () => {
  if (imported) { imported = null; refresh(); return; }
  const wp = waypoints.pop();
  if (!wp) return;
  map.removeLayer(wp.marker);
  if (segments.length >= waypoints.length && segments.length) segments.pop();
  refresh();
};
$("clear").onclick = () => {
  waypoints.forEach((w) => map.removeLayer(w.marker));
  waypoints = [];
  segments = [];
  imported = null;
  refresh();
};
$("loop").onclick = () => {
  if (waypoints.length > 1) addPoint(waypoints[0].lat, waypoints[0].lon);
};
$("locate").onclick = () => {
  navigator.geolocation && navigator.geolocation.getCurrentPosition(
    (p) => map.setView([p.coords.latitude, p.coords.longitude], 16),
    () => {}, { enableHighAccuracy: true, timeout: 10000 });
};

$("gpxFile").onchange = async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  try {
    const pts = Prepare.readGpx(await f.text());
    $("clear").onclick();
    imported = pts;
    if (!$("name").value) $("name").value = f.name.replace(/\.gpx$/i, "").replace(/_/g, " ");
    refresh();
    map.fitBounds(line.getBounds(), { padding: [20, 20] });
  } catch (err) {
    alert(t("gpxErr", { msg: err.message }));
  }
  e.target.value = "";
};

$("export").onclick = () => {
  const pts = track();
  if (pts.length < 2) { alert(t("needRoute")); return; }
  const name = $("name").value.trim() || "parcours";
  const blob = new Blob([Prepare.toGpx(pts, name)], { type: "application/gpx+xml" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name.replace(/[^\w\- ]+/g, "_") + ".gpx";
  a.click();
  URL.revokeObjectURL(a.href);
};

// ---------------------------------------------------------------- streets

$("name").placeholder = t("namePh");

$("prepare").onclick = async () => {
  const pts = track();
  if (pts.length < 2) { alert(t("needRoute")); return; }
  const name = ($("name").value.trim() || t("namePh")).replace(/[|\n]/g, " ");
  const log = $("prepLog");
  log.textContent = "";
  show(log, t("preparing"));
  $("prepare").disabled = true;
  try {
    prepared = await Prepare.prepareRoute(pts, name, +$("width").value, (m) => show(log, m));
    const kb = Math.ceil(prepared.size / 1024);
    show(log, t("streetsOk", { streets: prepared.streets, tiles: prepared.tiles, kb, s: Math.round(prepared.size / 1000) }), "ok");
    if (kb > 60) show(log, t("tooBig", { cap: CAPACITY_KB }), "err");
    $("send").disabled = !gist;
  } catch (e) {
    show(log, e.message, "err");
  }
  $("prepare").disabled = false;
};

// ---------------------------------------------------------------- GitHub gist


async function github(method, path, body) {
  const r = await fetch("https://api.github.com" + path, {
    method,
    headers: { Authorization: "token " + token, Accept: "application/vnd.github+json",
      ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (r.status === 401 || r.status === 403) throw new Error(t("badToken", { code: r.status }));
  if (!r.ok) throw new Error("GitHub " + r.status);
  return r.status === 204 ? null : r.json();
}

// The gist of the routes: found by its description, as created by prepare_route.py --upload.
async function findGist() {
  for (let page = 1; page <= 5; page++) {
    const list = await github("GET", "/gists?per_page=100&page=" + page);
    const g = list.find((x) => x.description === GIST_DESCRIPTION);
    if (g) return g.id;
    if (list.length < 100) break;
  }
  return null;
}

async function loadGist(id) {
  const g = await github("GET", "/gists/" + id);
  let index = "";
  const f = g.files["index.txt"];
  if (f) index = f.truncated ? await (await fetch(f.raw_url)).text() : f.content;
  gist = { id: g.id, owner: g.owner.login, files: Object.keys(g.files), index };
  $("gistLink").textContent = gist.owner + "/" + gist.id.slice(0, 8) + "…";
  $("gistLink").href = "https://gist.github.com/" + gist.owner + "/" + gist.id;
  listRoutes();
}

// index.txt: "PR1" then id|name|length m|file count|characters (see prepare_route.py).
function indexLines() {
  return gist.index.split("\n").slice(1).filter((l) => l.split("|").length >= 5);
}

function listRoutes() {
  const ul = $("routes");
  ul.textContent = "";
  const lines = indexLines();
  if (!lines.length) {
    const li = document.createElement("li");
    li.textContent = t("none");
    ul.appendChild(li);
  }
  for (const l of lines) {
    const [id, name, length, , size] = l.split("|");
    const li = document.createElement("li");
    const s = document.createElement("span");
    s.textContent = name;
    const small = document.createElement("small");
    small.textContent = (length / 1000).toFixed(1) + " km · " + Math.ceil(size / 1024) + (LANG === "fr" ? " Ko" : " KB");
    s.appendChild(small);
    const b = document.createElement("button");
    b.textContent = t("del");
    b.onclick = () => deleteRoute(id, name);
    li.append(s, b);
    ul.appendChild(li);
  }
}

async function saveGist(files, lines) {
  files["index.txt"] = { content: "PR1\n" + lines.map((l) => l + "\n").join("") };
  await github("PATCH", "/gists/" + gist.id, { files });
  await loadGist(gist.id);
}

async function deleteRoute(id, name) {
  if (!confirm(t("confirmDelete", { name }))) return;
  const files = {};
  for (const f of gist.files) if (f.startsWith(id + "_")) files[f] = null;
  try {
    await saveGist(files, indexLines().filter((l) => l.split("|")[0] !== id));
    show($("sendLog"), t("deleted"), "ok");
  } catch (e) {
    show($("sendLog"), e.message, "err");
  }
}

// Same as upload() in prepare_route.py: a route with the same name is replaced.
$("send").onclick = async () => {
  if (!prepared || !gist) return;
  const log = $("sendLog");
  show(log, t("sending"));
  $("send").disabled = true;
  try {
    let lines = indexLines();
    const old = lines.filter((l) => l.split("|")[1] === prepared.name || l.split("|")[0] === prepared.id);
    const files = {};
    for (const l of old) {
      const oid = l.split("|")[0];
      for (const f of gist.files) if (f.startsWith(oid + "_")) files[f] = null;
    }
    lines = lines.filter((l) => !old.includes(l));
    prepared.files.forEach((text, j) => { files[prepared.id + "_" + j + ".txt"] = { content: text }; });
    lines.push([prepared.id, prepared.name, prepared.length, prepared.files.length, prepared.size].join("|"));
    await saveGist(files, lines);
    show(log, t("sent"), "ok");
  } catch (e) {
    show(log, e.message, "err");
    $("send").disabled = false;
  }
};

async function connect() {
  const log = $("sendLog");
  try {
    const id = await findGist();
    $("noAccount").classList.add("hidden");
    $("account").classList.remove("hidden");
    if (id) {
      await loadGist(id);
    } else {
      $("routes").textContent = "";
      show(log, t("noGist"));
      const b = document.createElement("button");
      b.textContent = t("createGist");
      b.onclick = async () => {
        const g = await github("POST", "/gists", { description: GIST_DESCRIPTION, public: false,
          files: { "README.md": { content: "Routes for the Parcours Runner watch app. Keep this gist secret." } } });
        b.remove();
        await loadGist(g.id);
        show(log, t("firstTimeText"));
      };
      log.appendChild(b);
    }
    $("send").disabled = !prepared || !gist;
  } catch (e) {
    show(log, e.message, "err");
    $("noAccount").classList.remove("hidden");
    $("account").classList.add("hidden");
  }
}

token = store("pr_token");
$("tokenLink").href = "https://github.com/settings/tokens/new?scopes=gist&description=Parcours%20Runner";
$("connect").onclick = () => {
  token = $("token").value.trim();
  if (!token) return;
  store("pr_token", token);
  connect();
};
$("logout").onclick = (e) => {
  e.preventDefault();
  store("pr_token", null);
  token = null;
  gist = null;
  $("token").value = "";
  $("noAccount").classList.remove("hidden");
  $("account").classList.add("hidden");
};
if (token) connect();
