import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Settings access, translated texts and formatting of displayed values.
module Util {

    function readValue(key) {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    function readNum(key, def) {
        var v = readValue(key);
        if (v instanceof Number) { return v; }
        if (v instanceof Float || v instanceof Double || v instanceof Long) { return v.toNumber(); }
        if (v instanceof String) {
            var n = v.toNumber();
            if (n != null) { return n; }
        }
        return def;
    }

    function readBool(key, def) {
        var v = readValue(key);
        if (v instanceof Boolean) { return v; }
        return def;
    }

    function write(key, value) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
        }
    }

    // Text in the watch language (resources/strings or resources-fre/strings).
    function str(id) {
        return WatchUi.loadResource(id);
    }

    // Translated text with values in place of $1$, $2$...
    function fmt(id, values) {
        return Lang.format(WatchUi.loadResource(id), values);
    }

    // 754000 ms -> "12:34", 4354000 ms -> "1:12:34"
    function time(ms) {
        if (ms == null || ms < 0) { ms = 0; }
        var s = ms / 1000;
        var h = s / 3600;
        var m = (s / 60) % 60;
        var sec = s % 60;
        if (h > 0) {
            return h + ":" + m.format("%02d") + ":" + sec.format("%02d");
        }
        return m + ":" + sec.format("%02d");
    }

    // Pace in min/km from a speed in m/s: 3.2 -> "5:12"
    function pace(speed) {
        if (speed == null || speed < 0.6) { return "--:--"; }   // slower than 28 min/km: standing still
        var s = (1000.0 / speed).toNumber();
        return (s / 60) + ":" + (s % 60).format("%02d");
    }

    // Speed in km/h from a speed in m/s: 6.94 -> "25.0"
    function kmh(speed) {
        if (speed == null || speed < 0.6) { return "--.-"; }
        return (speed * 3.6).format("%.1f");
    }

    // 12345.6 m -> "12.35"
    function km(meters) {
        if (meters == null) { meters = 0; }
        return (meters / 1000.0).format("%.2f");
    }

    // Angle brought back between -pi and pi (radians).
    function angle(a) {
        while (a > Math.PI) { a -= 2 * Math.PI; }
        while (a < -Math.PI) { a += 2 * Math.PI; }
        return a;
    }

    // Readable distance: "850 m" or "3.4 km"
    function dist(meters) {
        if (meters >= 1000) {
            return (meters / 1000.0).format("%.1f") + " km";
        }
        return meters.toNumber() + " m";
    }
}
