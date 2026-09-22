"""The reminder logic, kept free of I/O so it can be tested with a fake clock.

After a session ends:
  - already at standing height -> counted as stood, no reminder
  - otherwise remind now, remind once more after REMIND_AGAIN, give up after GIVE_UP
  - reaching standing height at any point in that window counts as stood
Heights are only acted on inside that window; nothing else is recorded.
"""

STANDING_IN = 40.0
REMIND_AGAIN = 5 * 60
GIVE_UP = 20 * 60

FIRST = "Session's over — raise the desk to write your note."
SECOND = "Still sitting — raise the desk before you start the note?"


class Coach:
    def __init__(self, notify, record, standing=STANDING_IN):
        self.notify = notify    # notify(message)
        self.record = record    # record(stood: bool, at: float)
        self.standing = standing
        self.height = None      # last reported height; None until the desk first moves
        self._started = None    # session-end time while waiting, else None
        self._reminded_again = False

    @property
    def waiting(self):
        return self._started is not None

    def session_ended(self, now):
        if self.waiting:
            return
        if self.height is not None and self.height >= self.standing:
            self.record(True, now)
            return
        self._started = now
        self._reminded_again = False
        self.notify(FIRST)

    def height_changed(self, height, now):
        self.height = height
        if self.waiting and height >= self.standing:
            self._started = None
            self.record(True, now)

    def tick(self, now):
        if not self.waiting:
            return
        elapsed = now - self._started
        if elapsed >= GIVE_UP:
            self._started = None
            self.record(False, now)
        elif elapsed >= REMIND_AGAIN and not self._reminded_again:
            self._reminded_again = True
            self.notify(SECOND)
