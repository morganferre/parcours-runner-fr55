import Toybox.Lang;
import Toybox.WatchUi;

// ---------------- Routes menu (first screen when there are several routes) ----------------

function routeMenu(routes) {
    var menu = new WatchUi.Menu2({:title => Util.str(Rez.Strings.MenuRoutes)});
    var current = RouteStore.current(routes);
    var focus = 0;
    for (var i = 0; i < routes.size(); i++) {
        var r = routes[i];
        menu.addItem(new WatchUi.MenuItem(r[1], r[2] == null ? null : Util.dist(r[2]), r[0], {}));
        if (r[0].equals(current)) { focus = i; }
    }
    menu.setFocus(focus);                       // last route used
    return menu;
}

// Then the Sport menu. BACK here leaves the app (first view); BACK in the Sport menu
// or on the main view before the start comes back here.
class RouteMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        RouteStore.setCurrent(id);
        getApp().map.selectRoute(id);
        WatchUi.pushView(sportMenu(), new SportMenuDelegate(), WatchUi.SLIDE_LEFT);
    }
}
