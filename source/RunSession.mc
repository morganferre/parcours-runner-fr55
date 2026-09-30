import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

const STATE_READY = 0;
const STATE_RUNNING = 1;
const STATE_PAUSED = 2;
const STATE_DONE = 3;

// Run recording (FIT "Running" activity, synced with Garmin Connect)
// and the displayed values: time, distance, paces, laps.
class RunSession {

    private var mSession = null;
    private var mState = STATE_READY;
    private var mAutoLap = 1000;        // m, 0 = off

    private var mSpeed = 0.0;           // smoothed speed (m/s)

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
        mAutoLap = Util.readNum("autoLap", 1000);
    }

    function state() { return mState; }
    function isRunning() { return mState == STATE_RUNNING; }
    function started() { return mState == STATE_RUNNING || mState == STATE_PAUSED; }

    // ---------------- Commands ----------------

    function start() as Void {
        if (mSession == null) {
            mSession = ActivityRecording.createSession({
                :name => "Parcours Runner",
                :sport => ActivityRecording.SPORT_RUNNING,
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

    function elapsedTime() {
        var info = Activity.getActivityInfo();
        if (info == null || info.timerTime == null) { return 0; }
        return info.timerTime;
    }

    function distance() {
        var info = Activity.getActivityInfo();
        if (info == null || info.elapsedDistance == null) { return 0.0; }
        return info.elapsedDistance;
    }

    function speed() { return mSpeed; }

    function averageSpeed() {
        var info = Activity.getActivityInfo();
        if (info == null) { return null; }
        return info.averageSpeed;
    }

    function heartRate() {
        var info = Activity.getActivityInfo();
        if (info == null) { return null; }
        return info.currentHeartRate;
    }

    function cadence() {
        var info = Activity.getActivityInfo();
        if (info == null) { return null; }
        return info.currentCadence;
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
