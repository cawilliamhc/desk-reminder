"""Session end times, read from a file that holds times and nothing else.

    ~/Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json
    {"ends": ["2026-09-22T18:50:00.000Z", "2026-09-22T20:00:00.000Z"]}

Written by Practice Studio (client/src/lib/sessionEndsExport.ts) into its own
app-data folder. No names, no ids, no status - just when sessions end. This
app never reads the appointments file itself.
"""

import json
import os
from datetime import datetime
from pathlib import Path

APP_SUPPORT = Path.home() / "Library" / "Application Support"
DATA_DIR = APP_SUPPORT / "desk-reminder"   # this app's own files
SESSIONS_FILE = APP_SUPPORT / "com.carlwilliamson.practicestudio" / "desk-reminder" / "sessions.json"


class Schedule:
    def __init__(self, path=SESSIONS_FILE):
        self.path = Path(path)
        self._mtime = None
        self._ends = []

    def _reload(self):
        try:
            mtime = os.stat(self.path).st_mtime
        except FileNotFoundError:
            self._mtime, self._ends = None, []
            return
        if mtime == self._mtime:
            return
        self._mtime = mtime
        try:
            raw = json.loads(self.path.read_text())["ends"]
            self._ends = sorted(datetime.fromisoformat(s).timestamp() for s in raw)
        except (ValueError, KeyError, TypeError):
            self._ends = []

    def ends_between(self, after, until):
        """Session end times t with after < t <= until (epoch seconds)."""
        self._reload()
        return [t for t in self._ends if after < t <= until]
