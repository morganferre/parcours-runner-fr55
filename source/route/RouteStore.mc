import Toybox.Application.Storage;
import Toybox.Lang;

// The routes available on the watch and the one chosen:
//   - route pasted as text in the phone settings (no streets),
//   - routes built into the app by tools/prepare_route.py (RoutePack), unless deleted,
//   - routes downloaded from the secret gist (RouteDownloader).
// Watch storage:
//   "t" + id + "_" + tile number   base64 tile         "k" + id   tile numbers of the route
//   "z" + id                       characters stored    "m" + id   downloaded route: meta
//   "p" + id + "_" + j             downloaded route: part j of the points (base64)
//   "dl"   downloaded routes [[id, name, length], ...]   "hid"   built-in routes deleted
//   "cur"  route chosen
module RouteStore {

    const PHONE = "phone";              // id of the route pasted in the phone settings
    const KIND_PHONE = 0;
    const KIND_BUILTIN = 1;
    const KIND_DOWNLOADED = 2;
    const CAPACITY_KB = 110;            // storage available for the routes (measured)
    const MAX_POINT_PARTS = 10;

    // Incremented at each change: the menus rebuild themselves when they see a new value.
    var version = 0;

    function read(key) {
        try { return Storage.getValue(key); } catch (e) { return null; }
    }

    function arrayOf(key) {
        var v = read(key);
        return (v instanceof Array) ? v : [];
    }

    // [[id, name, length in m or null, kind], ...]
    function list() {
        var out = [];
        var text = Util.readValue("route");
        if (text instanceof String && text.length() > 0) {
            out.add([PHONE, Util.str(Rez.Strings.PhoneRoute), null, KIND_PHONE]);
        }
        var hiddenIds = arrayOf("hid");
        for (var i = 0; i < RoutePack.COUNT; i++) {
            if (hiddenIds.indexOf(RoutePack.IDS[i]) < 0) {
                out.add([RoutePack.IDS[i], RoutePack.NAMES[i], RoutePack.LENGTHS[i], KIND_BUILTIN]);
            }
        }
        var dl = arrayOf("dl");
        for (var i = 0; i < dl.size(); i++) {
            out.add([dl[i][0], dl[i][1], dl[i][2], KIND_DOWNLOADED]);
        }
        return out;
    }

    function isDownloaded(id) {
        var dl = arrayOf("dl");
        for (var i = 0; i < dl.size(); i++) {
            if (dl[i][0].equals(id)) { return true; }
        }
        return false;
    }

    // On the watch, built in (not deleted) or downloaded.
    function isOnWatch(id) {
        return (RoutePack.IDS.indexOf(id) >= 0 && arrayOf("hid").indexOf(id) < 0) || isDownloaded(id);
    }

    // Id of the last route chosen if it is still there, otherwise the first one (null: none).
    function current(routes) {
        if (routes.size() == 0) { return null; }
        var id = read("cur");
        for (var i = 0; i < routes.size(); i++) {
            if (routes[i][0].equals(id)) { return id; }
        }
        return routes[0][0];
    }

    function setCurrent(id) as Void {
        try { Storage.setValue("cur", id); } catch (e) { }
    }

    function tileKey(id, key) {
        return "t" + id + "_" + key;
    }

    // ---------------- Space ----------------

    function sizeOf(id) {
        var z = read("z" + id);
        return (z instanceof Number) ? z : 0;
    }

    // Storage taken by the streets and downloaded routes (KB).
    function usedKb() {
        var routes = list();
        var total = 0;
        for (var i = 0; i < routes.size(); i++) { total += sizeOf(routes[i][0]); }
        return (total + 1023) / 1024;
    }

    // ---------------- Downloads (gist) ----------------

    function canDownload() {
        return RoutePack.GIST.length() > 0;
    }

    function gistUrl(file) {
        return "https://gist.githubusercontent.com/" + RoutePack.GIST + "/raw/" + file;
    }

    // Adds (or replaces) a downloaded route in the list, once all its files are stored.
    function addDownloaded(id, name, length) as Void {
        var dl = arrayOf("dl");
        var out = [];
        for (var i = 0; i < dl.size(); i++) {
            if (!dl[i][0].equals(id)) { out.add(dl[i]); }
        }
        out.add([id, name, length]);
        Storage.setValue("dl", out);
        version++;
    }

    // ---------------- Deletion ----------------

    // Removes the streets of a route from the storage.
    function deleteTiles(id) as Void {
        var keys = read("k" + id);
        if (keys instanceof Array) {
            for (var i = 0; i < keys.size(); i++) {
                try { Storage.deleteValue(tileKey(id, keys[i])); } catch (e) { }
            }
        }
        try { Storage.deleteValue("k" + id); } catch (e) { }
        try { Storage.deleteValue("z" + id); } catch (e) { }
    }

    // Deleted from the Manage menu. A built-in route cannot leave the app: its streets are
    // removed and it is hidden until a new app file is installed.
    function deleteRoute(id) as Void {
        removeData(id);
        if (RoutePack.IDS.indexOf(id) >= 0) {
            var hiddenIds = arrayOf("hid");
            if (hiddenIds.indexOf(id) < 0) { hiddenIds.add(id); }
            try { Storage.setValue("hid", hiddenIds); } catch (e) { }
        }
        version++;
    }

    // Removes everything stored for a route (also a download that did not finish).
    function removeData(id) as Void {
        deleteTiles(id);
        for (var j = 0; j < MAX_POINT_PARTS; j++) {
            try { Storage.deleteValue("p" + id + "_" + j); } catch (e) { }
        }
        try { Storage.deleteValue("m" + id); } catch (e) { }
        var dl = arrayOf("dl");
        var out = [];
        for (var i = 0; i < dl.size(); i++) {
            if (!dl[i][0].equals(id)) { out.add(dl[i]); }
        }
        try { Storage.setValue("dl", out); } catch (e) { }
    }
}
