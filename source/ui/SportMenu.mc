import Toybox.Lang;
import Toybox.WatchUi;

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
