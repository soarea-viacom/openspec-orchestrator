# Drive game v2 — shared change prompt

Second round of the side-by-side. Paste the block below verbatim as the first message in
each of the two surviving folders: `~/temp/test-fable` (raw Fable, formerly `test-sdd`)
and `~/temp/test-grill` (orchestrator, engine 1.14.0 or later). `test-raw` is retired.

Same rules as v1: identical text, same top-level model on both, one run at a time, record
human wait separately. For the orchestrator run the only interruptions are the ones its
process makes mandatory.

```
Extend the browser car-driving game in this folder. v2.

Make every decision yourself. The only acceptable interruptions are those your own
process makes mandatory. You may use subagents. Stop only when every item in the
checklist below passes and all tests are green. Keep every v1 behaviour working; the
v1 checklist still applies.

1. Day and night. A natural cycle: sun arc, sky colour, ambient and directional light
   change together, dusk and dawn included. A full day lasts between 8 and 15 minutes
   of play — not a flash, not real time. It runs on both maps.

2. Car lights. Front headlights and rear tail lights as part of the car mesh, lit and
   unlit states visible from both views. Tail lights come on while braking. Reverse
   shows a small white light at the rear. Headlights come on automatically at night
   and off in the day; they cast light on the road ahead at night.

3. Speed-sensitive steering. At standstill and low speed the front wheels turn as
   they do now. As speed rises the steering lock shrinks smoothly, so the same key
   press turns the wheels less at high speed. The chase and cockpit views show the
   front wheels turning.

4. Collision. The car collides with every solid object in the world — buildings,
   trees, and anything else placed on a map — and never passes through one. A
   collision slows or stops the car; it does not launch it.

5. Hills. Offroad areas get rolling hills the car drives over, with suspension
   responding to them; roads and city blocks stay level and join the terrain without
   gaps or floating edges.

Tests, all under `npm test`, all green before you stop: unit tests for the day cycle
(time maps to sun position and light levels, both ends of the cycle), for the light
state machine (brake, reverse, night), for steering lock against speed, for collision
(a car driving at a building stops; one driving at a tree stops), and for hill height
sampling. Playwright: a screenshot at midday and one at night from the chase view,
one of the car braking at night showing lit tail lights and headlights, and one of
the car on a hill. knip stays clean. README gains one short section per item above.

Checklist (every item must pass):
 1. `npm install && npm run build && npm test` succeed from a clean clone.
 2. The v1 checklist still passes.
 3. The sky and lighting change over a few minutes of play, through dusk and dawn.
 4. Headlights turn on at night by themselves and light the road ahead.
 5. Tail lights light while braking; a white reverse light shows while reversing.
 6. Front wheels visibly turn less at high speed than at low speed.
 7. Driving into a building stops the car. Driving into a tree stops the car.
 8. Offroad areas have hills the car drives over; roads stay level and connected.
 9. Playwright produced the four screenshots named above and they show what they claim.
10. knip reports nothing.
```
