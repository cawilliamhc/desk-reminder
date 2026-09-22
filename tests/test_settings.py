import json
from datetime import datetime

from desk_reminder import settings as s
from desk_reminder.coach import Coach


def test_defaults_when_missing_or_corrupt(tmp_path):
    assert s.load(tmp_path / "none.json") == s.Settings()
    bad = tmp_path / "bad.json"
    bad.write_text("{nope")
    assert s.load(bad) == s.Settings()


def test_round_trip(tmp_path):
    f = tmp_path / "settings.json"
    s.save(s.Settings(standing=43.5, sound=False, paused_until=123.0), f)
    assert s.load(f) == s.Settings(standing=43.5, sound=False, paused_until=123.0)


def test_bad_values_fall_back_to_defaults(tmp_path):
    f = tmp_path / "settings.json"
    f.write_text(json.dumps({"standing": "tall", "sound": "yes", "paused_until": "soon"}))
    assert s.load(f) == s.Settings()


def test_paused_window():
    st = s.Settings(paused_until=100.0)
    assert st.paused(99) and not st.paused(100)
    assert not s.Settings().paused(0)


def test_end_of_today_is_next_local_midnight():
    now = datetime(2026, 9, 22, 15, 30).timestamp()
    assert datetime.fromtimestamp(s.end_of_today(now)) == datetime(2026, 9, 23, 0, 0)


def test_standing_from_current_only_when_clearly_raised():
    assert s.standing_from_current(None) is None
    assert s.standing_from_current(29.3) is None          # sitting: refused
    assert s.standing_from_current(44.5) == 43.5          # 1" of slack below the preset


def test_pause_label():
    now = datetime(2026, 9, 22, 15, 0).timestamp()
    assert s.pause_label(s.Settings(), now) == "Reminders on"
    assert s.pause_label(s.Settings(paused_until=s.end_of_today(now)), now) == "Paused for today"
    assert s.pause_label(s.Settings(paused_until=now + 3600), now) == "Paused until 4:00 PM"


def test_cancel_drops_a_reminder_without_recording():
    notes, records = [], []
    c = Coach(notify=notes.append, record=lambda stood, at: records.append(stood))
    c.height_changed(29.5, 0)
    c.session_ended(0)
    c.cancel()
    c.tick(10_000)
    assert records == [] and not c.waiting
