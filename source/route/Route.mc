import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;

// Meters per degree (local projection). The same values are used by
// tools/converter.html and tools/prepare_route.py: never change them on one side only.
const M_PER_DEG_LAT = 110574.0d;
const M_PER_DEG_LON = 111320.0d;
const MAX_TEXT_POINTS = 600;       // route pasted from the phone (decoded on the watch)
const REC = 9;                      // bytes per point
const BLOCK = 32;                   // points per block (bounding boxes to go fast)

// The route: points in meters from its first point, with bounding boxes per block.
// Loaded from the route built in by tools/prepare_route.py, or from the text pasted
// in the phone settings (see RouteStore).
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
    var warning = null;                 // shown at the bottom of the overview (incomplete route)

    function initialize(routeId) {
        id = routeId;
        if (routeId == null) {
            fromText("");
            return;
        }
        if (routeId.equals(RouteStore.PHONE)) {
            var text = Util.readValue("route");
            fromText(text instanceof String ? text : "");
            return;
        }
        var i = RoutePack.IDS.indexOf(routeId);
        if (i >= 0) {
            fromPack(RoutePack.routeBin(i));
            hasStreets = true;
        } else {
            message = Util.str(Rez.Strings.InvalidRoute);
        }
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

    // Route pasted from the phone (converter text), decoded here.
    // Format: P1;<point count>;<lat x 1e6>;<lon x 1e6>;<dx, dy steps in m, variable-length base 64>
    private function fromText(s) as Void {
        var start = s.find("P1;");
        if (start == null) {
            if (s.length() == 0) {
                message = Util.str(Rez.Strings.NoRoute);
            } else {
                message = Util.str(Rez.Strings.InvalidRoute);
            }
            return;
        }
        s = s.substring(start + 3, s.length());

        var fields = new [3] as Array<Number?>;
        for (var f = 0; f < 3; f++) {
            var i = s.find(";");
            if (i == null) {
                message = Util.str(Rez.Strings.InvalidRoute);
                return;
            }
            fields[f] = s.substring(0, i).toNumber();
            s = s.substring(i + 1, s.length());
        }
        if (fields[0] == null || fields[1] == null || fields[2] == null) {
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        var expected = fields[0];
        var cap = expected;
        if (cap > MAX_TEXT_POINTS) { cap = MAX_TEXT_POINTS; }
        if (cap < 2) {
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        lat0 = fields[1].toDouble() / 1000000.0d;
        lon0 = fields[2].toDouble() / 1000000.0d;
        cosLat0 = Math.cos(lat0 * Math.PI / 180.0d);

        var bytes = StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        s = null;
        data = new [cap * REC]b;

        var acc = 0;
        var shift = 0;
        var x = 0;
        var y = 0;
        var dx = 0;
        var haveDx = false;
        var size = bytes.size();
        for (var k = 0; k < size; k++) {
            var v = charValue(bytes[k]);
            if (v < 0) { continue; }
            if (v >= 32) {
                acc = acc | ((v - 32) << shift);
                shift += 5;
                continue;
            }
            acc = acc | (v << shift);
            var d = (acc >> 1) ^ (-(acc & 1));
            acc = 0;
            shift = 0;
            if (!haveDx) {
                dx = d;
                haveDx = true;
            } else {
                x += dx;
                y += d;
                haveDx = false;
                setPoint(n, x, y);
                n++;
                if (n >= cap) { break; }
            }
        }
        bytes = null;

        if (n < 2) {
            data = null;
            n = 0;
            message = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        if (n != expected) {
            warning = Util.fmt(Rez.Strings.Incomplete, [n, expected]);
        }
        computeDistancesAndBlocks();
    }

    // Cumulative distances, block boxes, center and size (the PC does it for the built-in route).
    private function computeDistancesAndBlocks() as Void {
        var minX = px(0);
        var maxX = minX;
        var minY = py(0);
        var maxY = minY;
        var sum = 0.0;
        setCum(0, 0);
        var prevX = minX;
        var prevY = minY;
        for (var i = 1; i < n; i++) {
            var cx = px(i);
            var cy = py(i);
            var ddx = cx - prevX;
            var ddy = cy - prevY;
            sum += Math.sqrt(ddx * ddx + ddy * ddy);
            setCum(i, sum);
            if (cx < minX) { minX = cx; }
            if (cx > maxX) { maxX = cx; }
            if (cy < minY) { minY = cy; }
            if (cy > maxY) { maxY = cy; }
            prevX = cx;
            prevY = cy;
        }
        total = sum;

        nb = (n - 2) / BLOCK + 1;
        blk = new [nb * 12]b;
        for (var b = 0; b < nb; b++) {
            var p0 = b * BLOCK;
            var p1 = p0 + BLOCK;
            if (p1 > n - 1) { p1 = n - 1; }
            var bx0 = px(p0);
            var bx1 = bx0;
            var by0 = py(p0);
            var by1 = by0;
            for (var i = p0 + 1; i <= p1; i++) {
                var cx = px(i);
                var cy = py(i);
                if (cx < bx0) { bx0 = cx; }
                if (cx > bx1) { bx1 = cx; }
                if (cy < by0) { by0 = cy; }
                if (cy > by1) { by1 = cy; }
            }
            put3(blk, b * 12, bx0);
            put3(blk, b * 12 + 3, bx1);
            put3(blk, b * 12 + 6, by0);
            put3(blk, b * 12 + 9, by1);
        }

        centerX = (minX + maxX) / 2.0;
        centerY = (minY + maxY) / 2.0;
        span = maxX - minX;
        if (maxY - minY > span) { span = maxY - minY; }
        if (span < 50) { span = 50; }
    }

    // Alphabet: A-Z a-z 0-9 - _  (0..31 = last chunk, 32..63 = chunk followed by another)
    private function charValue(b) {
        if (b >= 65 && b <= 90) { return b - 65; }
        if (b >= 97 && b <= 122) { return b - 71; }
        if (b >= 48 && b <= 57) { return b + 4; }
        if (b == 45) { return 62; }
        if (b == 95) { return 63; }
        return -1;
    }

    // ================= Points =================

    private function put3(arr, o, v) as Void {
        var u = v & 0xFFFFFF;
        arr[o] = (u >> 16) & 0xFF;
        arr[o + 1] = (u >> 8) & 0xFF;
        arr[o + 2] = u & 0xFF;
    }

    private function get3(o) {
        var v = (data[o] << 16) | (data[o + 1] << 8) | data[o + 2];
        if (v >= 0x800000) { v -= 0x1000000; }
        return v;
    }

    private function setPoint(i, x, y) as Void {
        put3(data, i * REC, x);
        put3(data, i * REC + 3, y);
    }

    private function setCum(i, c) as Void {
        put3(data, i * REC + 6, c.toNumber());
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
