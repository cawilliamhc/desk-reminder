# Intermission

A menu-bar app that tracks how much the standing desk is up versus down, and
reminds me to raise it to write my notes after sessions.

## Hardware (receive-only)

Jiecang JCB35NH4A control box, RJ12 **F** port, via a screw-terminal breakout, to a
DSD TECH SH-U09F2 (FTDI, 5 V):

| Adapter | F-port terminal |
|---|---|
| GND | 2 |
| RXD | 4 (box → handset height reports) |
| TXD | not connected |
| VCC | not connected |

Height frames on pin 4, 9600 8N1: `F2 F2 01 03 <hi> <lo> 07 <checksum> 7E`, height in
tenths of an inch, checksum = sum of cmd, len and data bytes. The box only sends while
the desk moves (plus ~1–2 s after), so height is unknown until the desk first moves.

**Nothing is ever sent to the desk.** Transmitting makes the handset click and light up;
the F port also ignores the known Jiecang commands on pins 3 and 5, so control would need
an RJ45 breakout on the handset cable anyway.

## The app

`mac/` is a Swift package: `DeskCore` holds the logic (frame parser, sit/stand timeline,
coach, day store, settings, session schedule) and `Intermission` is the SwiftUI app.

```sh
cd mac
swift test
./scripts/build_app.sh        # builds build/Intermission.app, ad-hoc signed
```

Install by copying `build/Intermission.app` to `/Applications` — notifications only work
from a registered bundle, so run it from there rather than the build folder.

### Behaviour

- Standing time counts only while the Mac is unlocked and in use: the desk is shared, and
  someone else's standing is not mine.
- After a session ends: if the desk is below the standing height, nudge, nudge once more
  after 5 minutes, give up after 20. Reaching standing height counts. Silent during a
  session, while paused, and on rest days.
- Standing share excludes session time from the denominator.
- Settings: standing height and goal, note reminders, skip virtual sessions, sound, desk
  days, coach tone, pause, open at login.

### Notifications and Focus

A Focus queues notifications silently. Breaking through needs the time-sensitive
entitlement, which needs a provisioning profile from a paid developer account — signed
ad hoc with it, macOS refuses to launch the app. So add **Intermission** to the Focus's
allowed apps (Settings has a button for that pane).

`INTERMISSION_TEST_NOTIFY=1 open /Applications/Intermission.app` posts one notification
at launch, for testing.

## Session times

Practice Studio publishes the day's sessions — times and modality only, no names, ids or
status — to
`~/Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json`
(`client/src/lib/sessionEndsExport.ts`). This app never reads the appointments file.

## The font

Headlines are set in GT Ultra Light, which is licensed for use in this app and is
therefore **not in this repository** — a licensed font isn't mine to hand out. The build
script looks for `mac/Resources/Fonts/GT-Ultra-Standard-Light.otf` and its italic; with
the folder missing it builds fine and the headlines fall back to New York, the system
serif.

## Data

`~/Library/Application Support/com.carlwilliamson.intermission/`: `days.json` (per-day
tallies), `plans.json` (a fortnight of plan edits), `weeks.json` (weekly goal slots),
`logs.json` (desk and computer stretches), `settings.json`, `last_height.json`.

The Python/rumps app this replaced was retired on 22 Sep 2026; its note history was
migrated into `days.json`, and its old folder (`~/Library/Application Support/desk-reminder/`)
is left in place, unused.
