"""Menu-bar app: shows desk height, reminds you to stand after sessions."""

import queue
import subprocess
import time

import rumps

from . import stats
from .coach import Coach
from .monitor import DeskMonitor
from .schedule import Schedule


def notify(message):
    # osascript needs no app bundle; macOS attributes these to Script Editor.
    script = f'display notification "{message}" with title "Desk" sound name "Glass"'
    subprocess.run(["osascript", "-e", script], check=False)


class DeskApp(rumps.App):
    def __init__(self):
        super().__init__("Desk", title="↕ —", quit_button="Quit")
        self.events = queue.Queue()   # filled by the serial thread, drained on the main thread
        self.coach = Coach(notify=notify, record=self._record)
        self.schedule = Schedule()
        self.last_check = time.time()

        self.status_item = rumps.MenuItem("Adapter: starting…")
        self.week_item = rumps.MenuItem("")
        self.menu = [
            self.status_item,
            self.week_item,
            None,
            rumps.MenuItem("I just finished a session", callback=self._manual_end),
        ]
        self._refresh_week()

        DeskMonitor(
            on_height=lambda h: self.events.put(("height", h)),
            on_status=lambda s: self.events.put(("status", s)),
        ).start()
        rumps.Timer(self._tick, 1).start()

    def _record(self, stood, at):
        stats.record(stood, at)
        self._refresh_week()

    def _refresh_week(self):
        stood, total = stats.this_week()
        self.week_item.title = f"Stood for {stood} of {total} notes this week"

    def _manual_end(self, _):
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
        for _end in self.schedule.ends_between(self.last_check, now):
            self.coach.session_ended(now)
        self.last_check = now
        self.coach.tick(now)

        h = self.coach.height
        icon = "🧍" if h is not None and h >= self.coach.standing else "↕"
        self.title = f"{icon} {h:.1f}″" if h is not None else "↕ —"


def main():
    DeskApp().run()


if __name__ == "__main__":
    main()
