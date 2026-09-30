import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Meters per degree (local projection). The same values are used by
// tools/converter.html and tools/prepare_route.py: never change them on one side only.
const M_PER_DEG_LAT = 110574.0d;
const M_PER_DEG_LON = 111320.0d;
const MAX_POINTS = 4000;           // route prepared on the PC: 9 bytes per point, 36 KB at most
const MAX_TEXT_POINTS = 600;       // route pasted from the phone (decoded on the watch)
const REC = 9;
const BLOCK = 32;                   // points per block (bounding boxes to go fast)
const STREETS_MAX_ZOOM = 300;       // beyond this, too many streets to draw in one second
const ANIM_MS = 1000;               // the view glides to the new GPS point in 1 s (GPS interval)
const STEP_POINTS = 300;            // street points drawn per step. The watch kills the app beyond
                                    // about 700 points in a single task (measured in the simulator).

// Route, OSM streets, GPS position, route tracking and off-course alerts.
class RouteMap {

    // --- Route: 9 bytes per point (x, y, cumulative distance: 3 bytes each, in m) ---
    private var mRoute = null;
    private var mN = 0;
    // Bounding box of each block of BLOCK points (including the next point):
    // 12 bytes per block, x min, x max, y min, y max as 3-byte signed values.
    private var mBlk = null;
    private var mNb = 0;
    private var mTotal = 0.0;
    private var mLat0 = 0.0d;
    private var mLon0 = 0.0d;
    private var mCosLat0 = 1.0d;
    private var mCenterX = 0.0;
    private var mCenterY = 0.0;
    private var mSpan = 1.0;
    private var mMessage = "";
    private var mWarning = null;

    // --- Settings ---
    private var mZoom = 200;
    private var mTrackUp = true;
    private var mDark = true;
    private var mLineWidth = 3;
    private var mShowDone = true;
    private var mShowStreets = true;
    private var mAlertOn = true;
    private var mAlertTone = true;
    private var mAlertDist = 40;

    // --- Position ---
    private var mHasPos = false;
    private var mQuality = 0;
    private var mX = 0.0;
    private var mY = 0.0;
    private var mRefX = 0.0;
    private var mRefY = 0.0;
    private var mHeading = 0.0;
    private var mHeadingOk = false;

    // --- Smooth display ---
    // The view does not jump from one GPS point to the next: it glides from the displayed position (mD*)
    // to the last point (mX, mY, mHeading, mNear*) over ANIM_MS, starting from mA*.
    private var mDX = 0.0;
    private var mDY = 0.0;
    private var mDH = 0.0;
    private var mDNX = 0.0;
    private var mDNY = 0.0;
    private var mAX = 0.0;
    private var mAY = 0.0;
    private var mAH = 0.0;
    private var mANX = 0.0;
    private var mANY = 0.0;
    private var mAT = 0;
    private var mAnimOn = false;        // false when standing still: no need to redraw
    private var mVisible = true;        // map screen displayed

    // --- Route tracking ---
    private var mSeg = 0;
    private var mNearX = 0.0;
    private var mNearY = 0.0;
    private var mOffDist = 0.0;
    private var mProgress = 0.0;
    private var mOffCount = 0;
    private var mOffCourse = false;
    private var mJoined = false;
    private var mBestD2 = 0.0;
    private var mBestSeg = 0;
    private var mBestT = 0.0;
    private var mBestX = 0.0;
    private var mBestY = 0.0;
    private var mBestS = 0.0;           // score of the best match (m): distance + jump penalty
    private var mScored = false;        // once on the route: prefer the logical continuation
    private var mSlack = 60.0;          // possible progress since the last point (m)
    private var mMatchMs = 0;
    // Closest match, without penalty
    private var mRawD2 = 0.0;
    private var mRawSeg = 0;
    private var mRawT = 0.0;
    private var mRawX = 0.0;
    private var mRawY = 0.0;

    // --- Current view ---
    private var mVox = 0.0;
    private var mVoy = 0.0;
    private var mVcx = 0.0;
    private var mVcy = 0.0;
    private var mVk = 1.0;
    private var mVc = 1.0;
    private var mVs = 0.0;

    // --- OSM streets ---
    private var mMapOffX = 0.0;
    private var mMapOffY = 0.0;
    private var mTileKeys = [] as Array<Number>;
    private var mTileData = [] as Array<ByteArray or Null>;
    private var mUnpack = -1;
    // Streets pre-drawn into two alternating bitmaps: one is shown while the other is being drawn.
    private var mBmp = [null, null];
    private var mBmpBg = -1;            // background color the bitmaps were created with
    private var mShow = -1;             // bitmap ready to show (-1: none)
    private var mWork = 0;              // bitmap being drawn
    private var mJob = false;
    private var mJobKeys = null;
    private var mJobData = null;
    private var mJobTile = 0;
    private var mJobByte = 0;
    private var mJobCat = -1;
    private var mJa = 0.0;              // view parameters frozen for the current drawing
    private var mJb = 0.0;
    private var mJox = 0.0;
    private var mJoy = 0.0;
    private var mJcx = 0.0;
    private var mJcy = 0.0;
    private var mJh = 0.0;              // view heading for the current drawing
    private var mSX = 0.0;              // view position and heading of the displayed bitmap
    private var mSY = 0.0;
    private var mSH = 0.0;
    private var mW = 208;
    private var mH = 208;
    private var mTimer = null;

    // --- Colors (the FR55 only shows 8 colors, no gray) ---
    var bg = Graphics.COLOR_BLACK;
    var fg = Graphics.COLOR_WHITE;
    var accent = Graphics.COLOR_YELLOW;
    private var mRouteColor = Graphics.COLOR_WHITE;
    private var mDoneColor = Graphics.COLOR_PINK;
    private var mStreetColor = Graphics.COLOR_DK_BLUE;
    private var mPathColor = Graphics.COLOR_GREEN;
    private var mWaterColor = 0x00FFFF;
    var doneColor = Graphics.COLOR_PINK;

    // --- Texts drawn every frame, loaded once ---
    private var mFinish = "";
    private var mRouteAway = "";
    private var mOffCourseText = "";

    function initialize() {
        mFinish = Util.str(Rez.Strings.Finish);
        mRouteAway = Util.str(Rez.Strings.RouteAway);
        mOffCourseText = Util.str(Rez.Strings.OffCourse);
        loadSettings();
    }

    // ================= Settings =================

    function loadSettings() as Void {
        loadDisplay();
        mShowDone = Util.readBool("showDone", true);
        mAlertOn = Util.readBool("alertOn", true);
        mAlertTone = Util.readBool("alertTone", true);
        mAlertDist = Util.readNum("alertDist", 40);
        if (mAlertDist < 10) { mAlertDist = 10; }

        // Route pasted from the phone first, otherwise the one prepared on the PC.
        var route = Util.readValue("route");
        if (route instanceof String && route.length() > 0) {
            loadRoute(route);
        } else if (RoutePack.HAS_MAP) {
            loadRouteBin(RoutePack.routeBin());
        } else {
            loadRoute("");
        }

        mTileKeys = [] as Array<Number>;
        mTileData = [] as Array<ByteArray or Null>;
        mUnpack = -1;
        if (RoutePack.HAS_MAP && RoutePack.CHUNKS > 0) {
            var installed = null;
            try { installed = Storage.getValue("pack"); } catch (e) { }
            if (installed == null || !installed.equals(RoutePack.PACK_ID)) {
                try { Storage.clearValues(); } catch (e) { }
                mUnpack = 0;
            }
        }
        if (RoutePack.HAS_MAP) {
            mMapOffX = ((RoutePack.LON0 / 1000000.0d - mLon0) * M_PER_DEG_LON * mCosLat0).toFloat();
            mMapOffY = ((RoutePack.LAT0 / 1000000.0d - mLat0) * M_PER_DEG_LAT).toFloat();
        }
    }

    // Display settings only (watch menu): does not reload the route.
    function loadDisplay() as Void {
        mZoom = Util.readNum("zoom", 200);
        if (mZoom < 50) { mZoom = 50; }
        mTrackUp = Util.readNum("orientation", 0) == 0;
        mDark = Util.readNum("theme", 0) == 0;
        mLineWidth = Util.readNum("lineWidth", 3);
        if (mLineWidth < 1) { mLineWidth = 1; }
        mShowStreets = Util.readBool("showStreets", true);
        mShow = -1;

        if (mDark) {
            bg = Graphics.COLOR_BLACK;
            fg = Graphics.COLOR_WHITE;
            accent = Graphics.COLOR_YELLOW;
            mRouteColor = Graphics.COLOR_WHITE;
        } else {
            bg = Graphics.COLOR_WHITE;
            fg = Graphics.COLOR_BLACK;
            accent = Graphics.COLOR_PINK;
            mRouteColor = Graphics.COLOR_BLACK;
            // (magenta arrow on a white background)
        }
        // 8 colors only: blue streets, green paths, cyan water, already run magenta (black) / cyan (white).
        mStreetColor = Graphics.COLOR_DK_BLUE;
        mPathColor = Graphics.COLOR_GREEN;
        if (mDark) {
            mDoneColor = Graphics.COLOR_PINK;
            mWaterColor = 0x00FFFF;
        } else {
            mDoneColor = 0x00FFFF;
            mWaterColor = Graphics.COLOR_DK_BLUE;
        }
        doneColor = mDoneColor;
        startRender();
    }

    function hasRoute() { return mN >= 2; }
    function progress() { return (mTotal > 0 && mJoined) ? mProgress / mTotal : 0.0; }
    function hasPosition() { return mHasPos; }
    function gpsQuality() { return mQuality; }
    function isOffCourse() { return mOffCourse; }
    function remaining() { return mTotal - mProgress; }
    function total() { return mTotal; }
    function zoom() { return mZoom; }

    // ================= Route loading =================
    // Format: P1;<point count>;<lat x 1e6>;<lon x 1e6>;<dx, dy steps in m, variable-length base 64>

    private function resetRoute() as Void {
        mRoute = null;
        mBlk = null;
        mN = 0;
        mNb = 0;
        mTotal = 0.0;
        mProgress = 0.0;
        mSeg = 0;
        mOffCount = 0;
        mOffCourse = false;
        mJoined = false;
        mMatchMs = 0;
        mWarning = null;
    }

    // Route prepared by tools/prepare_route.py: everything is precomputed,
    // the watch only decodes two byte blocks (no loop, instant start).
    // [lat0 x 1e6, lon0 x 1e6, point count, length, center x, center y, span, points base64, blocks base64]
    private function loadRouteBin(a) as Void {
        resetRoute();
        if (!(a instanceof Array) || a.size() < 9) {
            mMessage = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        mLat0 = a[0].toDouble() / 1000000.0d;
        mLon0 = a[1].toDouble() / 1000000.0d;
        mCosLat0 = Math.cos(mLat0 * Math.PI / 180.0d);
        mTotal = a[3].toFloat();
        mCenterX = a[4].toFloat();
        mCenterY = a[5].toFloat();
        mSpan = a[6].toFloat();
        mRoute = decode64(a[7]);
        mBlk = decode64(a[8]);
        mN = a[2];
        mNb = mBlk.size() / 12;
    }

    private function decode64(s) {
        return StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
    }

    // Route pasted from the phone (converter text), decoded here.
    private function loadRoute(s) as Void {
        resetRoute();

        var start = s.find("P1;");
        if (start == null) {
            if (s.length() == 0) {
                mMessage = Util.str(Rez.Strings.NoRoute);
            } else {
                mMessage = Util.str(Rez.Strings.InvalidRoute);
            }
            return;
        }
        s = s.substring(start + 3, s.length());

        var fields = new [3] as Array<Number?>;
        for (var f = 0; f < 3; f++) {
            var i = s.find(";");
            if (i == null) {
                mMessage = Util.str(Rez.Strings.InvalidRoute);
                return;
            }
            fields[f] = s.substring(0, i).toNumber();
            s = s.substring(i + 1, s.length());
        }
        if (fields[0] == null || fields[1] == null || fields[2] == null) {
            mMessage = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        var expected = fields[0];
        var cap = expected;
        if (cap > MAX_TEXT_POINTS) { cap = MAX_TEXT_POINTS; }
        if (cap < 2) {
            mMessage = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        mLat0 = fields[1].toDouble() / 1000000.0d;
        mLon0 = fields[2].toDouble() / 1000000.0d;
        mCosLat0 = Math.cos(mLat0 * Math.PI / 180.0d);

        var bytes = StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        s = null;
        mRoute = new [cap * REC]b;

        var acc = 0;
        var shift = 0;
        var x = 0;
        var y = 0;
        var dx = 0;
        var haveDx = false;
        var n = bytes.size();
        for (var k = 0; k < n; k++) {
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
                setPoint(mN, x, y);
                mN++;
                if (mN >= cap) { break; }
            }
        }
        bytes = null;

        if (mN < 2) {
            mRoute = null;
            mN = 0;
            mMessage = Util.str(Rez.Strings.InvalidRoute);
            return;
        }
        if (mN != expected) {
            mWarning = Util.fmt(Rez.Strings.Incomplete, [mN, expected]);
        }

        var minX = px(0);
        var maxX = minX;
        var minY = py(0);
        var maxY = minY;
        var total = 0.0;
        setCum(0, 0);
        var prevX = minX;
        var prevY = minY;
        for (var i = 1; i < mN; i++) {
            var cx = px(i);
            var cy = py(i);
            var ddx = cx - prevX;
            var ddy = cy - prevY;
            total += Math.sqrt(ddx * ddx + ddy * ddy);
            setCum(i, total);
            if (cx < minX) { minX = cx; }
            if (cx > maxX) { maxX = cx; }
            if (cy < minY) { minY = cy; }
            if (cy > maxY) { maxY = cy; }
            prevX = cx;
            prevY = cy;
        }
        mTotal = total;

        var nb = (mN - 2) / BLOCK + 1;
        mBlk = new [nb * 12]b;
        mNb = nb;
        for (var b = 0; b < nb; b++) {
            var p0 = b * BLOCK;
            var p1 = p0 + BLOCK;
            if (p1 > mN - 1) { p1 = mN - 1; }
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
            put3b(mBlk, b * 12, bx0);
            put3b(mBlk, b * 12 + 3, bx1);
            put3b(mBlk, b * 12 + 6, by0);
            put3b(mBlk, b * 12 + 9, by1);
        }

        mCenterX = (minX + maxX) / 2.0;
        mCenterY = (minY + maxY) / 2.0;
        mSpan = maxX - minX;
        if (maxY - minY > mSpan) { mSpan = maxY - minY; }
        if (mSpan < 50) { mSpan = 50; }
    }

    private function put3b(arr, o, v) as Void {
        var u = v & 0xFFFFFF;
        arr[o] = (u >> 16) & 0xFF;
        arr[o + 1] = (u >> 8) & 0xFF;
        arr[o + 2] = u & 0xFF;
    }

    private function put3(o, v) as Void {
        var u = v & 0xFFFFFF;
        mRoute[o] = (u >> 16) & 0xFF;
        mRoute[o + 1] = (u >> 8) & 0xFF;
        mRoute[o + 2] = u & 0xFF;
    }

    private function get3(o) {
        var v = (mRoute[o] << 16) | (mRoute[o + 1] << 8) | mRoute[o + 2];
        if (v >= 0x800000) { v -= 0x1000000; }
        return v;
    }

    private function setPoint(i, x, y) as Void {
        put3(i * REC, x);
        put3(i * REC + 3, y);
    }

    private function setCum(i, c) as Void {
        put3(i * REC + 6, c.toNumber());
    }

    private function px(i) { return get3(i * REC); }
    private function py(i) { return get3(i * REC + 3); }
    private function cum(i) { return get3(i * REC + 6); }

    // Squared distance between a point and the box of block b (0 if inside).
    private function blockDist2(b, x, y) {
        var k = mBlk;
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

    // Alphabet: A-Z a-z 0-9 - _  (0..31 = last chunk, 32..63 = chunk followed by another)
    private function charValue(b) {
        if (b >= 65 && b <= 90) { return b - 65; }
        if (b >= 97 && b <= 122) { return b - 71; }
        if (b >= 48 && b <= 57) { return b + 4; }
        if (b == 45) { return 62; }
        if (b == 95) { return 63; }
        return -1;
    }

    // ================= Position (each GPS point, once per second) =================

    function setPosition(info as Position.Info, running) as Void {
        mQuality = info.accuracy;
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_POOR) { return; }

        var deg = loc.toDegrees();
        var x = ((deg[1] - mLon0) * M_PER_DEG_LON * mCosLat0).toFloat();
        var y = ((deg[0] - mLat0) * M_PER_DEG_LAT).toFloat();

        var first = !mHasPos;
        var headingWasOk = mHeadingOk;
        animate();                      // position displayed right now: starting point of the glide
        updateHeading(x, y);
        mX = x;
        mY = y;
        mHasPos = true;

        if (mN >= 2) {
            matchRoute(x, y);
            updateAlert(running);
        }

        var dx = x - mDX;
        var dy = y - mDY;
        if (first || dx * dx + dy * dy > 200.0 * 200.0) {
            // First point or big jump: go there directly.
            mDX = x;
            mDY = y;
            mDNX = mNearX;
            mDNY = mNearY;
        }
        if (!headingWasOk) { mDH = mHeading; }
        mAX = mDX;
        mAY = mDY;
        mAH = mDH;
        mANX = mDNX;
        mANY = mDNY;
        mAT = System.getTimer();
        mAnimOn = dx * dx + dy * dy > 0.25 || angle(mHeading - mDH).abs() > 0.01;
        startRender();
    }

    private function angle(a) {
        while (a > Math.PI) { a -= 2 * Math.PI; }
        while (a < -Math.PI) { a += 2 * Math.PI; }
        return a;
    }

    // Moves the displayed position forward. Returns true until it reaches the last GPS point.
    function animate() {
        if (!mHasPos) { return false; }
        var f = (System.getTimer() - mAT) / ANIM_MS.toFloat();
        if (f > 1.0) { f = 1.0; } else if (f < 0.0) { f = 0.0; }
        mDX = mAX + (mX - mAX) * f;
        mDY = mAY + (mY - mAY) * f;
        mDNX = mANX + (mNearX - mANX) * f;
        mDNY = mANY + (mNearY - mANY) * f;
        mDH = angle(mAH + angle(mHeading - mAH) * f);
        return mAnimOn && f < 1.0;
    }

    // Called FPS times per second: true if the map screen must be redrawn.
    function frame() {
        if (!mVisible || !animate()) { return false; }
        // Track-up map: the street bitmap does not rotate by itself,
        // so it is redrawn as soon as the displayed heading drifts more than 6° away from it.
        if (mTrackUp && mHeadingOk && !mJob && mShow >= 0 && angle(mDH - mSH).abs() > 0.1) {
            startRender();
        }
        return true;
    }

    // Street drawing only runs while the map screen is shown: on the other screens it would
    // keep the CPU busy for nothing and slow down the buttons.
    function setVisible(v) as Void {
        if (v == mVisible) { return; }
        mVisible = v;
        if (v) {
            startRender();
        } else if (mJob) {
            mJob = false;
            mTimer.stop();
        }
    }

    // Background tasks, once per second: street installation, then tile loading.
    function tick() as Void {
        if (mUnpack >= 0) {
            for (var i = 0; i < 3 && mUnpack >= 0; i++) { unpackChunk(); }
        } else if (mHasPos) {
            updateTiles();
        }
    }

    private function updateHeading(x, y) as Void {
        if (!mHasPos) {
            mRefX = x;
            mRefY = y;
            return;
        }
        var dx = x - mRefX;
        var dy = y - mRefY;
        if (dx * dx + dy * dy < 16.0) { return; }   // less than 4 m: keep the heading

        var h = Math.atan2(dx, dy);
        if (mHeadingOk) {
            var diff = h - mHeading;
            while (diff > Math.PI) { diff -= 2 * Math.PI; }
            while (diff < -Math.PI) { diff += 2 * Math.PI; }
            h = mHeading + diff * 0.6;
            while (h > Math.PI) { h -= 2 * Math.PI; }
            while (h < -Math.PI) { h += 2 * Math.PI; }
        }
        mHeading = h;
        mHeadingOk = true;
        mRefX = x;
        mRefY = y;
    }

    // On an out-and-back or a self-crossing loop, several passes are at the same distance:
    // once on the route, prefer the one that follows the progress (no jump forward or backward).
    private function matchRoute(x, y) as Void {
        var last = mN - 2;
        var now = System.getTimer();
        // 60 m + 7 m/s since the last point (GPS can drop out for a few seconds).
        mSlack = 60.0;
        if (mMatchMs > 0) { mSlack += (now - mMatchMs) * 0.007; }
        mMatchMs = now;
        mScored = mJoined;

        var from = mSeg - 5;
        if (from < 0) { from = 0; }
        var to = mSeg + 40;
        if (to > last) { to = last; }

        resetBest();
        scan(x, y, from, to);
        if (mBestD2 > mAlertDist * mAlertDist && (from > 0 || to < last)) {
            // Search the whole route, skipping blocks that are too far.
            resetBest();
            var nb = mNb;
            for (var b = 0; b < nb; b++) {
                if (blockDist2(b, x, y) >= (mScored ? mBestS * mBestS : mBestD2)) { continue; }
                var s1 = b * BLOCK + BLOCK - 1;
                scan(x, y, b * BLOCK, s1 > last ? last : s1);
            }
            if (!mJoined) {
                // Not on the route yet: among passes that are almost as close,
                // take the earliest (on a loop, the start rather than the finish).
                var limit = Math.sqrt(mBestD2) + 15;
                limit = limit * limit;
                var found = false;
                for (var b = 0; b < nb && !found; b++) {
                    if (blockDist2(b, x, y) > limit) { continue; }
                    var s1 = b * BLOCK + BLOCK - 1;
                    if (s1 > last) { s1 = last; }
                    for (var i = b * BLOCK; i <= s1; i++) {
                        resetBest();
                        scan(x, y, i, i);
                        if (mBestD2 <= limit) {
                            found = true;
                            break;
                        }
                    }
                }
            }
        }
        // Shortcut or real jump: if a pass is within reach while the logical continuation is not,
        // snap to it rather than reporting "off course".
        var a2 = mAlertDist * mAlertDist;
        if (mScored && mBestD2 > a2 && mRawD2 <= a2) {
            mBestD2 = mRawD2;
            mBestSeg = mRawSeg;
            mBestT = mRawT;
            mBestX = mRawX;
            mBestY = mRawY;
        }

        mSeg = mBestSeg;
        mNearX = mBestX;
        mNearY = mBestY;
        mOffDist = Math.sqrt(mBestD2);
        var c0 = cum(mSeg);
        mProgress = c0 + mBestT * (cum(mSeg + 1) - c0);
    }

    private function resetBest() as Void {
        mBestD2 = 1.0e12;
        mBestS = 1.0e6;
        mRawD2 = 1.0e12;
    }

    // Segments from..to: keeps the best in mBest* and the closest in mRaw*
    // (without resetting them).
    private function scan(x, y, from, to) as Void {
        var r = mRoute;
        var o = from * REC;
        var ax = (r[o] << 16) | (r[o + 1] << 8) | r[o + 2];
        if (ax >= 0x800000) { ax -= 0x1000000; }
        var ay = (r[o + 3] << 16) | (r[o + 4] << 8) | r[o + 5];
        if (ay >= 0x800000) { ay -= 0x1000000; }
        for (var i = from; i <= to; i++) {
            o += REC;
            var bx = (r[o] << 16) | (r[o + 1] << 8) | r[o + 2];
            if (bx >= 0x800000) { bx -= 0x1000000; }
            var by = (r[o + 3] << 16) | (r[o + 4] << 8) | r[o + 5];
            if (by >= 0x800000) { by -= 0x1000000; }
            var vx = bx - ax;
            var vy = by - ay;
            var len2 = vx * vx + vy * vy;
            var t = 0.0;
            if (len2 > 0) {
                t = ((x - ax) * vx + (y - ay) * vy) / len2;
                if (t < 0.0) { t = 0.0; } else if (t > 1.0) { t = 1.0; }
            }
            var qx = ax + t * vx;
            var qy = ay + t * vy;
            var d2 = (x - qx) * (x - qx) + (y - qy) * (y - qy);
            if (d2 < mRawD2) {
                mRawD2 = d2;
                mRawSeg = i;
                mRawT = t;
                mRawX = qx;
                mRawY = qy;
            }
            var better = false;
            if (!mScored) {
                better = d2 < mBestD2;
            } else if (d2 < mBestS * mBestS) {
                // Penalty: 0.5 m per meter of jump beyond the possible progress, or beyond 20 m backward.
                var c0 = cum(i);
                var delta = c0 + t * (cum(i + 1) - c0) - mProgress;
                var sc = Math.sqrt(d2);
                if (delta > mSlack) {
                    sc += (delta - mSlack) * 0.5;
                } else if (delta < -20) {
                    sc += (-20 - delta) * 0.5;
                }
                if (sc < mBestS) {
                    mBestS = sc;
                    better = true;
                }
            }
            if (better) {
                mBestD2 = d2;
                mBestSeg = i;
                mBestT = t;
                mBestX = qx;
                mBestY = qy;
            }
            ax = bx;
            ay = by;
        }
    }

    // Off course after 3 s beyond the alert distance, back on course below 70% of that distance.
    private function updateAlert(running) as Void {
        if (!mJoined) {
            if (mOffDist > mAlertDist) { return; }
            mJoined = true;
        }
        if (mOffDist > mAlertDist) {
            mOffCount++;
        } else if (mOffDist < mAlertDist * 0.7) {
            mOffCount = 0;
        }
        if (!mOffCourse && mOffCount >= 3) {
            mOffCourse = true;
            if (running) { alert(true); }
        } else if (mOffCourse && mOffCount == 0) {
            mOffCourse = false;
            if (running) { alert(false); }
        } else if (mOffCourse && running && mOffCount % 30 == 0) {
            alert(true);
        }
    }

    private function alert(off) as Void {
        if (!mAlertOn) { return; }
        if (Attention has :vibrate) {
            var profile;
            if (off) {
                profile = [
                    new Attention.VibeProfile(100, 300),
                    new Attention.VibeProfile(0, 150),
                    new Attention.VibeProfile(100, 300),
                    new Attention.VibeProfile(0, 150),
                    new Attention.VibeProfile(100, 300)
                ];
            } else {
                profile = [new Attention.VibeProfile(60, 200)];
            }
            Attention.vibrate(profile);
        }
        if (mAlertTone && (Attention has :playTone)) {
            Attention.playTone(off ? Attention.TONE_ALERT_HI : Attention.TONE_ALERT_LO);
        }
    }

    // ================= OSM streets =================
    // Installed on first launch into the watch storage (key "t" + tile number),
    // then read tile by tile around the position.

    private function tileKey(tx, ty) {
        return (tx + 5000) * 10000 + (ty + 5000);
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

    function isInstallingStreets() { return mUnpack >= 0; }

    private function updateTiles() as Void {
        if (!RoutePack.HAS_MAP || !mShowStreets || mZoom > STREETS_MAX_ZOOM) {
            if (mTileKeys.size() > 0) {
                mTileKeys = [] as Array<Number>;
                mTileData = [] as Array<ByteArray or Null>;
            }
            return;
        }
        var t = RoutePack.TILE;
        var r = mZoom * 1.3;
        var mx = mX - mMapOffX;
        var my = mY - mMapOffY;
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
        var keys = [] as Array<Number>;
        var data = [] as Array<ByteArray or Null>;
        var loaded = 0;
        for (var i = 0; i < need.size(); i++) {
            var k = need[i];
            var old = mTileKeys.indexOf(k);
            if (old >= 0) {
                keys.add(k);
                data.add(mTileData[old]);
                continue;
            }
            if (loaded >= 3 || System.getSystemStats().freeMemory < 8000) { continue; }
            var s = Storage.getValue("t" + k);
            keys.add(k);
            if (s instanceof String) {
                data.add(StringUtil.convertEncodedString(s, {
                    :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                    :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
                }));
                loaded++;
            } else {
                data.add(null);
            }
        }
        mTileKeys = keys;
        mTileData = data;
        if (loaded > 0) { startRender(); }
    }

    // ---------------- Background street drawing ----------------
    // Tile: for each line [point count, category], then x, y on 2 bytes (m from the corner).
    // Categories: 0 street, 1 main road, 2 path, 3 waterway or water body.

    // View centered on the runner (same as in draw()).
    private function setupLiveView(w, h) as Void {
        mVcx = w / 2.0;
        mVcy = h / 2.0;
        mVox = mDX;
        mVoy = mDY;
        mVk = (w / 2.0) / mZoom;
        mVc = 1.0;
        mVs = 0.0;
        if (mTrackUp) {
            mVcy = h * 0.60;
            if (mHeadingOk) {
                mVc = Math.cos(mDH);
                mVs = Math.sin(mDH);
            }
        }
    }

    private function streetsOn() {
        return mHasPos && RoutePack.HAS_MAP && mShowStreets && mZoom <= STREETS_MAX_ZOOM;
    }

    // Starts (or restarts) drawing the streets for the current position.
    function startRender() as Void {
        if (!mVisible || !streetsOn() || mTileKeys.size() == 0) { return; }
        if (mBmp[0] == null || mBmpBg != bg) {
            var pal = [bg, Graphics.COLOR_DK_BLUE, Graphics.COLOR_GREEN, 0x00FFFF];
            mBmp = [
                new Graphics.BufferedBitmap({:width => mW, :height => mH, :palette => pal}),
                new Graphics.BufferedBitmap({:width => mW, :height => mH, :palette => pal})
            ];
            mBmpBg = bg;
            mShow = -1;
        }
        setupLiveView(mW, mH);
        mJa = mVc * mVk;
        mJb = mVs * mVk;
        mJox = mVox;
        mJoy = mVoy;
        mJcx = mVcx;
        mJcy = mVcy;
        mJh = mDH;
        mJobKeys = mTileKeys;
        mJobData = mTileData;
        mJobTile = 0;
        mJobByte = 0;
        mJobCat = -1;
        mWork = (mShow == 0) ? 1 : 0;
        var bdc = mBmp[mWork].getDc();
        bdc.setColor(bg, bg);
        bdc.clear();
        if (!mJob) {
            mJob = true;
            if (mTimer == null) { mTimer = new Timer.Timer(); }
            mTimer.start(method(:renderStep), 50, true);
        }
    }

    // One step: about STEP_POINTS points, then yield (new task 50 ms later).
    function renderStep() as Void {
        if (!mJob) { return; }
        var dc = mBmp[mWork].getDc();
        var t = RoutePack.TILE;
        var a = mJa;
        var b = mJb;
        var w = mW;
        var h = mH;
        var budget = STEP_POINTS;
        var vis = (w + h) / 2.0 / mVk + t * 0.71;
        var vis2 = vis * vis;
        var cat = mJobCat;
        var nt = mJobKeys.size();

        while (mJobTile < nt && budget > 0) {
            var bytes = mJobData[mJobTile];
            var key = mJobKeys[mJobTile];
            var bx = (key / 10000 - 5000) * t + mMapOffX - mJox;
            var by = (key % 10000 - 5000) * t + mMapOffY - mJoy;
            var cxm = bx + t / 2;
            var cym = by + t / 2;
            if (bytes == null || cxm * cxm + cym * cym > vis2) {
                mJobTile++;
                mJobByte = 0;
                continue;
            }
            var ox = mJcx + bx * a - by * b;
            var oy = mJcy - bx * b - by * a;
            var n = bytes.size();
            var i = mJobByte;
            while (i + 1 < n && budget > 0) {
                var cnt = bytes[i];
                if (bytes[i + 1] != cat) {
                    cat = bytes[i + 1];
                    if (cat == 1) {
                        dc.setPenWidth(3);
                        dc.setColor(mStreetColor, Graphics.COLOR_TRANSPARENT);
                    } else if (cat == 2) {
                        dc.setPenWidth(1);
                        dc.setColor(mPathColor, Graphics.COLOR_TRANSPARENT);
                    } else if (cat == 3) {
                        dc.setPenWidth(2);
                        dc.setColor(mWaterColor, Graphics.COLOR_TRANSPARENT);
                    } else {
                        dc.setPenWidth(1);
                        dc.setColor(mStreetColor, Graphics.COLOR_TRANSPARENT);
                    }
                }
                i += 2;
                budget -= cnt;
                // First point, then a line to each of the next ones (off screen: clipped by the watch).
                var X = (bytes[i] << 8) | bytes[i + 1];
                var Y = (bytes[i + 2] << 8) | bytes[i + 3];
                i += 4;
                var lx = ox + X * a - Y * b;
                var ly = oy - X * b - Y * a;
                for (var k = 1; k < cnt; k++) {
                    X = (bytes[i] << 8) | bytes[i + 1];
                    Y = (bytes[i + 2] << 8) | bytes[i + 3];
                    i += 4;
                    var sx = ox + X * a - Y * b;
                    var sy = oy - X * b - Y * a;
                    dc.drawLine(lx, ly, sx, sy);
                    lx = sx;
                    ly = sy;
                }
            }
            if (i + 1 < n) {
                mJobByte = i;               // tile not finished: resume here at the next step
            } else {
                mJobTile++;
                mJobByte = 0;
            }
        }
        mJobCat = cat;

        if (mJobTile >= nt) {
            mJob = false;
            mTimer.stop();
            mShow = mWork;
            mSX = mJox;
            mSY = mJoy;
            mSH = mJh;
            WatchUi.requestUpdate();
        }
    }

    // ================= Drawing =================

    // bottom: text shown at the bottom when there is no alert (pace, HR...), bottomColor its color.
    function draw(dc, bottom, bottomColor) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(bg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (mN < 2) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, mMessage,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawBottom(dc, w, h, bottom, bottomColor);
            return;
        }

        mW = w;
        mH = h;
        var live = mHasPos;
        mVcx = w / 2.0;
        mVcy = h / 2.0;
        mVox = mCenterX;
        mVoy = mCenterY;
        mVk = (w * 0.60) / mSpan;      // leaves room for the top and bottom texts
        mVc = 1.0;
        mVs = 0.0;
        if (live) {
            animate();
            setupLiveView(w, h);
            // Streets: bitmap pre-drawn in the background, shifted by the distance moved since.
            if (mShow >= 0 && streetsOn()) {
                var ox = toScreenX(mSX, mSY) - mVcx;
                var oy = toScreenY(mSX, mSY) - mVcy;
                dc.drawBitmap(ox.toNumber(), oy.toNumber(), mBmp[mShow]);
            }
        }
        drawRoute(dc, w, h, live);
        drawMarkers(dc);

        if (live) {
            if (mOffCourse || !mJoined) {
                dc.setPenWidth(2);
                dc.setColor(mOffCourse ? Graphics.COLOR_RED : accent, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(mVcx, mVcy, toScreenX(mDNX, mDNY), toScreenY(mDNX, mDNY));
            }
            drawArrow(dc, mVcx, mVcy);
            if (mTrackUp && mHeadingOk) {
                drawNorth(dc, w, h);
            }
        }

        // Top: remaining distance
        var top;
        if (!live) {
            top = Util.dist(mTotal);
        } else if (mTotal - mProgress < 25 && mSeg >= mN - 3) {
            top = mFinish;
        } else {
            top = Util.dist(mTotal - mProgress);
        }
        dc.setColor(fg, bg);
        dc.drawText(w / 2, h * 0.06, Graphics.FONT_SMALL, top, Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom: alert, otherwise the given text
        if (live && !mJoined) {
            drawBottom(dc, w, h, Lang.format(mRouteAway, [Util.dist(mOffDist)]), accent);
        } else if (live && mOffCourse) {
            drawBottom(dc, w, h, Lang.format(mOffCourseText, [mOffDist.toNumber()]), Graphics.COLOR_RED);
        } else if (!live && mWarning != null) {
            drawBottom(dc, w, h, mWarning, Graphics.COLOR_RED);
        } else {
            drawBottom(dc, w, h, bottom, bottomColor);
        }

        if (mOffCourse && live) {
            dc.setPenWidth(5);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(w / 2, h / 2, w / 2 - 2);
        }
    }

    private function drawBottom(dc, w, h, text, color) as Void {
        if (text == null) { return; }
        var font = Graphics.FONT_SMALL;
        if (dc.getTextWidthInPixels(text, font) > w * 0.55) { font = Graphics.FONT_XTINY; }
        var fh = dc.getFontHeight(font);
        dc.setColor(color, bg);
        dc.drawText(w / 2, h - fh - 16, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function toScreenX(x, y) {
        return mVcx + ((x - mVox) * mVc - (y - mVoy) * mVs) * mVk;
    }

    private function toScreenY(x, y) {
        return mVcy - ((x - mVox) * mVs + (y - mVoy) * mVc) * mVk;
    }

    private function drawRoute(dc, w, h, live) as Void {
        var m = 10;
        var split = live && mShowDone;
        var current = -1;
        var a = mVc * mVk;
        var b = mVs * mVk;
        var r = mRoute;
        // Visible radius around the view center, in meters.
        var vis = (w + h) / mVk;
        var vis2 = vis * vis;
        dc.setPenWidth(mLineWidth);

        var nb = mNb;
        for (var blk = 0; blk < nb; blk++) {
            if (blockDist2(blk, mVox, mVoy) > vis2) { continue; }
            var p0 = blk * BLOCK;
            var p1 = p0 + BLOCK;
            if (p1 > mN - 1) { p1 = mN - 1; }
            var lx = 0.0;
            var ly = 0.0;
            for (var i = p0; i <= p1; i++) {
                var o = i * REC;
                var X = (r[o] << 16) | (r[o + 1] << 8) | r[o + 2];
                if (X >= 0x800000) { X -= 0x1000000; }
                var Y = (r[o + 3] << 16) | (r[o + 4] << 8) | r[o + 5];
                if (Y >= 0x800000) { Y -= 0x1000000; }
                X = X - mVox;
                Y = Y - mVoy;
                var sx = mVcx + X * a - Y * b;
                var sy = mVcy - X * b - Y * a;

                if (i > p0
                    && !(lx < -m && sx < -m) && !(lx > w + m && sx > w + m)
                    && !(ly < -m && sy < -m) && !(ly > h + m && sy > h + m)) {
                    var seg = i - 1;
                    if (split && seg == mSeg) {
                        var qx = toScreenX(mDNX, mDNY);
                        var qy = toScreenY(mDNX, mDNY);
                        dc.setColor(mDoneColor, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(lx, ly, qx, qy);
                        dc.setColor(mRouteColor, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(qx, qy, sx, sy);
                        current = mRouteColor;
                    } else {
                        var col = (split && seg < mSeg) ? mDoneColor : mRouteColor;
                        if (col != current) {
                            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                            current = col;
                        }
                        dc.drawLine(lx, ly, sx, sy);
                    }
                }
                lx = sx;
                ly = sy;
            }
        }
    }

    private function drawMarkers(dc) as Void {
        var last = mN - 1;
        var ex = toScreenX(px(last), py(last));
        var ey = toScreenY(px(last), py(last));
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(ex - 5, ey - 5, 11, 11);

        var bx = toScreenX(px(0), py(0));
        var by = toScreenY(px(0), py(0));
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(bx, by, 7);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(bx, by, 5);
    }

    private function drawArrow(dc, cx, cy) as Void {
        if (!mHeadingOk) {
            dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 9);
            dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 7);
            return;
        }
        var a = mTrackUp ? 0.0 : mDH;
        var ca = Math.cos(a);
        var sa = Math.sin(a);
        var shape = [[0, -12], [9, 10], [0, 5], [-9, 10]];
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotate(shape, cx, cy, ca, sa, 1.4));
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotate(shape, cx, cy, ca, sa, 1.0));
    }

    private function rotate(shape, cx, cy, ca, sa, k) {
        var out = new [shape.size()];
        for (var i = 0; i < shape.size(); i++) {
            var x = shape[i][0] * k;
            var y = shape[i][1] * k;
            out[i] = [cx + x * ca - y * sa, cy + x * sa + y * ca];
        }
        return out;
    }

    private function drawNorth(dc, w, h) as Void {
        var r = w * 0.40;
        var nx = w / 2.0 - mVs * r;
        var ny = h / 2.0 - mVc * r;
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(nx, ny, 9);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(nx, ny, Graphics.FONT_XTINY, "N",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
