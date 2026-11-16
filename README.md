# Caddie

A private golf app for iPhone. During a round it shows each hole on a satellite map with
yardages to the front, center and back of the green. You mark where each shot finished, by GPS
where you stand or by pressing on the map, and enter each putt's length. From that it keeps the
score and works out fairways hit, greens in regulation, scrambling, sand saves, putting by
distance, penalties, club distances and strokes gained. It reads your Handicap Index, score
history and official course ratings from GHIN and can post a finished round.

There is nothing to pay for: no subscription, no developer account, no paid service.

This repository holds the app's source and the automation that builds and tests it on GitHub's
Macs. It contains no account details, courses or rounds; the sample content in the app and the
tests is made up.

## What it does

- **Courses.** Search for a course by name or list the ones near you. Caddie draws it from
  OpenStreetMap: holes, tees, fairways, greens, bunkers and water where volunteers have mapped
  them. It tells you what the map has and what is missing; a missing tee or green is placed by
  pressing on the map. Linking a course to GHIN brings in its official tees, ratings, slopes,
  pars, stroke indexes and yardages.
- **Playing.** The hole fills the top of the screen, tee at the bottom, green at the top. Tap
  **Mark ball** at your ball, or long-press the map where it finished. Caddie works out the
  lie from the course map (fairway, rough, bunker, green) and you can change it. Tap anywhere to
  measure to that point and from there to the green. Penalties are one tap. On the green, enter
  each putt's length. A hole can also be typed in quickly without the map.
- **Statistics**, over the last 5, 10 or 20 rounds or all of them: scoring, driving, approach,
  putting (including how often you hole out from each distance), short game, penalties, club
  distances, and strokes gained off the tee, on approach, around the green and putting.
- **Handicap.** Shows your GHIN index when connected. Otherwise it estimates one from your
  rounds with the World Handicap System arithmetic.
- **Backup.** Everything is kept on the phone. More > Backup writes one file with all of it.

## The GHIN connection is unofficial

TheGrint and similar apps connect to GHIN under a license from the USGA that is not offered to
individuals. Caddie instead signs in with your own GHIN email and password and uses the same
service the GHIN website uses. Your password is kept in the iPhone's Keychain and sent only to
GHIN.

- Reading your index, score history and course ratings works this way and changes nothing.
- **Posting a score has not been proven yet.** It is sent only after a screen shows exactly what
  will be posted and you confirm. After your first post, check it in the GHIN app. A posted score
  can only be changed or removed by your club.
- GHIN can change its service at any time, which would stop this working until the app is updated.

## Installing it from a Windows PC

The app is not in the App Store. It is installed with [iloader](https://github.com/nab138/iloader),
a free Windows program that signs an app with your Apple ID and puts it on your iPhone.

1. Download the app: [Caddie.ipa](https://github.com/gregmartin2008/golf-ios/releases/latest/download/Caddie.ipa).
2. Connect the iPhone by cable and open iloader.
3. Choose to install an `.ipa`, pick `Caddie.ipa`, and sign in with your Apple ID when asked.
4. On the iPhone, open Caddie and allow location "While Using the App".

A free Apple ID signs an app for seven days. SideStore, which iloader sets up, renews it on the
phone; open SideStore about once a week, and the evening before a round.

Installing a newer `Caddie.ipa` over the old one keeps your courses and rounds.

## First round

1. **More > GHIN**: sign in. Your index and recent scores appear.
2. **Courses > +**: search for the course, check what the map has, add it.
3. Open the course and tap **Link to GHIN** to bring in the tees and ratings.
4. If any holes are missing from the map, **Edit hole positions** and long-press the tee and
   the green for each.
5. **Play**: choose the course and tees, **Start round**.

## How it is built

- `Packages/CaddieCore`: all the logic, in plain Swift with no Apple-only frameworks, with unit
  tests: distances, course import, lie detection, scoring, statistics, strokes gained, handicap,
  the GHIN client, storage.
- `App`: the SwiftUI screens, the map, location and the Keychain.
- `.github/workflows/ci.yml`: on every push, runs the tests, imports two well-known public courses
  from live OpenStreetMap data as a check, builds the app, photographs every screen in the
  simulator with sample content, and publishes `Caddie.ipa` only if all of that passed.

`CLAUDE.md` has the rules the code follows.

## Credits

Course maps © OpenStreetMap contributors, Open Database License. Strokes gained uses the PGA
Tour baseline published by Mark Broadie (2011, 2012). GHIN field names follow the MIT-licensed
[n8io/ghin](https://github.com/n8io/ghin). Caddie is not affiliated with or endorsed by the USGA,
GHIN or TheGrint.
