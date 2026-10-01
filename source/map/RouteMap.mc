import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;

const ANIM_MS = 1000;               // the view glides to the new GPS point in 1 s (GPS interval)

// The map screen: GPS position and heading, smooth movement between GPS points,
// and the drawing (streets, route, markers, arrow, texts).
// The route data is in Route, the route tracking in RouteTracker,
// the streets in StreetTiles (loading) and StreetLayer (background drawing).
class RouteMap {

    private var mRoute;
    private var mTracker;
    private var mTiles;
    private var mLayer;
    private var mInstaller;

    // --- Settings ---
    private var mZoom = 200;
    private var mTrackUp = true;
    private var mDark = true;
    private var mLineWidth = 3;
    private var mShowDone = true;
    private var mShowStreets = true;

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
    // to the last point (mX, mY, mHeading, nearest route point) over ANIM_MS, starting from mA*.
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

    // --- Current view ---
    private var mVox = 0.0;
    private var mVoy = 0.0;
    private var mVcx = 0.0;
    private var mVcy = 0.0;
    private var mVk = 1.0;
    private var mVc = 1.0;
    private var mVs = 0.0;
    private var mVh = 0.0;              // heading the view is rotated by (track-up)

    // --- Colors (the FR55 only shows 8 colors, no gray) ---
    var bg = Graphics.COLOR_BLACK;
    var fg = Graphics.COLOR_WHITE;
    var accent = Graphics.COLOR_YELLOW;
    var doneColor = Graphics.COLOR_PINK;
    private var mRouteColor = Graphics.COLOR_WHITE;

    // --- Texts drawn every frame, loaded once ---
    private var mFinish = "";
    private var mRouteAway = "";
    private var mOffCourseText = "";

    function initialize() {
        mFinish = Util.str(Rez.Strings.Finish);
        mRouteAway = Util.str(Rez.Strings.RouteAway);
        mOffCourseText = Util.str(Rez.Strings.OffCourse);
        mLayer = new StreetLayer();
        mInstaller = new RouteInstaller();
        mRoute = new Route(null);
        loadSettings();
    }

    // ================= Settings =================

    // All settings (phone): reloads the route.
    function loadSettings() as Void {
        mShowDone = Util.readBool("showDone", true);
        selectRoute(mRoute.id);
    }

    // Route chosen in the Routes menu (RouteStore id, null: none).
    function selectRoute(id) as Void {
        mRoute = new Route(id);
        mTracker = new RouteTracker(mRoute);
        mTiles = new StreetTiles(mRoute);
        mLayer.setTiles(mTiles);
        loadDisplay();
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

        // 8 colors only: blue streets, green paths, cyan water, already run magenta (black) / cyan (white).
        var waterColor;
        if (mDark) {
            bg = Graphics.COLOR_BLACK;
            fg = Graphics.COLOR_WHITE;
            accent = Graphics.COLOR_YELLOW;
            mRouteColor = Graphics.COLOR_WHITE;
            doneColor = Graphics.COLOR_PINK;
            waterColor = 0x00FFFF;
        } else {
            bg = Graphics.COLOR_WHITE;
            fg = Graphics.COLOR_BLACK;
            accent = Graphics.COLOR_PINK;           // (magenta arrow on a white background)
            mRouteColor = Graphics.COLOR_BLACK;
            doneColor = 0x00FFFF;
            waterColor = Graphics.COLOR_DK_BLUE;
        }
        mLayer.configure(streetsEnabled(), mZoom, mTrackUp, bg,
            Graphics.COLOR_DK_BLUE, Graphics.COLOR_GREEN, waterColor);
    }

    private function streetsEnabled() {
        return mRoute.hasStreets && mShowStreets && mZoom <= STREETS_MAX_ZOOM;
    }

    function hasRoute() { return mRoute.isValid(); }
    function progress() { return (mRoute.total > 0 && mTracker.joined) ? mTracker.progress / mRoute.total : 0.0; }
    function hasPosition() { return mHasPos; }
    function gpsQuality() { return mQuality; }
    function isOffCourse() { return mTracker.offCourse; }
    function remaining() { return mRoute.total - mTracker.progress; }
    function total() { return mRoute.total; }
    function zoom() { return mZoom; }
    function isInstallingStreets() { return mInstaller.isBusy(); }

    // ================= Position (each GPS point, once per second) =================

    function setPosition(info as Position.Info, running) as Void {
        mQuality = info.accuracy;
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_POOR) { return; }

        var deg = loc.toDegrees();
        var x = ((deg[1] - mRoute.lon0) * M_PER_DEG_LON * mRoute.cosLat0).toFloat();
        var y = ((deg[0] - mRoute.lat0) * M_PER_DEG_LAT).toFloat();

        var first = !mHasPos;
        var headingWasOk = mHeadingOk;
        animate();                      // position displayed right now: starting point of the glide
        updateHeading(x, y);
        mX = x;
        mY = y;
        mHasPos = true;

        if (mRoute.isValid()) {
            mTracker.update(x, y, running);
        }

        var dx = x - mDX;
        var dy = y - mDY;
        if (first || dx * dx + dy * dy > 200.0 * 200.0) {
            // First point or big jump: go there directly.
            mDX = x;
            mDY = y;
            mDNX = mTracker.nearX;
            mDNY = mTracker.nearY;
        }
        if (!headingWasOk) { mDH = mHeading; }
        mAX = mDX;
        mAY = mDY;
        mAH = mDH;
        mANX = mDNX;
        mANY = mDNY;
        mAT = System.getTimer();
        mAnimOn = dx * dx + dy * dy > 0.25 || Util.angle(mHeading - mDH).abs() > 0.01;
        followStreets();
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
            h = Util.angle(mHeading + Util.angle(h - mHeading) * 0.6);
        }
        mHeading = h;
        mHeadingOk = true;
        mRefX = x;
        mRefY = y;
    }

    // Moves the displayed position forward. Returns true until it reaches the last GPS point.
    function animate() {
        if (!mHasPos) { return false; }
        var f = (System.getTimer() - mAT) / ANIM_MS.toFloat();
        if (f > 1.0) { f = 1.0; } else if (f < 0.0) { f = 0.0; }
        mDX = mAX + (mX - mAX) * f;
        mDY = mAY + (mY - mAY) * f;
        mDNX = mANX + (mTracker.nearX - mANX) * f;
        mDNY = mANY + (mTracker.nearY - mANY) * f;
        mDH = Util.angle(mAH + Util.angle(mHeading - mAH) * f);
        return mAnimOn && f < 1.0;
    }

    // Tells the street layer where the view is; it redraws the streets if needed.
    private function followStreets() as Void {
        mLayer.follow(mDX, mDY, mDH, mTrackUp && mHeadingOk);
        mLayer.maybeRender();
    }

    // Called FPS times per second: true if the map screen must be redrawn.
    function frame() {
        if (!mVisible || !animate()) { return false; }
        followStreets();
        return true;
    }

    function setVisible(v) as Void {
        mVisible = v;
        mLayer.setVisible(v);
    }

    // Background tasks, once per second: street installation, then tile loading.
    function tick() as Void {
        if (mInstaller.isBusy()) {
            mInstaller.step();
            return;
        }
        if (mTiles.tick(mHasPos, mX, mY, mZoom, streetsEnabled())) {
            mLayer.startRender();
        }
    }

    // ================= Drawing =================

    // View centered on the runner, rotated by heading hd on a track-up map.
    private function setupLiveView(w, h, hd) as Void {
        mVcx = w / 2.0;
        mVcy = h / 2.0;
        mVox = mDX;
        mVoy = mDY;
        mVk = (w / 2.0) / mZoom;
        mVc = 1.0;
        mVs = 0.0;
        mVh = 0.0;
        if (mTrackUp) {
            mVcy = h * 0.60;
            if (mHeadingOk) {
                mVh = hd;
                mVc = Math.cos(hd);
                mVs = Math.sin(hd);
            }
        }
    }

    // bottom: text shown at the bottom when there is no alert (pace, HR...), bottomColor its color.
    function draw(dc, bottom, bottomColor) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(bg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (!mRoute.isValid()) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, mRoute.message,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawBottom(dc, w, h, bottom, bottomColor);
            return;
        }

        mLayer.setScreen(w, h);
        var tracker = mTracker;
        var live = mHasPos;
        // Overview before the GPS fix: the whole route.
        mVcx = w / 2.0;
        mVcy = h / 2.0;
        mVox = mRoute.centerX;
        mVoy = mRoute.centerY;
        mVk = (w * 0.60) / mRoute.span;      // leaves room for the top and bottom texts
        mVc = 1.0;
        mVs = 0.0;
        if (live) {
            animate();
            // Streets: bitmap pre-drawn in the background, shifted by the distance moved since.
            // The bitmap cannot be rotated, so the whole map (route included) keeps the heading
            // it was drawn with: route and streets turn together, only the arrow turns right away.
            var bmp = mLayer.shown();
            setupLiveView(w, h, bmp != null ? mLayer.shownH : mDH);
            if (bmp != null) {
                var ox = toScreenX(mLayer.shownX, mLayer.shownY) - mVcx;
                var oy = toScreenY(mLayer.shownX, mLayer.shownY) - mVcy;
                dc.drawBitmap(ox.toNumber(), oy.toNumber(), bmp);
            }
        }
        drawRoute(dc, w, h, live);
        drawMarkers(dc);

        if (live) {
            if (tracker.offCourse || !tracker.joined) {
                dc.setPenWidth(2);
                dc.setColor(tracker.offCourse ? Graphics.COLOR_RED : accent, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(mVcx, mVcy, toScreenX(mDNX, mDNY), toScreenY(mDNX, mDNY));
            }
            drawArrow(dc, mVcx, mVcy);
            if (mTrackUp && mHeadingOk) {
                drawNorth(dc, w, h);
            }
        }

        // Top: remaining distance
        var total = mRoute.total;
        var top;
        if (!live) {
            top = Util.dist(total);
        } else if (total - tracker.progress < 25 && tracker.seg >= mRoute.n - 3) {
            top = mFinish;
        } else {
            top = Util.dist(total - tracker.progress);
        }
        dc.setColor(fg, bg);
        dc.drawText(w / 2, h * 0.06, Graphics.FONT_SMALL, top, Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom: alert, otherwise the given text
        if (live && !tracker.joined) {
            drawBottom(dc, w, h, Lang.format(mRouteAway, [Util.dist(tracker.offDist)]), accent);
        } else if (live && tracker.offCourse) {
            drawBottom(dc, w, h, Lang.format(mOffCourseText, [tracker.offDist.toNumber()]), Graphics.COLOR_RED);
        } else if (!live && mRoute.warning != null) {
            drawBottom(dc, w, h, mRoute.warning, Graphics.COLOR_RED);
        } else {
            drawBottom(dc, w, h, bottom, bottomColor);
        }

        if (tracker.offCourse && live) {
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
        var route = mRoute;
        var m = 10;
        var split = live && mShowDone;
        var segNow = mTracker.seg;
        var current = -1;
        var a = mVc * mVk;
        var b = mVs * mVk;
        var r = route.data;
        var n = route.n;
        // Visible radius around the view center, in meters.
        var vis = (w + h) / mVk;
        var vis2 = vis * vis;
        dc.setPenWidth(mLineWidth);

        var nb = route.nb;
        for (var blk = 0; blk < nb; blk++) {
            if (route.blockDist2(blk, mVox, mVoy) > vis2) { continue; }
            var p0 = blk * BLOCK;
            var p1 = p0 + BLOCK;
            if (p1 > n - 1) { p1 = n - 1; }
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
                    if (split && seg == segNow) {
                        var qx = toScreenX(mDNX, mDNY);
                        var qy = toScreenY(mDNX, mDNY);
                        dc.setColor(doneColor, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(lx, ly, qx, qy);
                        dc.setColor(mRouteColor, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(qx, qy, sx, sy);
                        current = mRouteColor;
                    } else {
                        var col = (split && seg < segNow) ? doneColor : mRouteColor;
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

    // Finish (red square) and start (green dot).
    private function drawMarkers(dc) as Void {
        var route = mRoute;
        var last = route.n - 1;
        var ex = toScreenX(route.px(last), route.py(last));
        var ey = toScreenY(route.px(last), route.py(last));
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(ex - 5, ey - 5, 11, 11);

        var bx = toScreenX(route.px(0), route.py(0));
        var by = toScreenY(route.px(0), route.py(0));
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
        var a = mTrackUp ? mDH - mVh : mDH;
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
