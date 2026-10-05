# Drive game — shared prompt

Paste the block below verbatim as the first message of each run. Both runs get the
same text; nothing else is said unless the agent's own process makes a question
mandatory.

Runs: separate empty folders, no CLAUDE.md in either, same top-level model and effort,
same commit of this engine repo, one after the other (orchestrator first, it needs you
at Gate 0 and Gate 2; the raw run can go unattended). Record human wait time
separately from machine time.

```
Build a browser car-driving game in this folder, from scratch, v1.

Make every decision yourself. The only acceptable interruptions are those your own
process makes mandatory. You may use subagents. Stop only when every item in the
checklist below passes and all tests are green.

Stack: a WebGL scene library of your choice with a physics engine that provides a
raycast vehicle, TypeScript, Vite. Static build, no backend, no login, no network
fetch at build or run time. Every asset is procedural or hand-coded in the repo:
textures from noise or patterns, buildings from primitives, trees from primitives,
car as a low-poly mesh you build with a visible interior. No downloaded asset packs.

World: two hand-authored finite maps, each roughly 2 by 2 km, each containing a
city-block area with static buildings, a highway loop, and an offroad area, with
sky and daylight. Surfaces: asphalt, tarmac, offroad (dirt, gravel). Realistic means
believable textures and lighting, not photoreal. Each surface has its own grip
coefficient and roughness and the car drives measurably differently on each; list
the values in a table in the README. Maps are described in a JSON format you
define and document in the README, loaded by a map loader; both maps selectable
from settings.

Car: raycast vehicle with suspension. Arcade feel is fine; surface response is not
optional.

Views: third-person chase camera and in-cockpit camera from the driver's seat, with
the interior mesh visible. No gauges, no dashboard readouts.

Out of scope for v1: traffic, pedestrians, any moving object other than the player
car, car damage, dashboard instruments, sound, multiplayer, deploy, CI.

Controls: Up throttle; Down brake, then reverse from standstill; Left and Right
steer; C toggles third-person and cockpit; F toggles fullscreen; R resets the car
upright onto the nearest road; Esc opens settings; P toggles an fps counter, the
one HUD element allowed.

Settings screen (Esc, pauses the game while open): rebind the five driving and view
keys, graphics quality low / medium / high (shadows and draw distance), map
selection. Persist in localStorage.

Runs in a normal window and in fullscreen, Chrome and Safari current. Target 60 fps
on an Apple-silicon Mac at 1440 by 900 on medium quality.

Tests, all run by `npm test` and all green before you stop: vitest unit tests for
vehicle and surface physics, map loading, settings persistence and key rebinding;
Playwright tests that load the game, drive for a few seconds, switch to each view,
and write a full-page screenshot per view; knip for dead code with zero findings.
Scripts: `npm install`, `npm run dev`, `npm run build`, `npm test`.

README under 80 lines: how to run, controls, map JSON format, surface table, how
to run tests.

Checklist (every item must pass):
 1. `npm install && npm run build && npm test` succeed from a clean clone.
 2. `npm run dev` serves the game; it loads with no console errors.
 3. Arrow keys drive the car: throttle, brake, reverse, steer.
 4. C switches between third-person and cockpit; cockpit shows the interior.
 5. F enters and leaves fullscreen; the game renders correctly in both.
 6. R resets an overturned or stuck car onto the nearest road.
 7. Both maps load and each has a city area, a highway loop, and offroad.
 8. Asphalt, tarmac and offroad look different and drive differently.
 9. Settings opens on Esc, pauses the game, rebinds keys, changes quality,
    switches map, and persists across reload.
10. P shows an fps counter; medium quality holds about 60 fps at 1440 by 900.
11. Playwright produced one screenshot per view and they show the scene.
12. knip reports nothing.
```
