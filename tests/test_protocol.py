from desk_reminder.protocol import FrameParser, height_of

# Shaped like real captures: 30.5" and 44.5".
H305 = bytes.fromhex("F2F2010301310 73D7E".replace(" ", ""))
H445 = bytes.fromhex("F2F20103 01BD07 C9 7E".replace(" ", ""))


def heights(frames):
    return [height_of(c, d) for c, d in frames]


def test_single_frame():
    assert heights(FrameParser().feed(H305)) == [30.5]


def test_frame_split_across_reads():
    p = FrameParser()
    assert p.feed(H305[:1]) == []
    assert p.feed(H305[1:5]) == []
    assert heights(p.feed(H305[5:])) == [30.5]


def test_back_to_back_with_noise():
    assert heights(FrameParser().feed(b"\x00\x7E" + H305 + b"\xF2" + H445)) == [30.5, 44.5]


def test_bad_checksum_is_dropped_and_parser_resyncs():
    bad = bytearray(H305)
    bad[-2] ^= 0xFF
    assert heights(FrameParser().feed(bytes(bad) + H445)) == [44.5]


def test_non_height_frame_has_no_height():
    frame = bytes.fromhex("F2F2 0E 01 01 10 7E".replace(" ", ""))
    [(cmd, data)] = FrameParser().feed(frame)
    assert height_of(cmd, data) is None
