import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Routes > Download: list of the routes of the secret gist (IndexView, then DownloadMenu),
// then the download of the chosen one with a progress bar (DownloadView).

// Small screen with a title, a text and a hint at the bottom.
function drawMessage(dc, title, text, color, hint) as Void {
    var w = dc.getWidth();
    var h = dc.getHeight();
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    dc.clear();
    if (title != null) {
        dc.drawText(w / 2, 40, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
    }
    if (text != null) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 22, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
    if (hint != null) {
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h - 50, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// ---------------- List of the routes online ----------------

class IndexView extends WatchUi.View {

    var index;

    function initialize() {
        View.initialize();
        index = new RouteIndex(self);
        index.load();
    }

    function onIndex() as Void {
        if (index.error == null) {
            WatchUi.switchToView(new DownloadMenu(index.entries), new DownloadMenuDelegate(index.entries),
                WatchUi.SLIDE_IMMEDIATE);
        } else {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (index.error == null) {
            drawMessage(dc, Util.str(Rez.Strings.MenuDownload), Util.str(Rez.Strings.Loading),
                Graphics.COLOR_WHITE, null);
        } else {
            drawMessage(dc, Util.str(Rez.Strings.MenuDownload), index.error, Graphics.COLOR_RED,
                Util.str(Rez.Strings.DlRetry));
        }
    }
}

class IndexDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        if (mView.index.error != null) {
            mView.index.load();
            WatchUi.requestUpdate();
        }
        return true;
    }
}

class DownloadMenu extends LiveMenu {

    private var mEntries;

    function initialize(entries) {
        mEntries = entries;
        LiveMenu.initialize(Util.str(Rez.Strings.MenuDownload));
        rebuild();
    }

    // "6.1 km  25 KB", or "installed".
    function fill() as Void {
        for (var i = 0; i < mEntries.size(); i++) {
            var e = mEntries[i];
            var sub = RouteStore.isOnWatch(e[0]) ? Util.str(Rez.Strings.Installed)
                : Util.dist(e[2]) + "  " + Util.fmt(Rez.Strings.SizeKb, [(e[4] + 1023) / 1024]);
            add(e[1], sub, i);
        }
    }
}

class DownloadMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var mEntries;

    function initialize(entries) {
        Menu2InputDelegate.initialize();
        mEntries = entries;
    }

    function onSelect(item) as Void {
        var view = new DownloadView(mEntries[item.getId()]);
        WatchUi.pushView(view, new DownloadDelegate(view), WatchUi.SLIDE_LEFT);
    }
}

// ---------------- Download of one route ----------------

class DownloadView extends WatchUi.View {

    var job;

    function initialize(entry) {
        View.initialize();
        job = new RouteDownloader(entry, self);
        job.start();
    }

    function onDownload() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (job.error != null) {
            drawMessage(dc, job.name, job.error, Graphics.COLOR_RED,
                job.done ? Util.str(Rez.Strings.DlOk) : Util.str(Rez.Strings.DlRetry));
            return;
        }
        if (job.done) {
            drawMessage(dc, job.name, Util.str(Rez.Strings.DlDone), Graphics.COLOR_GREEN,
                Util.str(Rez.Strings.DlOk));
            return;
        }
        drawMessage(dc, job.name, null, Graphics.COLOR_WHITE, null);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var f = job.received.toFloat() / job.total;
        if (f > 1.0) { f = 1.0; }
        var bw = w - 60;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(30, h / 2 - 8, bw, 16);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(32, h / 2 - 6, ((bw - 4) * f).toNumber(), 12);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 16, Graphics.FONT_XTINY,
            Util.fmt(Rez.Strings.StorageUse, [job.received / 1024, (job.total + 1023) / 1024]),
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class DownloadDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    // START: retry after an error, or close once finished.
    function onSelect() as Boolean {
        var job = mView.job;
        if (job.done) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (job.error != null) {
            job.start();
            WatchUi.requestUpdate();
        }
        return true;
    }

    // BACK: cancels a download in progress (nothing is kept).
    function onBack() as Boolean {
        mView.job.cancel();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
