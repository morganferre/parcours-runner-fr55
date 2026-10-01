import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Where the runner is on the route (progress, nearest point) and the off-course alert.
class RouteTracker {

    private var mRoute;

    // --- Results, read by the map ---
    var seg = 0;                        // current segment (point seg -> seg + 1)
    var nearX = 0.0;                    // nearest point on the route (m)
    var nearY = 0.0;
    var offDist = 0.0;                  // distance to the route (m)
    var progress = 0.0;                 // distance along the route (m)
    var joined = false;                 // the runner has reached the route once
    var offCourse = false;

    // --- Settings ---
    private var mAlertOn = true;
    private var mAlertTone = true;
    private var mAlertDist = 40;

    private var mOffCount = 0;
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

    function initialize(route) {
        mRoute = route;
        mAlertOn = Util.readBool("alertOn", true);
        mAlertTone = Util.readBool("alertTone", true);
        mAlertDist = Util.readNum("alertDist", 40);
        if (mAlertDist < 10) { mAlertDist = 10; }
    }

    // Each GPS point (x, y in m from the route origin).
    function update(x, y, running) as Void {
        match(x, y);
        updateAlert(running);
    }

    // ================= Route matching =================
    // On an out-and-back or a self-crossing loop, several passes are at the same distance:
    // once on the route, prefer the one that follows the progress (no jump forward or backward).

    private function match(x, y) as Void {
        var route = mRoute;
        var last = route.n - 2;
        var now = System.getTimer();
        // 60 m + 7 m/s since the last point (GPS can drop out for a few seconds).
        mSlack = 60.0;
        if (mMatchMs > 0) { mSlack += (now - mMatchMs) * 0.007; }
        mMatchMs = now;
        mScored = joined;

        var from = seg - 5;
        if (from < 0) { from = 0; }
        var to = seg + 40;
        if (to > last) { to = last; }

        resetBest();
        scan(x, y, from, to);
        if (mBestD2 > mAlertDist * mAlertDist && (from > 0 || to < last)) {
            // Search the whole route, skipping blocks that are too far.
            resetBest();
            var nb = route.nb;
            for (var b = 0; b < nb; b++) {
                if (route.blockDist2(b, x, y) >= (mScored ? mBestS * mBestS : mBestD2)) { continue; }
                var s1 = b * BLOCK + BLOCK - 1;
                scan(x, y, b * BLOCK, s1 > last ? last : s1);
            }
            if (!joined) {
                // Not on the route yet: among passes that are almost as close,
                // take the earliest (on a loop, the start rather than the finish).
                var limit = Math.sqrt(mBestD2) + 15;
                limit = limit * limit;
                var found = false;
                for (var b = 0; b < nb && !found; b++) {
                    if (route.blockDist2(b, x, y) > limit) { continue; }
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

        seg = mBestSeg;
        nearX = mBestX;
        nearY = mBestY;
        offDist = Math.sqrt(mBestD2);
        var c0 = route.cum(seg);
        progress = c0 + mBestT * (route.cum(seg + 1) - c0);
    }

    private function resetBest() as Void {
        mBestD2 = 1.0e12;
        mBestS = 1.0e6;
        mRawD2 = 1.0e12;
    }

    // Segments from..to: keeps the best in mBest* and the closest in mRaw*
    // (without resetting them).
    private function scan(x, y, from, to) as Void {
        var route = mRoute;
        var r = route.data;
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
                var c0 = route.cum(i);
                var delta = c0 + t * (route.cum(i + 1) - c0) - progress;
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

    // ================= Off-course alert =================
    // Off course after 3 s beyond the alert distance, back on course below 70% of that distance.

    private function updateAlert(running) as Void {
        if (!joined) {
            if (offDist > mAlertDist) { return; }
            joined = true;
        }
        if (offDist > mAlertDist) {
            mOffCount++;
        } else if (offDist < mAlertDist * 0.7) {
            mOffCount = 0;
        }
        if (!offCourse && mOffCount >= 3) {
            offCourse = true;
            if (running) { alert(true); }
        } else if (offCourse && mOffCount == 0) {
            offCourse = false;
            if (running) { alert(false); }
        } else if (offCourse && running && mOffCount % 30 == 0) {
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
}
