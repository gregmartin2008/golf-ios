# Caddie: build instructions

These are the working instructions for building and changing this app. Read them before touching the code.

## What this is

Caddie is a private golf app for one player on one iPhone. It keeps score during the round on a
satellite map of each hole, records where every shot finished (by GPS or by touch), records every
putt's length, and turns that into the statistics TheGrint sells in its Pro tier, plus strokes
gained. It reads the player's Handicap Index, score history and official course ratings from GHIN
and can post a finished round to GHIN.

Fixed constraints, all decided by the owner:

- Costs nothing: no Apple Developer Program, no paid API, no paid hosting.
- Built on GitHub's macOS machines (the owner has a Windows PC and no Mac) and installed with
  iloader, which signs with a free Apple ID. So: no iCloud, no push, no App Groups, no app
  extensions, no Apple Watch target.
- One player. No partners' scores, no games, no backend.
- Default entry is "map every shot"; a hole can also be typed in quickly without the map.
- Every putt's length is entered.
- Public repository. It must never contain the owner's name, email, GHIN number, password, home
  courses or rounds. Tests and demo content use invented data and famous public courses only.

## Layout

```
project.yml                 XcodeGen project (the .xcodeproj is generated, never committed)
App/Sources                 SwiftUI app: screens, MapKit, location, Keychain
App/Resources               Asset catalog
Packages/CaddieCore         All logic. Foundation only. No UIKit, SwiftUI, MapKit or CoreLocation.
  Sources/CaddieCore
  Sources/caddie-check      Command-line tool: imports a real course from OpenStreetMap, prints coverage
  Tests/CaddieCoreTests
scripts/                    CI helpers (build, package, screenshots, publish)
.github/workflows/ci.yml
```

Rule: anything that can be decided without a screen lives in CaddieCore and has a unit test. The
app target holds views, the map, location, the Keychain and nothing else. This is what lets the
logic be tested with `swift test` on any machine.

## Language rules (there is no local compiler; GitHub is the compiler)

- Swift 5 language mode, `SWIFT_STRICT_CONCURRENCY: minimal`, deployment target iOS 17 API level
  (project target is set to match the build machine; do not use APIs newer than iOS 17).
- State: `ObservableObject` + `@Published`, one `AppModel` injected with `.environmentObject`.
  Do not use the `@Observable` macro, SwiftData, or Swift macros of any kind.
- The map is `MKMapView` wrapped in `UIViewRepresentable`. Do not use SwiftUI `Map`.
- No third-party packages.
- Every `public` type in CaddieCore that crosses into the app is `Codable` and `Equatable` where
  that is free. All stored models are plain structs.
- Async work uses `async/await` with `URLSession`. UI updates happen on the main actor
  (`AppModel` is `@MainActor`).
- Keep files under about 400 lines. Prefer explicit types over clever inference; long SwiftUI
  bodies are split into small computed views so the type checker does not time out.

## Data contract (CaddieCore/Models.swift)

Stored as JSON files in the app's Documents folder by `Store`: `courses.json`, `rounds.json`,
`bag.json`, `settings.json`. Writes are atomic. `Store.exportBackup()` returns one JSON file with
everything. Changing a stored field means adding it as optional or with a default in a custom
decoder; a build must always open the previous build's files.

- `Coordinate { lat, lon }`
- `Course { id, name, city, state, location, osmID?, ghinCourseID?, holes[9 or 18], tees[],
  features[], boundary[] }`
- `Hole { number, par, strokeIndex, tee?, greenCenter?, greenFront?, greenBack?, line[] }`
  `line` is the playing line from tee to green (OpenStreetMap's `golf=hole` way).
- `CourseFeature { id, kind (tee, fairway, green, bunker, water, rough), ring[], hole? }`
- `TeeSet { id, name, rating, slope, par, yards[], ghinTeeSetID?, gender? }`
- `Round { id, courseID, courseName, teeID?, teeName, rating, slope, par, date, holeCount,
  holes[], status (inProgress, finished), handicapIndexAtPlay?, isPractice, ghin (posted state),
  source (app, ghin), imported (adjusted gross and differential, for rounds read from GHIN) }`
- `HoleScore { number, par, strokeIndex, yards, marks[], putts[], holedFromOffGreen,
  quick? }`
- `BallMark { id, coordinate, lie, source (gps, touch, tee), accuracy?, club?, penaltyBefore? }`
  A mark is a spot the ball lay and a stroke was played from. Mark 0 is the tee.
  `penaltyBefore` is set on the mark where the ball was dropped or replayed after a penalty.
- `Putt { feet }` in order; the last one is the one that went in.
- `QuickEntry { strokes, putts, teeResult?, penaltyStrokes, sandShots, chips }` for a hole typed in
  without the map. When `quick` is set it wins over marks and putts.

### Counting strokes on a mapped hole

```
offGreen = marks whose lie is not green
strokes  = offGreen.count + putts.count + number of marks with penaltyBefore
```

Out of bounds or lost ball: add a second mark at the same spot with `penaltyBefore`. Water or
unplayable: add the drop spot as a mark with `penaltyBefore`. A hole is complete when it has putts
or `holedFromOffGreen` is true, or `quick` is set.

## Rules that must not drift (CaddieCore/HoleAnalyzer.swift)

- GIR: `(strokes − putts) ≤ (par − 2)`. Same as TheGrint.
- Fairway: par 4 and 5 only. Hit when the second mark's lie is fairway or green. Otherwise a miss,
  left or right by which side of the playing line the second mark is on. A second mark with
  `penaltyBefore` is a penalty off the tee.
- Lie from a point (`LieDetector`): green, then bunker, then water, then tee, then fairway; within
  3 m outside a green is fringe; anything else is rough. If the course has no outlines near the
  point the lie is `unknown` and the app asks.
- Approach shot: on a par 3 the tee shot; otherwise the first non-tee shot that starts more than
  30 yards from the green center. Its result is "green" or a miss short, long, left or right.
- Chip: a mark off the green within 30 yards of the green center. Sand shot: a mark in a bunker.
- Scramble: missed GIR and strokes ≤ par. Up-and-down: last off-green mark within 30 yards and
  one putt or none. Sand save: the same when that mark is in a bunker.
- Net double bogey (for handicap): `min(strokes, par + 2 + strokes received on the hole)`.
- Score differential: `(113 / slope) × (adjusted gross − rating)`, rounded to one decimal.
- Handicap index: World Handicap System table (lowest 1 of 3 minus 2.0 ... lowest 8 of 20),
  rounded to one decimal. Local value is labeled "estimate"; when GHIN is connected the GHIN value
  is shown instead.
- Strokes gained: Broadie's published PGA Tour table (tee, fairway, rough, sand, recovery in
  yards; green in feet), linear interpolation, clamped at the ends.
  `SG = expected(start) − expected(end) − 1 − penalty strokes`. Categories: off the tee (tee shots
  on par 4 and 5), approach (more than 30 yards), around the green (30 yards or less, off the
  green), putting. Always labeled "against the PGA Tour baseline".

## Course import (CaddieCore/OSM*.swift)

1. The app finds a point for the course (Apple's `MKLocalSearch`, or the phone's location).
2. One Overpass query within 3 km: `leisure=golf_course` outlines, `golf=hole` ways, and
   `golf=tee|fairway|green|bunker|water_hazard|lateral_water_hazard|rough`, plus `natural=water`.
3. Pick the course outline that contains the point (else the nearest). Keep only features whose
   center is inside that outline.
4. Each `golf=hole` way gives number (`ref`), par, stroke index (`handicap`) and the playing line.
   The tee is the line's first point; the green is the green outline nearest the line's last
   point. Front and back of the green are where the line from the previous point crosses it.
5. Each remaining feature is assigned to the hole whose line is nearest.
6. The result includes a coverage report (holes found, greens, tees, fairways, bunkers, water) that
   the app shows so the owner knows what to fix by hand.

A course with no mapped holes is still created (18 holes, par 4) and the owner places tee and green
points by long-pressing the map in the hole editor.

## GHIN (CaddieCore/GHIN.swift)

Unofficial: the same endpoints ghin.com uses, with the owner's own login. Field names follow the
MIT-licensed `n8io/ghin` client.

- Sign-in: Firebase installation token, then `POST /golfer_login.json`.
- Read: golfer (index, low index), scores (history), course search, course details (tee sets with
  rating, slope, par, stroke index and yardage per hole).
- Post: `POST /scores/hbh.json` hole by hole. Only ever sent from the confirmation screen, which
  shows the course, tee, date and every hole's score first. Never retried automatically. Never
  called from tests or CI. Until the owner has posted a real round, the README calls it unproven.
- The password lives in the Keychain only. Nothing about GHIN is logged.
- Every decoder is lenient (missing or renamed fields must not crash); failures show the server's
  message.

## Screens

Tabs: Play, Rounds, Stats, Courses, More.

- Play: start a round (course, tee, 9 or 18, starting hole) or resume. Then the hole screen: map
  on top, panel below with distances (front, center, back), the mark list, club picker, "Mark
  ball here" (GPS), putts entry, hole result, previous and next.
  Long-press on the map drops a mark there. Tap on the map measures (you → point → green). Marks
  can be dragged. Tapping a mark's row edits lie, club and penalty or deletes it.
- Putts: one row per putt, length in feet from a quick picker; "Holed out from off the green".
- Round summary: card, totals, derived stats, strokes gained, Finish, Post to GHIN.
- Rounds: list, detail with the shot map of each hole.
- Stats: scoring, driving, approach, putting, short game, penalties, strokes gained, clubs. Filter:
  last 5, 10, 20, all.
- Courses: list, add (search or near me), course detail (scorecard grid, tees, coverage, link to
  GHIN course), hole editor (place tee and green by long-press).
- More: handicap (GHIN or estimate, differentials table), GHIN sign-in and sync, bag, units,
  backup export and import.

## Demo mode and CI

Launching with `-demo <screen>` loads invented data in memory (never touching the Documents
folder) and opens that screen, so CI can photograph every screen in the simulator. Screens:
`home, hole, putts, summary, rounds, round, stats, courses, course, editor, handicap, ghin, bag`.

CI (`.github/workflows/ci.yml`), modeled on the owner's minutes-ios pipeline:

1. `core`: `swift test` in Packages/CaddieCore, then `caddie-check` against two famous public
   courses on live OpenStreetMap (a network failure there is reported, not fatal).
2. `app`: XcodeGen, simulator build, device build (unsigned), package `Caddie.ipa`, photograph
   every screen, publish the `.ipa` as the `latest` release only if everything passed.
3. Each job publishes its logs to a branch (`ci-core`, `ci-app`) so results can be read with
   `git fetch`.

## Definition of done for any change

- `swift test` passes on CI; the simulator and device builds succeed with no errors.
- No screen crashes in the screenshot run, and the pictures look right.
- Stored files from the previous build still open.
- README is updated if behavior the owner sees has changed. Plain English, American spelling.
