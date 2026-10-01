import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;
import Toybox.System;

const STREETS_MAX_ZOOM = 300;       // beyond this, too many streets to draw in one second

// OSM streets built into the app by tools/prepare_route.py, in 500 m tiles.
// Installed on first launch into the watch storage (key "t" + tile number),
// then read tile by tile around the position.
// Tile: for each line [point count, category], then x, y on 2 bytes (m from the corner).
// Categories: 0 street, 1 main road, 2 path, 3 waterway or water body.
class StreetTiles {

    // Tiles loaded around the position, from nearest to farthest (null: empty tile).
    var keys = [] as Array<Number>;
    var data = [] as Array<ByteArray or Null>;
    // Position of the tile grid origin in the route coordinates (m).
    var offX = 0.0;
    var offY = 0.0;
    private var mUnpack = -1;           // next chunk to install, -1 when done

    function initialize(route) {
        if (!RoutePack.HAS_MAP) { return; }
        if (RoutePack.CHUNKS > 0) {
            var installed = null;
            try { installed = Storage.getValue("pack"); } catch (e) { }
            if (installed == null || !installed.equals(RoutePack.PACK_ID)) {
                try { Storage.clearValues(); } catch (e) { }
                mUnpack = 0;
            }
        }
        offX = ((RoutePack.LON0 / 1000000.0d - route.lon0) * M_PER_DEG_LON * route.cosLat0).toFloat();
        offY = ((RoutePack.LAT0 / 1000000.0d - route.lat0) * M_PER_DEG_LAT).toFloat();
    }

    function isInstalling() { return mUnpack >= 0; }

    // Once per second: installation first, then the tiles around (x, y).
    // enabled: streets shown at this zoom. Returns true when new tiles were loaded.
    function tick(hasPos, x, y, zoom, enabled) {
        if (mUnpack >= 0) {
            for (var i = 0; i < 3 && mUnpack >= 0; i++) { unpackChunk(); }
            return false;
        }
        if (!hasPos) { return false; }
        return update(x, y, zoom, enabled);
    }

    private function unpackChunk() as Void {
        var c = RoutePack.chunk(mUnpack);
        if (c instanceof Array) {
            for (var i = 0; i + 1 < c.size(); i += 2) {
                try {
                    Storage.setValue("t" + c[i], c[i + 1]);
                } catch (e) {
                    // Storage full: keep the streets already installed.
                    try { Storage.setValue("pack", RoutePack.PACK_ID); } catch (e2) { }
                    mUnpack = -1;
                    return;
                }
            }
        }
        c = null;
        mUnpack++;
        if (mUnpack >= RoutePack.CHUNKS) {
            Storage.setValue("pack", RoutePack.PACK_ID);
            mUnpack = -1;
        }
    }

    private function tileKey(tx, ty) {
        return (tx + 5000) * 10000 + (ty + 5000);
    }

    private function update(x, y, zoom, enabled) {
        if (!RoutePack.HAS_MAP || !enabled) {
            if (keys.size() > 0) {
                keys = [] as Array<Number>;
                data = [] as Array<ByteArray or Null>;
            }
            return false;
        }
        var t = RoutePack.TILE;
        var r = zoom * 1.3;
        var mx = x - offX;
        var my = y - offY;
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
            var s = Storage.getValue("t" + k);
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
