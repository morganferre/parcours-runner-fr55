import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch test (v1.2 prototype): can the app download through the phone, how big can an answer
// be, and how much storage is left for routes? Results are shown on the screen.
// To use it: copy this file into source/, add <iq:uses-permission id="Communications"/> to
// manifest.xml and make ParcoursRunnerApp.getInitialView() return
// [new NetTestView(), new NetTestDelegate()]. Never leave it in source/ for a real build.
// Raw address of a gist holding test_2k.txt ... test_64k.txt (any text of that size).
const NET_TEST_URL = "https://gist.githubusercontent.com/<user>/<gist id>/raw/";
const NET_TEST_SIZES = [2, 8, 16, 32, 64];

class NetTestView extends WatchUi.View {

    private var mLines = [] as Array<String>;
    private var mStep = 0;
    private var mStart = 0;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        if (mStep == 0) {
            mLines.add("Net test...");
            next();
        }
    }

    private function next() as Void {
        if (mStep < NET_TEST_SIZES.size()) {
            mStart = System.getTimer();
            Communications.makeWebRequest(NET_TEST_URL + "test_" + NET_TEST_SIZES[mStep] + "k.txt", null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            }, method(:onReceive));
        } else {
            storageTest();
        }
    }

    function onReceive(code as Number, data as String or Null) as Void {
        var ms = System.getTimer() - mStart;
        var len = (data instanceof String) ? data.length() : -1;
        data = null;
        var free = System.getSystemStats().freeMemory / 1024;
        mLines.add(NET_TEST_SIZES[mStep] + "k: " + code + " " + len + " " + ms + "ms f" + free);
        mStep++;
        WatchUi.requestUpdate();
        next();
    }

    // Fills the storage with 8 KB values until it refuses, then removes them.
    private function storageTest() as Void {
        var chunk = "";
        for (var i = 0; i < 64; i++) { chunk += "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; }
        var n = 0;
        try {
            for (n = 0; n < 60; n++) { Storage.setValue("probe" + n, chunk); }
        } catch (e) {
            mLines.add("store err " + e.getErrorMessage());
        }
        mLines.add("store 8k x" + n + " = " + (n * 8) + "k");
        for (var i = 0; i <= n; i++) {
            try { Storage.deleteValue("probe" + i); } catch (e) { }
        }
        // One big value
        try {
            Storage.setValue("probeBig", chunk + chunk);
            mLines.add("store 16k: ok");
        } catch (e) {
            mLines.add("store 16k: err");
        }
        try { Storage.deleteValue("probeBig"); } catch (e) { }
        mLines.add("done");
        mStep = 99;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var y = 30;
        for (var i = 0; i < mLines.size(); i++) {
            dc.drawText(dc.getWidth() / 2, y, Graphics.FONT_XTINY, mLines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += 16;
        }
    }
}

class NetTestDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }
}
