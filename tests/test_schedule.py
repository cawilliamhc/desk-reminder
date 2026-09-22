import json
from datetime import datetime

from desk_reminder.schedule import Schedule


def ts(s):
    return datetime.fromisoformat(s).timestamp()


def test_ends_in_window(tmp_path):
    f = tmp_path / "sessions.json"
    f.write_text(json.dumps({"ends": ["2026-09-22T14:50:00-04:00", "2026-09-22T16:00:00-04:00"]}))
    s = Schedule(f)
    assert s.ends_between(ts("2026-09-22T14:49:59-04:00"), ts("2026-09-22T14:50:00-04:00")) == [ts("2026-09-22T14:50:00-04:00")]
    assert s.ends_between(ts("2026-09-22T14:50:00-04:00"), ts("2026-09-22T15:59:59-04:00")) == []


def test_missing_or_malformed_file_means_no_sessions(tmp_path):
    assert Schedule(tmp_path / "nope.json").ends_between(0, 2e9) == []
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert Schedule(bad).ends_between(0, 2e9) == []
