import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

const STEP_POINTS = 300;            // street points drawn per step. The watch kills the app beyond
                                    // about 700 points in a single task (measured in the simulator).
const REDRAW_PX = 6;                // streets redrawn once the view has moved this many pixels away
const REDRAW_ANGLE = 0.1;           // ...or turned this much (rad, about 6°)

// Streets pre-drawn in the background into two alternating bitmaps: one is shown while the
// other is being drawn, a few hundred points at a time so the watch stays responsive.
// The map tells where the view is (follow), the layer decides when a new drawing is needed.
class StreetLayer {

    private var mTiles = null;
    private var mBmp = [null, null];
    private var mBmpBg = -1;            // background color the bitmaps were created with
    private var mShow = -1;             // bitmap ready to show (-1: none)
    private var mWork = 0;              // bitmap being drawn
    private var mVisible = true;        // map screen displayed
    private var mTimer = null;

    // Position and heading of the displayed bitmap (route coordinates, m / rad).
    var shownX = 0.0;
    var shownY = 0.0;
    var shownH = 0.0;

    // --- Settings (configure) ---
    private var mOn = false;            // streets enabled at this zoom
    private var mZoom = 200;
    private var mTrackUp = true;
    private var mBg = Graphics.COLOR_BLACK;
    private var mStreetColor = Graphics.COLOR_DK_BLUE;
    private var mPathColor = Graphics.COLOR_GREEN;
    private var mWaterColor = 0x00FFFF;
    private var mW = 208;
    private var mH = 208;

    // --- Current view, given by the map (follow) ---
    private var mHasView = false;
    private var mX = 0.0;
    private var mY = 0.0;
    private var mHead = 0.0;
    private var mRotate = false;        // track-up map with a known heading

    // --- Drawing in progress ---
    private var mJob = false;
    private var mPending = false;       // a redraw was asked while drawing or off the map screen
    private var mJobKeys = null;
    private var mJobData = null;
    private var mJobTile = 0;
    private var mJobByte = 0;
    private var mJobX = 0;              // last point decoded in the current tile (m)
    private var mJobY = 0;
    private var mJobCat = -1;
    private var mJa = 0.0;              // view parameters frozen for the current drawing
    private var mJb = 0.0;
    private var mJk = 1.0;
    private var mJox = 0.0;
    private var mJoy = 0.0;
    private var mJcx = 0.0;
    private var mJcy = 0.0;
    private var mJh = 0.0;

    function initialize() {
    }

    function setTiles(tiles) as Void {
        mTiles = tiles;
        mShow = -1;
    }

    function configure(on, zoom, trackUp, bg, streetColor, pathColor, waterColor) as Void {
        mOn = on;
        mZoom = zoom;
        mTrackUp = trackUp;
        mBg = bg;
        mStreetColor = streetColor;
        mPathColor = pathColor;
        mWaterColor = waterColor;
        mShow = -1;
        startRender();
    }

    function setScreen(w, h) as Void {
        mW = w;
        mH = h;
    }

    // Where the map view is now (called each frame and at each GPS point).
    function follow(x, y, heading, rotate) as Void {
        mHasView = true;
        mX = x;
        mY = y;
        mHead = heading;
        mRotate = rotate;
    }

    // Bitmap to draw under the route, or null.
    function shown() {
        return (mShow >= 0 && mOn && mHasView) ? mBmp[mShow] : null;
    }

    // Street drawing only runs while the map screen is shown: on the other screens it would
    // keep the CPU busy for nothing and slow down the buttons.
    function setVisible(v) as Void {
        if (v == mVisible) { return; }
        mVisible = v;
        if (v) {
            if (mPending) {
                mPending = false;
                startRender();
            } else {
                maybeRender();
            }
        } else if (mJob) {
            mJob = false;
            mTimer.stop();
            mPending = true;
        }
    }

    // Redraws the streets only when the displayed bitmap no longer matches the view:
    // running in a straight line, that is every few seconds instead of every second.
    function maybeRender() as Void {
        if (mJob || !mVisible || !mHasView || !mOn) { return; }
        var redraw = mShow < 0;
        if (!redraw) {
            var k = mW / 2.0 / mZoom;
            var dx = (mX - shownX) * k;
            var dy = (mY - shownY) * k;
            redraw = dx * dx + dy * dy > REDRAW_PX * REDRAW_PX
                || (mRotate && Util.angle(mHead - shownH).abs() > REDRAW_ANGLE);
        }
        if (redraw) { startRender(); }
    }

    // Starts drawing the streets for the current view. A drawing in progress is never
    // thrown away: the new one starts when it is finished (or when the map screen comes back).
    function startRender() as Void {
        if (!mHasView || !mOn || mTiles == null || mTiles.keys.size() == 0) { return; }
        if (!mVisible || mJob) {
            mPending = true;
            return;
        }
        if (mBmp[0] == null || mBmpBg != mBg) {
            var pal = [mBg, Graphics.COLOR_DK_BLUE, Graphics.COLOR_GREEN, 0x00FFFF];
            mBmp = [
                new Graphics.BufferedBitmap({:width => mW, :height => mH, :palette => pal}),
                new Graphics.BufferedBitmap({:width => mW, :height => mH, :palette => pal})
            ];
            mBmpBg = mBg;
            mShow = -1;
        }
        // Same view as RouteMap.setupLiveView.
        var k = (mW / 2.0) / mZoom;
        var c = 1.0;
        var s = 0.0;
        mJh = 0.0;
        if (mRotate) {
            mJh = mHead;
            c = Math.cos(mHead);
            s = Math.sin(mHead);
        }
        mJa = c * k;
        mJb = s * k;
        mJk = k;
        mJox = mX;
        mJoy = mY;
        mJcx = mW / 2.0;
        mJcy = mTrackUp ? mH * 0.60 : mH / 2.0;
        mJobKeys = mTiles.keys;
        mJobData = mTiles.data;
        mJobTile = 0;
        mJobByte = 0;
        mJobX = 0;
        mJobY = 0;
        mJobCat = -1;
        mWork = (mShow == 0) ? 1 : 0;
        var bdc = mBmp[mWork].getDc();
        bdc.setColor(mBg, mBg);
        bdc.clear();
        mJob = true;
        if (mTimer == null) { mTimer = new Timer.Timer(); }
        mTimer.start(method(:renderStep), 50, true);
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
        var vis = (w + h) / 2.0 / mJk + t * 0.71;
        var vis2 = vis * vis;
        var cat = mJobCat;
        var nt = mJobKeys.size();

        while (mJobTile < nt && budget > 0) {
            var bytes = mJobData[mJobTile];
            var key = mJobKeys[mJobTile];
            var bx = (key / 10000 - 5000) * t - mJox;
            var by = (key % 10000 - 5000) * t - mJoy;
            var cxm = bx + t / 2;
            var cym = by + t / 2;
            if (bytes == null || cxm * cxm + cym * cym > vis2) {
                mJobTile++;
                mJobByte = 0;
                mJobX = 0;
                mJobY = 0;
                continue;
            }
            var ox = mJcx + bx * a - by * b;
            var oy = mJcy - bx * b - by * a;
            var n = bytes.size();
            var i = mJobByte;
            // Points are steps from the previous one (see encode_tile in prepare_route.py):
            // 1 byte from -64 to 63, otherwise 2 bytes. X, Y: last point of the tile (m).
            var X = mJobX;
            var Y = mJobY;
            var v;
            while (i < n && budget > 0) {
                var head = bytes[i];
                i++;
                var cnt = head & 63;
                if (head >> 6 != cat) {
                    cat = head >> 6;
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
                budget -= cnt;
                // First point, then a line to each of the next ones (off screen: clipped by the watch).
                v = bytes[i];
                if (v < 128) { X += v - 64; i++; } else { X += ((v & 127) << 8 | bytes[i + 1]) - 16384; i += 2; }
                v = bytes[i];
                if (v < 128) { Y += v - 64; i++; } else { Y += ((v & 127) << 8 | bytes[i + 1]) - 16384; i += 2; }
                var lx = ox + X * a - Y * b;
                var ly = oy - X * b - Y * a;
                for (var k = 1; k < cnt; k++) {
                    v = bytes[i];
                    if (v < 128) { X += v - 64; i++; } else { X += ((v & 127) << 8 | bytes[i + 1]) - 16384; i += 2; }
                    v = bytes[i];
                    if (v < 128) { Y += v - 64; i++; } else { Y += ((v & 127) << 8 | bytes[i + 1]) - 16384; i += 2; }
                    var sx = ox + X * a - Y * b;
                    var sy = oy - X * b - Y * a;
                    dc.drawLine(lx, ly, sx, sy);
                    lx = sx;
                    ly = sy;
                }
            }
            if (i < n) {
                mJobByte = i;               // tile not finished: resume here at the next step
                mJobX = X;
                mJobY = Y;
            } else {
                mJobTile++;
                mJobByte = 0;
                mJobX = 0;
                mJobY = 0;
            }
        }
        mJobCat = cat;

        if (mJobTile >= nt) {
            mJob = false;
            mTimer.stop();
            mShow = mWork;
            shownX = mJox;
            shownY = mJoy;
            shownH = mJh;
            if (mPending) {
                mPending = false;
                startRender();
            } else {
                maybeRender();
            }
            WatchUi.requestUpdate();
        }
    }
}
