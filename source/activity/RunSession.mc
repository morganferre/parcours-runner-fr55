import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

const STATE_READY = 0;
const STATE_RUNNING = 1;
const STATE_PAUSED = 2;
const STATE_DONE = 3;

const SPORT_RUN = 0;
const SPORT_BIKE = 1;

// Activity recording (FIT "Running" or "Cycling" activity, synced with Garmin Connect)
// and the displayed values: time, distance, paces (km/h when cycling), laps.
class RunSession {

    private var mSession = null;
    private var mState = STATE_READY;
    private var mBike = false;
    private var mAutoLap = 1000;        // m, 0 = off

    private var mSpeed = 0.0;           // smoothed speed (m/s)
    // Activity values read once per second in tick(): the screens reuse them
    // instead of asking the watch again for every number they draw.
    private var mInfo = null;

    // Current lap
    private var mLap = 1;
    private var mLapStartMs = 0;
    private var mLapStartDist = 0.0;

    // Last completed lap (shown for a few seconds)
    private var mLastNum = 0;
    private var mLastMs = 0;
    private var mLastDist = 0.0;
    private var mShowUntil = 0;

    function initialize() {
        loadSettings();
    }

    function loadSettings() as Void {
        mBike = Util.readNum("sport", SPORT_RUN) == SPORT_BIKE;
        mAutoLap = Util.readNum(autoLapKey(), autoLapDefault());
    }

    // Each sport keeps its own auto lap: 1 km laps make no sense on a bike.
    function autoLapKey() { return mBike ? "autoLapBike" : "autoLap"; }
    function autoLapDefault() { return mBike ? 5000 : 1000; }
    function isBike() { return mBike; }

    function state() { return mState; }
    function isRunning() { return mState == STATE_RUNNING; }
    function started() { return mState == STATE_RUNNING || mState == STATE_PAUSED; }

    // ---------------- Commands ----------------

    // SPORT_RUN or SPORT_BIKE, chosen in the menu shown when the app opens.
    function setSport(sport) as Void {
        Util.write("sport", sport);
        loadSettings();
    }

    function start() as Void {
        if (mSession == null) {
            mSession = ActivityRecording.createSession({
                :name => "Parcours Runner",
                :sport => mBike ? ActivityRecording.SPORT_CYCLING : ActivityRecording.SPORT_RUNNING,
                :subSport => ActivityRecording.SUB_SPORT_GENERIC
            });
        }
        mSession.start();
        mState = STATE_RUNNING;
        vibrate(200);
    }

    function pause() as Void {
        if (mSession != null && mSession.isRecording()) {
            mSession.stop();
        }
        mState = STATE_PAUSED;
        vibrate(200);
    }

    function resume() as Void {
        if (mSession != null) {
            mSession.start();
        }
        mState = STATE_RUNNING;
        vibrate(200);
    }

    function save() as Void {
        if (mSession != null) {
            if (mSession.isRecording()) { mSession.stop(); }
            mSession.save();
            mSession = null;
        }
        mState = STATE_DONE;
    }

    function discard() as Void {
        if (mSession != null) {
            if (mSession.isRecording()) { mSession.stop(); }
            mSession.discard();
            mSession = null;
        }
        mState = STATE_DONE;
    }

    // New lap (BACK button or auto lap)
    function lap() as Void {
        if (mState != STATE_RUNNING || mSession == null) { return; }
        mSession.addLap();
        mInfo = Activity.getActivityInfo();     // exact values at the button press
        var now = elapsedTime();
        var dist = distance();
        mLastNum = mLap;
        mLastMs = now - mLapStartMs;
        mLastDist = dist - mLapStartDist;
        mShowUntil = System.getTimer() + 6000;
        mLap++;
        mLapStartMs = now;
        mLapStartDist = dist;
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 250),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(100, 250)
            ]);
        }
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_LAP);
        }
    }

    // Once per second
    function tick() as Void {
        var info = Activity.getActivityInfo();
        mInfo = info;
        if (info == null) { return; }
        var v = info.currentSpeed;
        if (v == null) { v = 0.0; }
        // Smoothing: 1 Hz GPS makes the instant pace jump around.
        mSpeed = mSpeed * 0.7 + v * 0.3;

        if (mState == STATE_RUNNING && mAutoLap > 0 && distance() - mLapStartDist >= mAutoLap) {
            lap();
        }
    }

    private function vibrate(ms) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, ms)]);
        }
    }

    // ---------------- Values ----------------

    // Latest values, read at the last tick (or now if no tick has happened yet).
    private function current() {
        if (mInfo == null) { mInfo = Activity.getActivityInfo(); }
        return mInfo;
    }

    function elapsedTime() {
        var info = current();
        if (info == null || info.timerTime == null) { return 0; }
        return info.timerTime;
    }

    function distance() {
        var info = current();
        if (info == null || info.elapsedDistance == null) { return 0.0; }
        return info.elapsedDistance;
    }

    function speed() { return mSpeed; }

    function averageSpeed() {
        var info = current();
        if (info == null) { return null; }
        return info.averageSpeed;
    }

    function heartRate() {
        var info = current();
        if (info == null) { return null; }
        return info.currentHeartRate;
    }

    function cadence() {
        var info = current();
        if (info == null) { return null; }
        return info.currentCadence;
    }

    // Speed shown as a pace (min/km) when running, in km/h when cycling.
    function speedText(speed) { return mBike ? Util.kmh(speed) : Util.pace(speed); }
    function speedUnit() { return mBike ? "km/h" : "/km"; }

    // Speed over a time (ms) and a distance (m), e.g. a lap.
    function speedOf(ms, meters) {
        if (meters == null || meters < 20 || ms == null || ms <= 0) { return speedText(null); }
        return speedText(meters / (ms / 1000.0));
    }

    function lapNumber() { return mLap; }
    function lapTime() { return elapsedTime() - mLapStartMs; }
    function lapDistance() { return distance() - mLapStartDist; }

    // Last lap to display, or null
    function lapPopup() {
        if (mLastNum == 0 || System.getTimer() > mShowUntil) { return null; }
        return [mLastNum, mLastMs, mLastDist];
    }
}
