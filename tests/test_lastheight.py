from desk_reminder import lastheight


def test_round_trip_and_missing(tmp_path):
    f = tmp_path / "last_height.json"
    assert lastheight.load(f) is None
    lastheight.save(29.3, f)
    assert lastheight.load(f) == 29.3


def test_corrupt_file_is_unknown(tmp_path):
    f = tmp_path / "last_height.json"
    f.write_text("{oops")
    assert lastheight.load(f) is None


def test_title_prefers_live_then_remembered():
    assert lastheight.title(29.3, 44.5, 40) == "↕ 29.3″"
    assert lastheight.title(44.5, None, 40) == "🧍 44.5″"
    assert lastheight.title(None, 44.5, 40) == "↕ ~44.5″"   # remembered never shows as standing
    assert lastheight.title(None, None, 40) == "↕ —"
