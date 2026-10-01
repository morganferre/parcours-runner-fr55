import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// Downloads one route of the secret gist through the phone (Garmin Connect), file by file
// (about 8 KB each, about 1 KB/s over Bluetooth). Format: see upload() in prepare_route.py.
// Each file is stored as soon as it arrives: after an error, retry() resumes at that file.
// The route only appears in the list once all its files are stored.
class RouteDownloader {

    // entry: [id, name, length m, file count, characters] (a line of index.txt)
    var name = "";
    var received = 0;                   // characters stored
    var total = 1;
    var error = null;                   // text to show, null: no error
    var done = false;

    private var mId;
    private var mLength;
    private var mFiles;
    private var mFile = 0;
    private var mKeys = [];
    private var mListener;              // object with a method onDownload() (redraw)
    private var mBusy = false;

    function initialize(entry, listener) {
        mId = entry[0];
        name = entry[1];
        mLength = entry[2];
        mFiles = entry[3];
        total = entry[4] > 0 ? entry[4] : 1;
        mListener = listener;
        RouteStore.removeData(mId);     // what a previous attempt left
    }

    function start() as Void {
        error = null;
        if (mBusy || done) { return; }
        mBusy = true;
        Communications.makeWebRequest(RouteStore.gistUrl(mId + "_" + mFile + ".txt"), null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        }, method(:onFile));
    }

    // BACK during the download: nothing is kept.
    function cancel() as Void {
        Communications.cancelAllRequests();
        mBusy = false;
        if (!done) { RouteStore.removeData(mId); }
    }

    function onFile(code as Number, data as String or Null) as Void {
        mBusy = false;
        if (code != 200 || !(data instanceof String)) {
            error = errorText(code);
            mListener.onDownload();
            return;
        }
        var stored = store(data);
        data = null;
        if (!stored) {
            RouteStore.removeData(mId);
            error = Util.str(Rez.Strings.ErrStorageFull);
            done = true;                // nothing to retry
            mListener.onDownload();
            return;
        }
        mFile++;
        if (mFile >= mFiles) {
            try {
                Storage.setValue("z" + mId, received);
                RouteStore.addDownloaded(mId, name, mLength);
            } catch (e) {
                RouteStore.removeData(mId);
                error = Util.str(Rez.Strings.ErrStorageFull);
            }
            done = true;
        } else {
            start();
        }
        mListener.onDownload();
    }

    // Lines "key=value": m (meta), p<j> (points), t<tile> (tile). False if the storage is full.
    private function store(text) {
        try {
            var nl = text.find("\n");
            while (nl != null) {
                var line = text.substring(0, nl);
                text = text.substring(nl + 1, text.length());
                nl = text.find("\n");
                var eq = line.find("=");
                if (eq == null || eq < 1) { continue; }
                var key = line.substring(0, eq);
                var value = line.substring(eq + 1, line.length());
                line = null;
                var kind = key.substring(0, 1);
                if (kind.equals("t")) {
                    var tile = key.substring(1, key.length()).toNumber();
                    if (tile == null) { continue; }
                    Storage.setValue(RouteStore.tileKey(mId, tile), value);
                    mKeys.add(tile);
                    Storage.setValue("k" + mId, mKeys);
                } else if (kind.equals("p")) {
                    Storage.setValue("p" + mId + "_" + key.substring(1, key.length()), value);
                } else if (kind.equals("m")) {
                    Storage.setValue("m" + mId, value);
                } else {
                    continue;
                }
                received += value.length();
            }
        } catch (e) {
            return false;
        }
        return true;
    }

    function errorText(code) {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return Util.str(Rez.Strings.ErrPhone);
        }
        return Util.fmt(Rez.Strings.ErrNetwork, [code]);
    }
}

// Reads index.txt of the gist: "PR1" then id|name|length|files|characters per line.
class RouteIndex {

    var entries = null;                 // [[id, name, length, files, characters], ...] once loaded
    var error = null;
    private var mListener;

    function initialize(listener) {
        mListener = listener;
    }

    function load() as Void {
        error = null;
        // Query string: avoids an old cached copy of the list.
        Communications.makeWebRequest(RouteStore.gistUrl("index.txt") + "?t=" + System.getTimer(), null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        }, method(:onIndex));
    }

    function onIndex(code as Number, data as String or Null) as Void {
        if (code != 200 || !(data instanceof String)) {
            error = code == Communications.BLE_CONNECTION_UNAVAILABLE
                ? Util.str(Rez.Strings.ErrPhone) : Util.fmt(Rez.Strings.ErrNetwork, [code]);
            mListener.onIndex();
            return;
        }
        var list = [];
        var lines = Util.split(data, "\n");
        data = null;
        for (var i = 1; i < lines.size(); i++) {
            var f = Util.split(lines[i], "|");
            if (f.size() < 5) { continue; }
            var length = f[2].toNumber();
            var files = f[3].toNumber();
            var size = f[4].toNumber();
            if (length == null || files == null || size == null) { continue; }
            list.add([f[0], f[1], length, files, size]);
        }
        entries = list;
        if (list.size() == 0) { error = Util.str(Rez.Strings.ErrNoRouteOnline); }
        mListener.onIndex();
    }
}
