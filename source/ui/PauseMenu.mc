import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

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
