import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Timer;

// Simulator test: fake GPS points along the built-in route, 6 m per second (no need for
// Simulation > Activity Data). To use it, copy this file into source/ and add to
// ParcoursRunnerApp.onStart(): `mFeed = new DebugFeed();` (with `private var mFeed = null;`).
// Never leave it in source/ for a real build.
class DebugFeed {
    var mTimer;
    var mPts;
    var mN;
    var mLat0;
    var mLon0;
    var mCos;
    var mD = 0.0;
    var mLast = 0;

    function initialize() {
        var a = RoutePack.routeBin();
        mLat0 = a[0].toDouble() / 1000000.0d;
        mLon0 = a[1].toDouble() / 1000000.0d;
        mCos = Math.cos(mLat0 * Math.PI / 180.0d);
        mN = a[2];
        mPts = StringUtil.convertEncodedString(a[7], {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        mTimer = new Timer.Timer();
        mTimer.start(method(:step), 1000, true);
    }

    function g(o) {
        var v = (mPts[o] << 16) | (mPts[o + 1] << 8) | mPts[o + 2];
        if (v >= 0x800000) { v -= 0x1000000; }
        return v;
    }

    function step() as Void {
        mD += 6.0;
        var i = mLast;
        while (i < mN - 2 && g((i + 1) * 9 + 6) < mD) { i++; }
        mLast = i;
        var c0 = g(i * 9 + 6);
        var c1 = g((i + 1) * 9 + 6);
        var t = c1 > c0 ? (mD - c0) / (c1 - c0) : 0.0;
        if (t > 1.0) { t = 1.0; }
        var x = g(i * 9) + t * (g((i + 1) * 9) - g(i * 9));
        var y = g(i * 9 + 3) + t * (g((i + 1) * 9 + 3) - g(i * 9 + 3));
        var info = new Position.Info();
        info.accuracy = Position.QUALITY_GOOD;
        info.position = new Position.Location({
            :latitude => mLat0 + y / 110574.0d,
            :longitude => mLon0 + x / (111320.0d * mCos),
            :format => :degrees
        });
        var t0 = System.getTimer();
        getApp().onPosition(info);
        System.println("pos " + mD + " " + (System.getTimer() - t0) + "ms mem " + System.getSystemStats().usedMemory);
    }
}
