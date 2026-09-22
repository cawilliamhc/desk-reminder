"""Menu-bar app: shows desk height, reminds you to stand after sessions."""

import queue
import subprocess
import time

import rumps

from . import lastheight, settings as settings_mod, stats
from .coach import Coach
from .monitor import DeskMonitor
from .schedule import Schedule
from .settings import STANDING_CHOICES


def notify(message, sound=True):
    # osascript needs no app bundle; macOS attributes these to Script Editor.
    script = f'display notification "{message}" with title "Desk"'
    if sound:
        script += ' sound name "Glass"'
    subprocess.run(["osascript", "-e", script], check=False)


class DeskApp(rumps.App):
    def __init__(self):
        super().__init__("Desk", title="↕ —", quit_button="Quit")
        self.events = queue.Queue()   # filled by the serial thread, drained on the main thread
        self.settings = settings_mod.load()
        self.coach = Coach(
            notify=lambda m: notify(m, self.settings.sound),
            record=self._record,
            standing=self.settings.standing,
        )
        self.schedule = Schedule()
        self.last_check = time.time()
        self.remembered = lastheight.load()

        self.status_item = rumps.MenuItem("Adapter: starting…")
        self.week_item = rumps.MenuItem("")
        self.pause_status = rumps.MenuItem("")
        self.resume_item = rumps.MenuItem("Resume reminders")
        self.standing_menu = rumps.MenuItem("Standing height")
        self.use_current = rumps.MenuItem("Use current height")
        self.sound_item = rumps.MenuItem("Sound", callback=self._toggle_sound)
        self.menu = [
            self.status_item,
            self.week_item,
            None,
            rumps.MenuItem("I just finished a session", callback=self._manual_end),
            None,
            self.pause_status,
            rumps.MenuItem("Pause for 1 hour", callback=self._pause_hour),
            rumps.MenuItem("Pause for today", callback=self._pause_today),
            self.resume_item,
            None,
            self.standing_menu,
            self.sound_item,
        ]
        self._refresh_week()
        self._refresh_settings()

        DeskMonitor(
            on_height=lambda h: self.events.put(("height", h)),
            on_status=lambda s: self.events.put(("status", s)),
        ).start()
        rumps.Timer(self._tick, 1).start()

    # --- stats -------------------------------------------------------------

    def _record(self, stood, at):
        stats.record(stood, at)
        self._refresh_week()

    def _refresh_week(self):
        stood, total = stats.this_week()
        self.week_item.title = f"Stood for {stood} of {total} notes this week"

    # --- settings ----------------------------------------------------------

    def _save(self):
        settings_mod.save(self.settings)
        self._refresh_settings()

    def _refresh_settings(self):
        now = time.time()
        self.pause_status.title = settings_mod.pause_label(self.settings, now)
        self.resume_item.set_callback(self._resume if self.settings.paused(now) else None)
        self.sound_item.state = int(self.settings.sound)

        # Rebuilt each time so a custom "current height" value gets its own tick.
        standing = self.settings.standing
        choices = sorted(set(STANDING_CHOICES) | {standing})
        self.standing_menu.title = f"Standing height: {standing:.1f}″ and up"
        if self.standing_menu._menu is not None:
            self.standing_menu.clear()
        for value in choices:
            item = rumps.MenuItem(f"{value:.1f}″", callback=self._standing_setter(value))
            item.state = int(value == standing)
            self.standing_menu.add(item)
        self.standing_menu.add(None)
        self.standing_menu.add(self.use_current)
        self._refresh_use_current()

    def _refresh_use_current(self):
        threshold = settings_mod.standing_from_current(self.coach.height)
        if threshold is None:
            self.use_current.title = "Use current height (raise the desk first)"
            self.use_current.set_callback(None)
        else:
            self.use_current.title = f"Use current height ({self.coach.height:.1f}″ → counts from {threshold:.1f}″)"
            self.use_current.set_callback(self._standing_setter(threshold))

    def _standing_setter(self, value):
        def apply(_):
            self.settings.standing = value
            self.coach.standing = value
            self._save()
        return apply

    def _toggle_sound(self, _):
        self.settings.sound = not self.settings.sound
        self._save()

    def _pause_until(self, until):
        self.settings.paused_until = until
        self.coach.cancel()   # a reminder already showing is dropped, not counted
        self._save()

    def _pause_hour(self, _):
        self._pause_until(time.time() + 3600)

    def _pause_today(self, _):
        self._pause_until(settings_mod.end_of_today(time.time()))

    def _resume(self, _):
        self.settings.paused_until = None
        self._save()

    # --- loop --------------------------------------------------------------

    def _manual_end(self, _):
        # Clicking this is deliberate, so it works even while paused.
        self.coach.session_ended(time.time())

    def _tick(self, _):
        now = time.time()
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "height":
                self.coach.height_changed(value, now)
            else:
                self.status_item.title = f"Adapter: {value}"

        paused = self.settings.paused(now)
        if self.settings.paused_until is not None and not paused:
            self.settings.paused_until = None   # the pause ran out
            self._save()
        # Sessions that end while paused are skipped: no reminder, not counted.
        if self.schedule.ends_between(self.last_check, now) and not paused:
            self.coach.session_ended(now)
        self.last_check = now
        self.coach.tick(now)

        live = self.coach.height
        if live is not None and live != self.remembered:
            # Reports repeat at the final height for ~1-2 s after the desk
            # stops, so this settles on where it came to rest.
            lastheight.save(live)
            self.remembered = live
        self._refresh_use_current()
        title = lastheight.title(live, self.remembered, self.coach.standing)
        self.title = title + (" ⏸" if paused else "")


def main():
    DeskApp().run()


if __name__ == "__main__":
    main()
