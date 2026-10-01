# Parcours Runner – Forerunner 55

**English** · [Français](README.fr.md)

Connect IQ app for the **Garmin Forerunner 55**: follow a GPX route on the watch,
with the surrounding OpenStreetMap streets, and record a real **Running** or **Cycling** activity
(synced with Garmin Connect and Strava: GPS, distance, pace or speed, heart rate, cadence, laps).

- route map with streets, paths and waterways, the part already run in color;
- alert (vibration + beep) when you leave the route;
- remaining distance, progress ring;
- 3 run screens (map, data, lap), auto lap;
- everything works offline: the route and streets are built into the app;
- watch texts in English or French, following the language set on the watch.

## Quick start

You need a Windows PC (the install scripts are PowerShell), a Forerunner 55 and a USB cable.

### 1. Install the tools (once)

1. **Python 3**: <https://www.python.org/downloads/> (tick "Add Python to PATH").
   No extra library is needed.
2. **Connect IQ SDK**: download the *SDK Manager* from
   <https://developer.garmin.com/connect-iq/sdk/>, then install the latest SDK
   and the **Forerunner 55** device from the SDK Manager.
3. **VS Code** + the **Monkey C** extension (by Garmin).
4. **Developer key**: in VS Code, `Ctrl+Shift+P` › `Monkey C: Generate a Developer Key`.
   It signs the app. Keep it **outside** the project and never share it:
   the scripts find it on their own through the VS Code settings.

### 2. Get the project

```
git clone https://github.com/morganferre/parcours-runner-fr55.git
cd parcours-runner-fr55
```

(or **Code › Download ZIP** on GitHub).

### 3. Prepare a route

Export your route as GPX (Garmin Connect, Strava, Komoot...), then in a terminal,
from the project folder:

```
python tools\prepare_route.py path\to\my_route.gpx
```

The script downloads the streets around the route (OpenStreetMap, internet connection needed),
builds them into the app and compiles `bin\ParcoursRunner.prg`.

Several routes: give several GPX at once. The watch then shows a **Routes** menu when the app
opens (the name comes from the file name, `_` replaced by spaces):

```
python tools\prepare_route.py tools\lake_loop.gpx tools\city_center.gpx tools\forest.gpx
```

The streets of all the routes must fit on the watch (about 110 KB): the script shows how much
each one takes.

Useful options:

| Option | Effect |
|---|---|
| `--width 400` | wider band of streets around the route (default 300 m) |
| `--points 2000` | more precise track (default: 60 points per km, up to 4,000) |
| `--reverse` | run the GPX in the opposite direction |
| `--flip-start` | out-and-back: start from the other end |
| `--name "Lake loop"` | route name (with a single GPX) |
| `--key path\developer_key` | developer key, if it is not set in VS Code |
| `--no-map` | go back to the version without a built-in route |

### 4. Install on the watch

Plug the watch in over USB, then:

```
powershell -ExecutionPolicy Bypass -File tools\install_watch.ps1
```

Or copy `bin\ParcoursRunner.prg` to `GARMIN\APPS` with File Explorer.
The app shows up in the activity list (START button from the watch face)
as **Parcours Runner**.

On the first launch of a new route, the watch stores the streets
(a few seconds, "Preparing streets..." at the bottom of the map).

To change the routes on the watch: run step 3 again with other GPX, then step 4.

## During the run

When the app opens, choose the **route** (if there are several), then **Running** or **Cycling**
(START each time; the last choices are preselected).
The GPS searches meanwhile. When cycling, paces are replaced by a speed in km/h and the auto lap
is separate (5 km by default).

| Button | Before the start | During the run | Paused |
|---|---|---|---|
| **START** | start | pause + menu | pause menu |
| **BACK** | back to the Routes menu (or exit) | new lap | pause menu |
| **UP / DOWN** | change screen | change screen | change screen |
| **UP held** | settings | settings | settings |

Pause menu: **Resume**, **Save** (summary then exit), **Discard** (with confirmation).

Screens:
1. **Map**: route, streets, remaining distance at the top, pace and heart rate at the bottom.
2. **Data**: time, distance, pace, heart rate.
3. **Lap**: time and pace of the current lap, lap distance, average pace.

Auto lap every km (every 5 km when cycling, adjustable): vibration and a "LAP 3" popup with the pace of that lap.

Settings (UP held): zoom, orientation, streets on/off, black or white background, auto lap.

## Good to know

- The FR55 only shows 8 colors. On a black background: route **white**, already run **magenta**
  (like the progress ring), streets **blue** (main roads thicker), paths **green**,
  waterways and lakes **cyan**, you in **yellow**, off course in **red**.
- Streets are drawn up to the 300 m zoom. In a very dense city, the farthest tiles
  may be missing: the watch limits drawing so it never exceeds the allowed time.
  If the script reports too many streets, run it again with `--width 200`.
- If the app is closed during a run (empty battery...), the run is saved automatically.
- An app copied over USB cannot be configured from the phone: use the UP-held menu.

## Test in the simulator

1. In VS Code: `Ctrl+Shift+P` › `Monkey C: Run`, choose **Forerunner 55**.
2. **Simulation › Activity Data**: load the same GPX as the prepared route, then **▶**.
3. Click the buttons drawn around the watch (START, BACK, UP, DOWN).

Change the language in the simulator with **Settings › Language**.

`tools\simulator.ps1` automates all this (build, launch, clicks, screenshots):

```
powershell -File tools\simulator.ps1 -Build -Run -Keys "down,start" -Shot test
```

## Languages

The watch texts live in `resources/strings/strings.xml` (English, the default language)
and `resources-fre/strings/strings.xml` (French). The watch picks one automatically from its language.

To add a language: copy `resources-fre` to `resources-<code>` (for example `resources-spa`
for Spanish, `resources-deu` for German), translate the texts, then add
`<iq:language><code></iq:language>` to `manifest.xml`.

## Code layout

```
source/ParcoursRunnerApp.mc        startup, GPS, heart rate, timer
source/Util.mc                     settings, translated texts, time and pace formatting
source/RoutePack.mc                GENERATED by tools/prepare_route.py (built-in route and streets)
source/activity/RunSession.mc      FIT recording (running or cycling), pause, laps, paces
source/route/Route.mc              route points (built in or pasted from the phone)
source/route/RouteTracker.mc       position on the route, progress, off-course alert
source/route/RouteStore.mc         routes on the watch, route chosen
source/route/RouteInstaller.mc     copies the streets of the routes to the watch (first launch)
source/map/RouteMap.mc             map screen: position, heading, animation, drawing
source/map/StreetTiles.mc          streets: install on the watch, tiles around the position
source/map/StreetLayer.mc          streets: background drawing into two alternating bitmaps
source/ui/MainView.mc              the 3 screens (map, data, lap)
source/ui/MainDelegate.mc          buttons
source/ui/RouteMenu.mc             route choice when the app opens (if there are several)
source/ui/SportMenu.mc             running / cycling choice when the app opens
source/ui/PauseMenu.mc             pause menu (resume, save, discard)
source/ui/SettingsMenu.mc          settings menu (UP held)
source/ui/SummaryView.mc           end summary
resources/route_pack/              GENERATED by tools/prepare_route.py (not versioned)
resources*/strings/                watch texts, per language
tools/                             route preparation, install, simulator, fonts, web converter
tools/debug/DebugFeed.mc           simulator test: fake ride along the route
```

`tools/converter.html` (open it in a browser) turns a GPX into text to paste into the
app settings from the phone: route only, without streets, and only if the app
was installed from the Connect IQ Store.

`tools/generate_fonts.py` regenerates the digit fonts (needs Pillow and the Windows
Bahnschrift font); only useful to change how they look.

## Map data

Streets come from [OpenStreetMap](https://www.openstreetmap.org/copyright)
© OpenStreetMap contributors, under the ODbL license, downloaded through the Overpass API.

## License

Code under the [MIT](LICENSE) license: free to use, modify and redistribute,
as long as the copyright notice is kept. Provided without warranty.
