from desk_reminder.coach import FIRST, GIVE_UP, REMIND_AGAIN, SECOND, Coach


def make():
    notes, records = [], []
    coach = Coach(notify=notes.append, record=lambda stood, at: records.append(stood))
    return coach, notes, records


def test_reminds_then_counts_standing():
    c, notes, records = make()
    c.height_changed(29.5, 0)
    c.session_ended(100)
    assert notes == [FIRST]
    c.height_changed(35.0, 110)      # on the way up, not there yet
    assert records == []
    c.height_changed(44.5, 115)
    assert records == [True]
    assert not c.waiting


def test_already_standing_counts_without_reminder():
    c, notes, records = make()
    c.height_changed(44.5, 0)
    c.session_ended(100)
    assert notes == [] and records == [True]


def test_unknown_height_still_reminds():
    c, notes, _ = make()
    c.session_ended(100)
    assert notes == [FIRST]


def test_second_reminder_once_then_gives_up():
    c, notes, records = make()
    c.height_changed(29.5, 0)
    c.session_ended(0)
    c.tick(REMIND_AGAIN)
    c.tick(REMIND_AGAIN + 60)
    assert notes == [FIRST, SECOND]
    c.tick(GIVE_UP)
    assert records == [False]
    assert not c.waiting


def test_movement_outside_a_window_records_nothing():
    c, notes, records = make()
    c.height_changed(44.5, 0)
    c.height_changed(27.4, 50)
    c.tick(10_000)
    assert notes == [] and records == []


def test_overlapping_session_end_does_not_restart_window():
    c, notes, _ = make()
    c.height_changed(29.5, 0)
    c.session_ended(0)
    c.session_ended(60)
    assert notes == [FIRST]
