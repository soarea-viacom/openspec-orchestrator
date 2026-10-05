# Drive game — reviewer prompt

Run in a fresh Fable session that built neither project. Give it the two repo paths
as A and B in random order; do not say which run produced which. Unblind after the
report.

```
You are reviewing two independent implementations of the same brief, in the two
folders below, labelled A and B. You did not build either and you do not know how
either was built. Grade both against the checklist, identically, with evidence.

For each repo:
 1. Clone to a temporary folder and run `npm install && npm run build && npm test`.
    Record exit codes, test counts (passed / failed / skipped), and knip output.
 2. Run `npm run dev` and drive the game for five minutes: both maps, both views,
    all three surfaces, fullscreen on and off, settings open and change, reset.
    Open the browser console and note every error.
 3. Grade each checklist item pass or fail. A pass names the evidence (command
    output, what you saw and did). A fail names what happened instead.
 4. List defects you found beyond the checklist, each with severity blocking /
    major / minor, file:line where you can, and a one-line reproduction.
 5. Measure: lines of source excluding tests and generated files, number of
    source files, number of dependencies and devDependencies, test file count,
    README line count.

Then compare: for each checklist item, which repo is better and why in one line,
or "same". Finish with the defect lists side by side and your overall verdict,
one paragraph, naming the single biggest difference.

Checklist:
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

Repo A: <path>
Repo B: <path>
```
