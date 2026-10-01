import Toybox.Application.Storage;
import Toybox.Lang;

// The routes available on the watch and the one chosen.
// Built-in routes come from RoutePack (tools/prepare_route.py); a route pasted as text in the
// phone settings comes first. Their streets are in the watch storage:
//   "t" + route id + "_" + tile number   base64 tile
//   "k" + route id                        list of the tile numbers of that route
module RouteStore {

    const PHONE = "phone";              // id of the route pasted in the phone settings

    // [[id, name, length in m or null], ...]
    function list() {
        var out = [];
        var text = Util.readValue("route");
        if (text instanceof String && text.length() > 0) {
            out.add([PHONE, Util.str(Rez.Strings.PhoneRoute), null]);
        }
        for (var i = 0; i < RoutePack.COUNT; i++) {
            out.add([RoutePack.IDS[i], RoutePack.NAMES[i], RoutePack.LENGTHS[i]]);
        }
        return out;
    }

    // Id of the last route chosen if it is still there, otherwise the first one (null: none).
    function current(routes) {
        if (routes.size() == 0) { return null; }
        var id = null;
        try { id = Storage.getValue("cur"); } catch (e) { }
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

    // Removes the streets of a route from the storage.
    function deleteTiles(id) as Void {
        var keys = null;
        try { keys = Storage.getValue("k" + id); } catch (e) { }
        if (keys instanceof Array) {
            for (var i = 0; i < keys.size(); i++) {
                try { Storage.deleteValue(tileKey(id, keys[i])); } catch (e) { }
            }
        }
        try { Storage.deleteValue("k" + id); } catch (e) { }
    }
}
