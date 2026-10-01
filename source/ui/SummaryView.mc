import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Summary shown after saving. BACK or START to exit.
class SummaryView extends WatchUi.View {

    private var mTime;
    private var mDist;
    private var mAvgSpeed;              // already formatted: pace or km/h
    private var mUnit;
    private var mTitle;
    private var mLarge = null;
    private var mMedium = null;

    function initialize(summary) {
        View.initialize();
        mTime = summary[0];
        mDist = summary[1];
        mAvgSpeed = summary[2];
        mUnit = summary[3];
        mTitle = summary[4];
    }

    function onLayout(dc as Graphics.Dc) as Void {
        mLarge = WatchUi.loadResource(Rez.Fonts.DigitsLarge);
        mMedium = WatchUi.loadResource(Rez.Fonts.DigitsMedium);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var c = Graphics.TEXT_JUSTIFY_CENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawCircle(w / 2, h / 2, w / 2 - 3);
        dc.drawText(w / 2, 20, Graphics.FONT_XTINY, mTitle, c);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 44, mLarge, Util.km(mDist), c);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 100, Graphics.FONT_XTINY, "km", c);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.32, 124, mMedium, Util.time(mTime), c);
        dc.drawText(w * 0.68, 124, mMedium, mAvgSpeed, c);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.32, 158, Graphics.FONT_XTINY, Util.str(Rez.Strings.Time), c);
        dc.drawText(w * 0.68, 158, Graphics.FONT_XTINY, mUnit, c);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h - 34, Graphics.FONT_XTINY, Util.str(Rez.Strings.BackToExit), c);
    }
}

// BACK or START: exit the app.
class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        System.exit();
    }

    function onSelect() as Boolean {
        System.exit();
    }
}
