import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Forerunner 55 buttons:
//   START (top right)     : start / pause (Resume, Save, Discard menu)
//   BACK  (bottom right)  : new lap during the run, exit before the start
//   UP / DOWN (left)      : change screen
//   UP held               : map settings
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        var run = getApp().run;
        var state = run.state();
        if (state == STATE_READY) {
            run.start();
        } else if (state == STATE_RUNNING) {
            run.pause();
            openPauseMenu();
        } else if (state == STATE_PAUSED) {
            openPauseMenu();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var run = getApp().run;
        var state = run.state();
        if (state == STATE_RUNNING) {
            run.lap();
            WatchUi.requestUpdate();
            return true;
        }
        if (state == STATE_PAUSED) {
            openPauseMenu();
            return true;
        }
        return false;       // before the start: exits the app
    }

    function onNextPage() as Boolean {
        mView.nextPage(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        mView.nextPage(-1);
        return true;
    }

    function onMenu() as Boolean {
        openSettingsMenu();
        return true;
    }
}

// ---------------- Sport menu (first screen, the GPS searches meanwhile) ----------------

function sportMenu() {
    var menu = new WatchUi.Menu2({:title => Util.str(Rez.Strings.MenuSport)});
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.SportRun), null, SPORT_RUN, {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.SportBike), null, SPORT_BIKE, {}));
    menu.setFocus(Util.readNum("sport", SPORT_RUN) == SPORT_BIKE ? 1 : 0);     // last sport used
    return menu;
}

// BACK in this menu leaves the app (default behavior: it is the first view).
class SportMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        getApp().run.setSport(item.getId());
        var view = new MainView();
        WatchUi.switchToView(view, new MainDelegate(view), WatchUi.SLIDE_LEFT);
    }
}

// ---------------- Pause menu ----------------

function openPauseMenu() as Void {
    var menu = new WatchUi.Menu2({:title => Util.str(Rez.Strings.MenuPause)});
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuResume), null, :resume, {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuSave), null, :save, {}));
    menu.addItem(new WatchUi.MenuItem(Util.str(Rez.Strings.MenuDiscard), null, :discard, {}));
    WatchUi.pushView(menu, new PauseMenuDelegate(), WatchUi.SLIDE_UP);
}

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var run = getApp().run;
        var id = item.getId();
        if (id == :resume) {
            run.resume();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            var summary = [run.elapsedTime(), run.distance(), run.speedText(run.averageSpeed()), run.speedUnit(),
                Util.str(run.isBike() ? Rez.Strings.RideSaved : Rez.Strings.RunSaved)];
            run.save();
            WatchUi.switchToView(new SummaryView(summary), new SummaryDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :discard) {
            WatchUi.pushView(new WatchUi.Confirmation(Util.str(Rez.Strings.ConfirmDiscard)),
                new ConfirmDiscardDelegate(), WatchUi.SLIDE_UP);
        }
    }

    // BACK in the menu: stay paused.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ConfirmDiscardDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            getApp().run.discard();
            System.exit();
        }
        return true;
    }
}

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
