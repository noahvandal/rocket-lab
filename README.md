# Rocket Lab

Build a rocket, launch it, and land it back on the pad. Made with Godot 4.7, using the
Compatibility (WebGL 2) renderer, so it runs in desktop and mobile browsers.

## Play

1. **Build**: pick a nose (capsule, cone or flat), stack fuel tanks, and choose an engine type and
   how many (1–4). Add fins and landing legs. The panel shows thrust/weight and delta-v. It warns you
   if the rocket can't lift off or doesn't carry enough fuel for the mission.
2. **Launch**: a 3-2-1 countdown, then full throttle.
3. **Land**: reach the mission altitude, then come back down. With legs deployed you must touch
   down below 7 m/s and less than 14° of tilt. Without legs the limit is 2.5 m/s. The "BURN NOW!"
   warning tells you when to start your landing burn.

Missions: Hop (300 m), Skyline (3 km), Stratosphere (15 km), Edge of Space (50 km), and Kármán Line
(100 km, with re-entry plasma). Landing on the pad earns 3 stars. Best results are saved.

| Action | Keyboard | Touch / mouse |
|---|---|---|
| Throttle up / down | W / S (or Shift / Ctrl) | drag the throttle bar |
| Full / cut throttle | Z / X | |
| Steer | A / D (or arrows) | ◀ ▶ pads |
| Legs | G | LEGS button |
| Assist mode (Hold / Retro / Upright / Manual) | Q | assist button |
| Camera (chase / ground telephoto) | C | CAM button |
| Time warp | T | WARP button |
| Retry / back to builder | R / Esc | BUILD button |
| Orbit camera / zoom | drag / scroll wheel | drag on empty space |

**Retro** assist points the engines into your direction of travel, which helps a lot when landing
from high missions.

## Run locally

```bash
godot --path rocket_lab
```

## Web build

```bash
cd rocket_lab && godot --headless --export-release "Web" build/web/index.html
```

```bash
python3 -m http.server 8790 --directory rocket_lab/build/web
```

The export is single-threaded, so it needs no special COOP/COEP headers. Any static host works,
including itch.io, GitHub Pages, Netlify and Vercel. The game content is about 100 KB. Most of the
download is Godot's engine (`index.wasm`, about 10 MB gzipped, which the browser caches).

## Code

All visuals are generated in code, so there are no assets to load:

- `scripts/main.gd`: game states, input, camera, mission rules, scoring, save
- `scripts/rocket.gd`: rocket model built from parts, flight physics, flames, smoke, re-entry plasma
- `scripts/world.gd`: island terrain, ocean shader, sky shader (fades to stars in space), launch site
- `scripts/hud.gd` and `scripts/touch_controls.gd`: builder UI, telemetry, multitouch flight controls
- `scripts/parts.gd`: part catalogue and missions, which are easy to extend
- `scripts/sfx.gd`: synthesized engine rumble, explosion and beeps
- `tests/`: headless autopilot test (`godot --headless --path rocket_lab --script tests/sim_test.gd`)
  and screenshot scripts
