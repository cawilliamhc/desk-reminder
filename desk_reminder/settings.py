"""Settings chosen from the menu, kept in settings.json beside the stats."""

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta

from .schedule import DATA_DIR

SETTINGS_FILE = DATA_DIR / "settings.json"

STANDING_CHOICES = (38.0, 40.0, 42.0, 44.0)
# "Use current height" sets the threshold this far below where the desk is,
# since a preset doesn't stop at exactly the same tenth every time.
CURRENT_HEIGHT_MARGIN = 1.0
# ...and is only offered above this, so a click while sitting (27-31" here)
# can't turn sitting into standing.
MIN_CURRENT_HEIGHT = 35.0


@dataclass
class Settings:
    standing: float = 40.0
    sound: bool = True
    paused_until: float | None = None   # epoch seconds

    def paused(self, now):
        return self.paused_until is not None and now < self.paused_until


def load(path=SETTINGS_FILE):
    try:
        raw = json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return Settings()
    s = Settings()
    if isinstance(raw.get("standing"), (int, float)) and raw["standing"] > 0:
        s.standing = float(raw["standing"])
    if isinstance(raw.get("sound"), bool):
        s.sound = raw["sound"]
    if isinstance(raw.get("paused_until"), (int, float)):
        s.paused_until = float(raw["paused_until"])
    return s


def save(settings, path=SETTINGS_FILE):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(settings), indent=2))


def end_of_today(now):
    """Next local midnight, as epoch seconds."""
    d = datetime.fromtimestamp(now)
    return (d.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)).timestamp()


def standing_from_current(height):
    """Threshold for "Use current height", or None if the desk isn't clearly raised."""
    if height is None or height < MIN_CURRENT_HEIGHT:
        return None
    return round(height - CURRENT_HEIGHT_MARGIN, 1)


def pause_label(settings, now):
    if not settings.paused(now):
        return "Reminders on"
    if settings.paused_until >= end_of_today(now):
        return "Paused for today"
    return "Paused until " + datetime.fromtimestamp(settings.paused_until).strftime("%-I:%M %p")
