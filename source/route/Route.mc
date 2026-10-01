import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;

// Meters per degree (local projection). The same values are used by
// tools/prepare_route.py: never change them on one side only.
const M_PER_DEG_LAT = 110574.0d;
const M_PER_DEG_LON = 111320.0d;
const REC = 9;                      // bytes per point
const BLOCK = 32;                   // points per block (bounding boxes to go fast)

// The route: points in meters from its first point, with bounding boxes per block.
// Built into the app or downloaded (see RouteStore): everything is precomputed on the PC.
class Route {

    var id = null;                      // RouteStore id, null: no route
    var hasStreets = false;             // streets installed in the storage under this id

    // 9 bytes per point (x, y, cumulative distance: 3 bytes each, in m).
    // Public so that the hot loops (drawing, matching) read it without a call per point.
    var data = null;
    var n = 0;
    // Bounding box of each block of BLOCK points (including the next point):
    // 12 bytes per block, x min, x max, y min, y max as 3-byte signed values.
    var blk = null;
    var nb = 0;
    var total = 0.0;
    var lat0 = 0.0d;
    var lon0 = 0.0d;
    var cosLat0 = 1.0d;
    // Overview (before the GPS fix): center and size of the route.
    var centerX = 0.0;
    var centerY = 0.0;
    var span = 1.0;
    var message = "";                   // shown instead of the map when there is no route

    function initialize(routeId) {
        id = routeId;
        if (routeId == null) {
            message = Util.str(Rez.Strings.NoRoute);
            return;
        }
        var i = RoutePack.IDS.indexOf(routeId);
        if (i >= 0) {
            fromPack(RoutePack.routeBin(i));
            hasStreets = true;
        } else if (RouteStore.isDownloaded(routeId)) {
            fromStorage(routeId);
            hasStreets = true;
        } else {
            message = Util.str(Rez.Strings.InvalidRoute);
        }
    }

    // Route downloaded from the gist (RouteDownloader), same content as fromPack:
    // "m" + id = lat0;lon0;points;length;center x;center y;span;point parts;blocks base64,
    // "p" + id + "_" + j = part j of the points (base64, whole bytes).
    private function fromStorage(routeId) as Void {
        var meta = RouteStore.read("m" + routeId);
        var f = (meta instanceof String) ? Util.split(meta, ";") : [];
        if (f.size() < 9) {
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        lat0 = f[0].toDouble() / 1000000.0d;
        lon0 = f[1].toDouble() / 1000000.0d;
        cosLat0 = Math.cos(lat0 * Math.PI / 180.0d);
        total = f[3].toFloat();
        centerX = f[4].toFloat();
        centerY = f[5].toFloat();
        span = f[6].toFloat();
        var parts = f[7].toNumber();
        var count = f[2].toNumber();
        blk = decode64(f[8]);
        f = null;
        meta = null;
        var bytes = null;
        for (var j = 0; j < parts; j++) {
            var text = RouteStore.read("p" + routeId + "_" + j);
            if (!(text instanceof String)) { break; }
            var b = decode64(text);
            if (bytes == null) { bytes = b; } else { bytes.addAll(b); }
        }
        if (bytes == null || bytes.size() != count * REC) {
            blk = null;
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        data = bytes;
        n = count;
        nb = blk.size() / 12;
    }

    function isValid() { return n >= 2; }

    // ================= Loading =================

    // Route prepared by tools/prepare_route.py: everything is precomputed,
    // the watch only decodes two byte blocks (no loop, instant start).
    // [lat0 x 1e6, lon0 x 1e6, point count, length, center x, center y, span, points base64, blocks base64]
    private function fromPack(a) as Void {
        if (!(a instanceof Array) || a.size() < 9) {
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        lat0 = a[0].toDouble() / 1000000.0d;
        lon0 = a[1].toDouble() / 1000000.0d;
        cosLat0 = Math.cos(lat0 * Math.PI / 180.0d);
        total = a[3].toFloat();
        centerX = a[4].toFloat();
        centerY = a[5].toFloat();
        span = a[6].toFloat();
        data = decode64(a[7]);
        blk = decode64(a[8]);
        n = a[2];
        nb = blk.size() / 12;
    }

    private function decode64(s) {
        return StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
    }

    // ================= Points =================

    private function get3(o) {
        var v = (data[o] << 16) | (data[o + 1] << 8) | data[o + 2];
        if (v >= 0x800000) { v -= 0x1000000; }
        return v;
    }

    function px(i) { return get3(i * REC); }
    function py(i) { return get3(i * REC + 3); }
    function cum(i) { return get3(i * REC + 6); }

    // Squared distance between a point and the box of block b (0 if inside).
    function blockDist2(b, x, y) {
        var k = blk;
        var o = b * 12;
        var x0 = (k[o] << 16) | (k[o + 1] << 8) | k[o + 2];
        if (x0 >= 0x800000) { x0 -= 0x1000000; }
        var x1 = (k[o + 3] << 16) | (k[o + 4] << 8) | k[o + 5];
        if (x1 >= 0x800000) { x1 -= 0x1000000; }
        var y0 = (k[o + 6] << 16) | (k[o + 7] << 8) | k[o + 8];
        if (y0 >= 0x800000) { y0 -= 0x1000000; }
        var y1 = (k[o + 9] << 16) | (k[o + 10] << 8) | k[o + 11];
        if (y1 >= 0x800000) { y1 -= 0x1000000; }
        var dx = 0.0;
        var dy = 0.0;
        if (x < x0) { dx = x0 - x; } else if (x > x1) { dx = x - x1; }
        if (y < y0) { dy = y0 - y; } else if (y > y1) { dy = y - y1; }
        return dx * dx + dy * dy;
    }
}
