# Intermission

A menu-bar app that tracks how much the standing desk is up versus down, and
reminds me to raise it to write my notes after sessions.

## Hardware

Jiecang JCB35NH4A control box, **Bluetooth adapter in the RJ12 F port** — the port
Jiecang's own support says exists for a dongle. The app finds it by name ("Branch Desk
…"), connects, and subscribes to the one characteristic that talks:

| | |
|---|---|
| Service | `FE60` (a Lierda module, `L-BTMEB95-07014-03`) |
| `FE61` | write — the command channel |
| `FE62` | notify — the box's frames, relayed untouched |

The dongle is a transparent bridge, so what arrives is the control box's own serial
frame: `F2 F2 01 03 <hi> <lo> 07 <checksum> 7E`, height in tenths of an inch, checksum
the sum of everything from the command byte to the last data byte. The box only speaks
while the desk is moving, so the height is unknown until it first moves.

**One command is ever sent.** `F1 F1 01 00 01 7E` is up, and it is momentary: the desk
moves while the frames keep arriving at about seven a second and stops the moment they
don't. "Raise now" pulses it until the desk is near the height in Settings and lets it
coast the rest, measuring that coast each time. It runs because the button was pressed —
never on a timer, never after a reminder.

Do not guess at other command bytes. `F1 F1 1B 02 <hi> <lo>`, tried as "go to height",
put the box into its ASR re-home state: it drove to its lowest point and needed the down
button held to recover.

### The wire this replaced

The first version read the same frames from F-port pin 4 through an FTDI adapter, with
ground on pin 2 and nothing connected to TXD. It worked, and it made the handset wake up
— a click and a lit screen, several times a day. Two days of logging showed the line is
silent unless the desk is moving, so it was never data; a resistor in the signal line
changed nothing; unplugging it stopped it. The cause was the shared ground between the
Mac and the control box, which is the one thing Bluetooth doesn't have.

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
