import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

const PAGE_COUNT = 3;   // 0 = map, 1 = data, 2 = lap

// Digit position in the generated fonts (tools/generate_fonts.py):
// the top of a digit is LARGE_TOP px below the drawing point, and it is LARGE_H px tall.
const LARGE_TOP = 5;
const LARGE_H = 49;
const MEDIUM_TOP = 4;
const MEDIUM_H = 28;

// Main view: three screens scrolled with UP / DOWN.
class MainView extends WatchUi.View {

    private var mPage = 0;
    private var mLarge = null;
    private var mMedium = null;
    // Texts drawn every second, loaded once.
    private var mGpsOk = "";
    private var mGpsWeak = "";
    private var mGpsSearching = "";
    private var mPreparing = "";
    private var mPaused = "";
    private var mAverage = "";
    private var mLap = "";

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        mLarge = WatchUi.loadResource(Rez.Fonts.DigitsLarge);
        mMedium = WatchUi.loadResource(Rez.Fonts.DigitsMedium);
        mGpsOk = Util.str(Rez.Strings.GpsOk);
        mGpsWeak = Util.str(Rez.Strings.GpsWeak);
        mGpsSearching = Util.str(Rez.Strings.GpsSearching);
        mPreparing = Util.str(Rez.Strings.PreparingStreets);
        mPaused = Util.str(Rez.Strings.Paused);
        mAverage = Util.str(Rez.Strings.Average);
        mLap = Util.str(Rez.Strings.Lap);
    }

    // Hidden by a menu (pause, back to the Routes menu): no street drawing underneath.
    function onHide() as Void {
        getApp().map.setVisible(false);
    }

    function nextPage(step) as Void {
        mPage = (mPage + step + PAGE_COUNT) % PAGE_COUNT;
        getApp().map.setVisible(mPage == 0);     // right away: stops street drawing before the redraw
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var app = getApp();
        var map = app.map;
        var run = app.run;
        map.setVisible(mPage == 0);

        if (mPage == 0) {
            mapPage(dc, map, run);
        } else if (mPage == 1) {
            dataPage(dc, map, run);
        } else {
            lapPage(dc, map, run);
        }
        ring(dc, map, run);
        lapPopup(dc, map, run);
        pageDots(dc, map);
    }

    // ---------------- Screen 1: map ----------------

    private function mapPage(dc, map, run) as Void {
        var text;
        var color = map.fg;
        var state = run.state();
        if (map.isInstallingStreets()) {
            text = mPreparing;
            color = map.accent;
        } else if (state == STATE_READY) {
            text = gpsText(map);
            color = gpsColor(map);
        } else if (state == STATE_PAUSED) {
            text = mPaused;
            color = Graphics.COLOR_YELLOW;
        } else {
            text = run.speedText(run.speed());
            var hr = run.heartRate();
            if (hr != null) { text += "   " + hr; }
        }
        map.draw(dc, text, color);
    }

    // ---------------- Screen 2: data ----------------
    //   HR (heart)       top
    //   TIME             medium digits
    //   PACE /km         large digits, centered
    //   DISTANCE km      medium digits

    private function dataPage(dc, map, run) as Void {
        var w = dc.getWidth();
        background(dc, map);
        header(dc, map, run, w);

        centeredText(dc, map.fg, w / 2, 46, mMedium, Util.time(run.elapsedTime()));
        valueWithUnit(dc, map, w / 2, 81, mLarge, LARGE_TOP + LARGE_H, run.speedText(run.speed()), run.speedUnit());
        valueWithUnit(dc, map, w / 2, 146, mMedium, MEDIUM_TOP + MEDIUM_H, Util.km(run.distance()), "km");
    }

    // ---------------- Screen 3: lap ----------------
    //   LAP n            top
    //   lap time         medium digits
    //   lap pace         large digits
    //   average pace     medium digits

    private function lapPage(dc, map, run) as Void {
        var w = dc.getWidth();
        background(dc, map);

        dc.setColor(map.accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 17, Graphics.FONT_SMALL, Lang.format(mLap, [run.lapNumber()]),
            Graphics.TEXT_JUSTIFY_CENTER);

        var lapMs = run.lapTime();
        centeredText(dc, map.fg, w / 2, 46, mMedium, Util.time(lapMs));
        valueWithUnit(dc, map, w / 2, 81, mLarge, LARGE_TOP + LARGE_H,
            run.speedOf(lapMs, run.lapDistance()), run.speedUnit());
        valueWithUnit(dc, map, w / 2, 146, mMedium, MEDIUM_TOP + MEDIUM_H,
            run.speedText(run.averageSpeed()), mAverage);
    }

    // ---------------- Shared elements ----------------

    private function background(dc, map) as Void {
        dc.setColor(map.bg, map.bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
    }

    private function centeredText(dc, color, x, y, font, text) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Value + small unit in the accent color, aligned on the bottom of the digits, centered together.
    private function valueWithUnit(dc, map, x, y, font, digitBottom, value, unit) as Void {
        var wv = dc.getTextWidthInPixels(value, font);
        var wu = dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
        var x0 = x - (wv + 3 + wu) / 2;
        dc.setColor(map.fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(map.accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + wv + 3, y + digitBottom - Graphics.getFontAscent(Graphics.FONT_XTINY),
            Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Top of the Data screen: HR during the run, otherwise the state (GPS, pause).
    private function header(dc, map, run, w) as Void {
        var state = run.state();
        if (state == STATE_READY) {
            dc.setColor(gpsColor(map), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 20, Graphics.FONT_XTINY, gpsText(map), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (state == STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 17, Graphics.FONT_SMALL, mPaused, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var hr = run.heartRate();
        var text = hr == null ? "--" : hr.toString();
        var tw = dc.getTextWidthInPixels(text, Graphics.FONT_SMALL);
        var x0 = w / 2 - (tw + 18) / 2;
        heart(dc, x0 + 6, 31, 6);
        dc.setColor(map.fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + 18, 17, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function heart(dc, x, y, s) as Void {
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - s / 2, y - s / 3, s / 2 + 1);
        dc.fillCircle(x + s / 2, y - s / 3, s / 2 + 1);
        dc.fillPolygon([[x - s - 1, y - s / 4], [x + s + 1, y - s / 4], [x, y + s]]);
    }

    private function gpsText(map) {
        var q = map.gpsQuality();
        if (q >= Position.QUALITY_USABLE) { return mGpsOk; }
        if (q >= Position.QUALITY_POOR) { return mGpsWeak; }
        return mGpsSearching;
    }

    private function gpsColor(map) {
        var q = map.gpsQuality();
        if (q >= Position.QUALITY_USABLE) { return Graphics.COLOR_GREEN; }
        if (q >= Position.QUALITY_POOR) { return Graphics.COLOR_YELLOW; }
        return Graphics.COLOR_RED;
    }

    // Ring around the screen: progress along the route ("already run" color), yellow when paused.
    private function ring(dc, map, run) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = w / 2 - 3;
        dc.setPenWidth(5);
        if (run.state() == STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(w / 2, h / 2, r);
            return;
        }
        if (!map.hasRoute() || map.isOffCourse()) { return; }
        dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, r);
        var f = map.progress();
        if (f > 0.005) {
            if (f > 1.0) { f = 1.0; }
            dc.setColor(map.doneColor, Graphics.COLOR_TRANSPARENT);
            // 90° = 12 o'clock; clockwise
            dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, 90 - 360 * f);
        }
    }

    // Popup shown for 6 s at each new lap.
    private function lapPopup(dc, map, run) as Void {
        var t = run.lapPopup();
        if (t == null) { return; }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bw = 176;
        var bh = 112;
        var x = (w - bw) / 2;
        var y = (h - bh) / 2;
        dc.setColor(map.bg, map.bg);
        dc.fillRoundedRectangle(x, y, bw, bh, 10);
        dc.setColor(map.accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawRoundedRectangle(x, y, bw, bh, 10);

        dc.drawText(w / 2, y + 4, Graphics.FONT_XTINY, Lang.format(mLap, [t[0]]), Graphics.TEXT_JUSTIFY_CENTER);
        valueWithUnit(dc, map, w / 2, y + 20, mLarge, LARGE_TOP + LARGE_H, run.speedOf(t[1], t[2]), run.speedUnit());
        dc.setColor(map.fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + bh - 26, Graphics.FONT_XTINY,
            Util.time(t[1]) + "   " + Util.km(t[2]) + " km", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page indicator on the left edge.
    private function pageDots(dc, map) as Void {
        var h = dc.getHeight();
        for (var i = 0; i < PAGE_COUNT; i++) {
            var y = h / 2 + (i - 1) * 11;
            dc.setColor(map.fg, Graphics.COLOR_TRANSPARENT);
            if (i == mPage) {
                dc.fillCircle(17, y, 3);
            } else {
                dc.setPenWidth(1);
                dc.drawCircle(17, y, 2);
            }
        }
    }
}
