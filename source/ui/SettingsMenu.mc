import Toybox.Lang;
import Toybox.WatchUi;

// ---------------- Settings menu (UP held) ----------------

const ZOOMS = [100, 200, 300, 500, 1000];
const AUTO_LAPS = [0, 500, 1000, 2000];
const AUTO_LAPS_BIKE = [0, 1000, 5000, 10000];

function zoomLabel() {
    return Util.readNum("zoom", 200) + " m";
}

function orientationLabel() {
    return Util.str(Util.readNum("orientation", 0) == 0 ? Rez.Strings.MenuTrackUp : Rez.Strings.OrientationNorth);
}

function themeLabel() {
    return Util.str(Util.readNum("theme", 0) == 0 ? Rez.Strings.ThemeDark : Rez.Strings.ThemeLight);
}

// Auto lap of the current sport (the last one chosen at the start).
function autoLapLabel() {
    var run = getApp().run;
    var v = Util.readNum(run.autoLapKey(), run.autoLapDefault());
    if (v == 0) { return Util.str(Rez.Strings.AutoLapOff); }
    return Util.dist(v);
}

function openSettingsMenu() as Void {
    var menu = new WatchUi.Menu2({:title => Util.str(Rez.Strings.MenuSettings)});
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuZoom), zoomLabel(), :zoom, {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuOrientation), orientationLabel(), :orientation, {}));
    menu.addItem(new WatchUi.ToggleMenuItem(Util.str(Rez.Strings.MenuStreets), null, :streets,
        Util.readBool("showStreets", true), {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuColors), themeLabel(), :theme, {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuAutoLap), autoLapLabel(), :autoLap, {}));
    WatchUi.pushView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
}

// Each press moves to the next value.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        if (id == :zoom) {
            Util.write("zoom", next(ZOOMS, Util.readNum("zoom", 200)));
            item.setSubLabel(zoomLabel());
        } else if (id == :orientation) {
            Util.write("orientation", 1 - Util.readNum("orientation", 0));
            item.setSubLabel(orientationLabel());
        } else if (id == :streets) {
            Util.write("showStreets", (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :theme) {
            Util.write("theme", 1 - Util.readNum("theme", 0));
            item.setSubLabel(themeLabel());
        } else if (id == :autoLap) {
            var run = getApp().run;
            Util.write(run.autoLapKey(), next(run.isBike() ? AUTO_LAPS_BIKE : AUTO_LAPS,
                Util.readNum(run.autoLapKey(), run.autoLapDefault())));
            item.setSubLabel(autoLapLabel());
        }
        var app = getApp();
        app.map.loadDisplay();
        app.run.loadSettings();
        WatchUi.requestUpdate();
    }

    private function next(values, current) {
        var i = values.indexOf(current);
        return values[(i + 1) % values.size()];
    }
}
