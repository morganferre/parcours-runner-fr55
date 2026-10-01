import Toybox.Lang;
import Toybox.WatchUi;

// Menu rebuilt when the routes change (download, deletion) and it comes back on screen.
class LiveMenu extends WatchUi.Menu2 {

    private var mCount = 0;
    private var mSeen = -1;

    function initialize(title) {
        Menu2.initialize({:title => title});
    }

    // Items of the menu: subclasses add them with add().
    function fill() as Void {
    }

    function add(label, sub, id) as Void {
        addItem(new WatchUi.MenuItem(label, sub, id, {}));
        mCount++;
    }

    function rebuild() as Void {
        for (var i = mCount - 1; i >= 0; i--) { deleteItem(i); }
        mCount = 0;
        mSeen = RouteStore.version;
        fill();
    }

    function onShow() as Void {
        if (mSeen != RouteStore.version) { rebuild(); }
        Menu2.onShow();
    }
}

// ---------------- Routes menu (first screen when there are several routes or a gist) ----------------

class RouteMenu extends LiveMenu {

    function initialize() {
        LiveMenu.initialize(Util.str(Rez.Strings.MenuRoutes));
        rebuild();
    }

    function fill() as Void {
        var routes = RouteStore.list();
        var current = RouteStore.current(routes);
        var focus = 0;
        for (var i = 0; i < routes.size(); i++) {
            var r = routes[i];
            add(r[1], Util.dist(r[2]), r[0]);
            if (r[0].equals(current)) { focus = i; }
        }
        if (RouteStore.canDownload()) {
            add(Util.str(Rez.Strings.MenuDownload), null, :download);
        }
        if (routes.size() > 0) {
            add(Util.str(Rez.Strings.MenuManage),
                Util.fmt(Rez.Strings.StorageUse, [RouteStore.usedKb(), RouteStore.CAPACITY_KB]), :manage);
        }
        setFocus(focus);                        // last route used
    }
}

// Then the Sport menu. BACK here leaves the app (first view); BACK in the Sport menu
// or on the main view before the start comes back here.
class RouteMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        if (id == :download) {
            var view = new IndexView();
            WatchUi.pushView(view, new IndexDelegate(view), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :manage) {
            WatchUi.pushView(new ManageMenu(), new ManageMenuDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        RouteStore.setCurrent(id);
        getApp().map.selectRoute(id);
        WatchUi.pushView(sportMenu(), new SportMenuDelegate(), WatchUi.SLIDE_LEFT);
    }
}

// ---------------- Manage: delete a route ----------------

class ManageMenu extends LiveMenu {

    function initialize() {
        LiveMenu.initialize(Util.str(Rez.Strings.MenuManage));
        rebuild();
    }

    function fill() as Void {
        var routes = RouteStore.list();
        for (var i = 0; i < routes.size(); i++) {
            var r = routes[i];
            add(r[1], Util.fmt(Rez.Strings.SizeKb, [(RouteStore.sizeOf(r[0]) + 1023) / 1024]), r[0]);
        }
        if (routes.size() == 0) { add(Util.str(Rez.Strings.NoRoutes), null, :none); }
    }
}

class ManageMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) as Void {
        var id = item.getId();
        if (id == :none) { return; }
        WatchUi.pushView(new WatchUi.Confirmation(Util.fmt(Rez.Strings.ConfirmDelete, [item.getLabel()])),
            new ConfirmDeleteDelegate(id), WatchUi.SLIDE_UP);
    }
}

class ConfirmDeleteDelegate extends WatchUi.ConfirmationDelegate {

    private var mId;

    function initialize(id) {
        ConfirmationDelegate.initialize();
        mId = id;
    }

    // The menu underneath rebuilds itself when it comes back (RouteStore.version).
    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            RouteStore.deleteRoute(mId);
        }
        return true;
    }
}
