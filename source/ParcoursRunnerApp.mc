import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

const FPS = 6;              // frames per second on the map screen while moving
const FRAME_MS = 166;       // 1000 / FPS: keep both in sync

// Full app: route map + run screens + Garmin activity recording.
class ParcoursRunnerApp extends Application.AppBase {

    var map = null;
    var run = null;
    private var mTimer = null;
    private var mFrame = 0;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) as Void {
        map = new RouteMap();
        run = new RunSession();
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        }
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTick), FRAME_MS, true);
    }

    function onStop(state) as Void {
        // App closed during a run (low battery...): save it so nothing is lost.
        if (run != null && run.started()) {
            run.save();
        }
        if (mTimer != null) { mTimer.stop(); }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
    }

    function onPosition(info as Position.Info) as Void {
        map.setPosition(info, run.isRunning());
        WatchUi.requestUpdate();
    }

    // Every FRAME_MS: next map frame if it is moving; once per second: computations and screens.
    function onTick() as Void {
        mFrame++;
        if (mFrame >= FPS) {
            mFrame = 0;
            run.tick();
            map.tick();
            WatchUi.requestUpdate();
        } else if (map.frame()) {
            WatchUi.requestUpdate();
        }
    }

    // Routes menu (when there are several), then Sport menu, then the main view.
    function getInitialView() {
        var routes = RouteStore.list();
        if (routes.size() > 1) {
            return [routeMenu(routes), new RouteMenuDelegate()];
        }
        map.selectRoute(RouteStore.current(routes));
        return [sportMenu(), new SportMenuDelegate()];
    }

    // Settings changed from the Connect IQ phone app.
    function onSettingsChanged() as Void {
        map.loadSettings();
        run.loadSettings();
        WatchUi.requestUpdate();
    }
}

function getApp() as ParcoursRunnerApp {
    return Application.getApp() as ParcoursRunnerApp;
}
