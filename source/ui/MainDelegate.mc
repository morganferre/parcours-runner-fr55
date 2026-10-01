import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Forerunner 55 buttons:
//   START (top right)     : start / pause (Resume, Save, Discard menu)
//   BACK  (bottom right)  : new lap during the run, exit before the start
//   UP / DOWN (left)      : change screen
//   UP held               : map settings
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        var run = getApp().run;
        var state = run.state();
        if (state == STATE_READY) {
            run.start();
        } else if (state == STATE_RUNNING) {
            run.pause();
            openPauseMenu();
        } else if (state == STATE_PAUSED) {
            openPauseMenu();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var run = getApp().run;
        var state = run.state();
        if (state == STATE_RUNNING) {
            run.lap();
            WatchUi.requestUpdate();
            return true;
        }
        if (state == STATE_PAUSED) {
            openPauseMenu();
            return true;
        }
        return false;       // before the start: exits the app
    }

    function onNextPage() as Boolean {
        mView.nextPage(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        mView.nextPage(-1);
        return true;
    }

    function onMenu() as Boolean {
        openSettingsMenu();
        return true;
    }
}
