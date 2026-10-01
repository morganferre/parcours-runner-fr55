import Toybox.Application.Storage;
import Toybox.Lang;

const STORAGE_VERSION = 2;          // 1 (v1.1): a single route, tiles under "t" + tile number

// Copies the streets of the built-in routes into the watch storage, a few chunks per second,
// the first time a new set of routes (new app file) is launched.
// A route already installed (same id, same content) is not copied again.
class RouteInstaller {

    private var mBusy = false;
    private var mRoute = 0;             // route being installed
    private var mChunk = 0;             // next chunk of that route
    private var mKeys = null;           // tile numbers of that route

    function initialize() {
        var version = null;
        try { version = Storage.getValue("v"); } catch (e) { }
        if (version != STORAGE_VERSION) {
            // Storage of an older version: nothing worth keeping.
            try { Storage.clearValues(); } catch (e) { }
            try { Storage.setValue("v", STORAGE_VERSION); } catch (e) { }
        }
        var installed = null;
        try { installed = Storage.getValue("pack"); } catch (e) { }
        if (installed != null && installed.equals(RoutePack.PACK_ID)) { return; }

        // Streets of the routes that are no longer in the app.
        var old = null;
        try { old = Storage.getValue("builtins"); } catch (e) { }
        if (old instanceof Array) {
            for (var i = 0; i < old.size(); i++) {
                if (RoutePack.IDS.indexOf(old[i]) < 0) { RouteStore.deleteTiles(old[i]); }
            }
        }
        mBusy = true;
    }

    function isBusy() { return mBusy; }

    // Once per second: 3 chunks of about 4 KB.
    function step() as Void {
        for (var k = 0; k < 3 && mBusy; k++) { stepChunk(); }
    }

    private function stepChunk() as Void {
        if (mRoute >= RoutePack.COUNT) {
            finish();
            return;
        }
        var id = RoutePack.IDS[mRoute];
        if (mChunk == 0) {
            var done = null;
            try { done = Storage.getValue("k" + id); } catch (e) { }
            if (done != null) {             // already installed
                nextRoute();
                return;
            }
            mKeys = [];
        }
        if (mChunk >= RoutePack.CHUNKS[mRoute]) {
            try {
                Storage.setValue("k" + id, mKeys);
            } catch (e) {
                finish();
                return;
            }
            nextRoute();
            return;
        }
        var c = RoutePack.chunk(mRoute, mChunk);
        for (var i = 0; i + 1 < c.size(); i += 2) {
            try {
                Storage.setValue(RouteStore.tileKey(id, c[i]), c[i + 1]);
                mKeys.add(c[i]);
            } catch (e) {
                // Storage full: keep the streets already installed.
                try { Storage.setValue("k" + id, mKeys); } catch (e2) { }
                finish();
                return;
            }
        }
        mChunk++;
    }

    private function nextRoute() as Void {
        mRoute++;
        mChunk = 0;
        mKeys = null;
    }

    private function finish() as Void {
        try {
            Storage.setValue("builtins", RoutePack.IDS);
            Storage.setValue("pack", RoutePack.PACK_ID);
        } catch (e) { }
        mKeys = null;
        mBusy = false;
    }
}
