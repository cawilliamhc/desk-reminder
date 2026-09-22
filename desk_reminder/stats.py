"""One line per session end: when, and whether you stood. Nothing else."""

import json
import time
from datetime import datetime, timedelta

from .schedule import DATA_DIR

STATS_FILE = DATA_DIR / "stood.jsonl"


def record(stood, at, path=STATS_FILE):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps({"at": int(at), "stood": stood}) + "\n")


def this_week(path=STATS_FILE, now=None):
    """(stood, total) since Monday 00:00 local time."""
    now = datetime.fromtimestamp(now or time.time())
    monday = (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    stood = total = 0
    try:
        with open(path) as f:
            for line in f:
                row = json.loads(line)
                if row["at"] >= monday.timestamp():
                    total += 1
                    stood += row["stood"]
    except FileNotFoundError:
        pass
    return stood, total
