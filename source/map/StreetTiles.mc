import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;
import Toybox.System;

const STREETS_MAX_ZOOM = 300;       // beyond this, too many streets to draw in one second

// OSM streets around the position, read tile by tile (500 m) from the watch storage,
// where RouteInstaller copied them (keys: see RouteStore).
// Tile: for each line one byte (category << 6 | point count), then the points as steps
// (see encode_tile in prepare_route.py), in m from the tile corner, in the route coordinates.
// Categories: 0 street, 1 main road, 2 path, 3 waterway or water body.
class StreetTiles {

    // Tiles loaded around the position, from nearest to farthest (null: empty tile).
    var keys = [] as Array<Number>;
    var data = [] as Array<ByteArray or Null>;
    private var mRouteId = null;

    function initialize(route) {
        if (route.hasStreets) { mRouteId = route.id; }
    }

    // Once per second: the tiles around (x, y). enabled: streets shown at this zoom.
    // Returns true when new tiles were loaded.
    function tick(hasPos, x, y, zoom, enabled) {
        if (!hasPos) { return false; }
        return update(x, y, zoom, enabled);
    }

    private function tileKey(tx, ty) {
        return (tx + 5000) * 10000 + (ty + 5000);
    }

    private function update(x, y, zoom, enabled) {
        if (mRouteId == null || !enabled) {
            if (keys.size() > 0) {
                keys = [] as Array<Number>;
                data = [] as Array<ByteArray or Null>;
            }
            return false;
        }
        var t = RoutePack.TILE;
        var r = zoom * 1.3;
        var mx = x;
        var my = y;
        var x0 = Math.floor((mx - r) / t).toNumber();
        var x1 = Math.floor((mx + r) / t).toNumber();
        var y0 = Math.floor((my - r) / t).toNumber();
        var y1 = Math.floor((my + r) / t).toNumber();
        var ctx = Math.floor(mx / t).toNumber();
        var cty = Math.floor(my / t).toNumber();

        // Tiles needed, from nearest to farthest.
        var need = [] as Array<Number>;
        for (var ring = 0; ring <= 2; ring++) {
            for (var tx = x0; tx <= x1; tx++) {
                for (var ty = y0; ty <= y1; ty++) {
                    var dx = (tx - ctx).abs();
                    var dy = (ty - cty).abs();
                    var dist = dx > dy ? dx : dy;
                    if (dist == ring) { need.add(tileKey(tx, ty)); }
                }
            }
        }

        // New list in the order of "need" (nearest to farthest):
        // reuse tiles already loaded, load at most 3 new ones per second.
        var newKeys = [] as Array<Number>;
        var newData = [] as Array<ByteArray or Null>;
        var loaded = 0;
        for (var i = 0; i < need.size(); i++) {
            var k = need[i];
            var old = keys.indexOf(k);
            if (old >= 0) {
                newKeys.add(k);
                newData.add(data[old]);
                continue;
            }
            if (loaded >= 3 || System.getSystemStats().freeMemory < 8000) { continue; }
            var s = Storage.getValue(RouteStore.tileKey(mRouteId, k));
            newKeys.add(k);
            if (s instanceof String) {
                newData.add(StringUtil.convertEncodedString(s, {
                    :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                    :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
                }));
                loaded++;
            } else {
                newData.add(null);
            }
        }
        keys = newKeys;
        data = newData;
        return loaded > 0;
    }
}
