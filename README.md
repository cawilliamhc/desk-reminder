# Desk reminder

A menu-bar app that reminds me to raise the desk after a session, and checks that I did.

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
tenths of an inch, checksum = sum of cmd, len and data bytes. The box only sends while the
desk moves (plus ~1–2 s after), so height is unknown until the desk first moves.

The F port doesn't accept the known Jiecang handset commands on pins 3 or 5: frames on pin 3 wake
the handset display but don't move the desk. This app never writes to the port.

## Behaviour

- At each session's end time: if you're below 40″, remind; remind once more at 5 min; give up at 20 min.
- Reaching 40″ at any point in that window counts as standing. Already standing counts too.
- Menu: current height, adapter status, "Stood for X of Y notes this week", and
  **I just finished a session** for a manual trigger.
- Desk movement outside those windows is ignored and not recorded (the desk is shared).
- The menu-bar title shows the live height (🧍 at or above the standing height). After a
  restart it shows the last known height as `~29.3″` until the desk moves again; the reminder
  logic only ever uses live reports, since someone may have moved the desk meanwhile.

## Settings (from the menu)

- **Pause for 1 hour / for today, Resume.** Sessions that end while paused get no reminder
  and aren't counted. Pausing drops a reminder already in progress. The title shows ⏸.
- **Standing height:** 38/40/42/44″, or **Use current height**, which counts from 1″ below
  where the desk is now. It's only offered above 35″, so a click while sitting can't make
  sitting count as standing.
- **Sound** on/off for reminders.

Saved in `~/Library/Application Support/desk-reminder/settings.json`.

## Files

- **Input:** `~/Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json`,
  `{"ends": ["2026-09-22T18:50:00.000Z", ...]}`. Written by Practice Studio
  (`client/src/lib/sessionEndsExport.ts`) whenever its calendar loads: scheduled/attended
  client sessions, yesterday through 14 days ahead. **Times only**: no names, ids or
  status. This app never reads the appointments file.
- **Output:** `~/Library/Application Support/desk-reminder/stood.jsonl`, one
  `{"at": <epoch>, "stood": true|false}` per session end.

## Run

```sh
python3 -m venv .venv && .venv/bin/pip install pyserial rumps pytest
./run.sh
.venv/bin/python -m pytest
```

## Start at login

`launchd/com.carlwilliamson.desk-reminder.plist` is symlinked into `~/Library/LaunchAgents/`.
It starts the app at login, restarts it after a crash, and leaves it quit after **Quit**.
Logs go to `~/Library/Logs/desk-reminder.log`.

```sh
# install / restart
ln -sf "$PWD/launchd/com.carlwilliamson.desk-reminder.plist" ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u)/com.carlwilliamson.desk-reminder 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.carlwilliamson.desk-reminder.plist

# remove
launchctl bootout gui/$(id -u)/com.carlwilliamson.desk-reminder
rm ~/Library/LaunchAgents/com.carlwilliamson.desk-reminder.plist
```
