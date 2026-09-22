"""Decode the height reports a Jiecang JCB35NH4A sends on its F port (pin 4).

Frame, box -> handset, 9600 8N1:
    F2 F2 | cmd | len | data[len] | checksum | 7E
    checksum = (cmd + len + sum(data)) & 0xFF
cmd 0x01 is a height report: data[0:2] big-endian, tenths of an inch.
The box only sends while the desk moves, plus ~1-2 s after it stops.
"""

HEADER = b"\xF2\xF2"
END = 0x7E
CMD_HEIGHT = 0x01


class FrameParser:
    """Feed raw bytes in; get complete, checksum-valid frames out."""

    def __init__(self):
        self._buf = bytearray()

    def feed(self, chunk):
        self._buf += chunk
        frames = []
        while True:
            start = self._buf.find(HEADER)
            if start == -1:
                # Keep a trailing F2 in case it's the first half of a header.
                del self._buf[:-1]
                return frames
            del self._buf[:start]
            if len(self._buf) < 4:
                return frames
            cmd, n = self._buf[2], self._buf[3]
            end = 4 + n + 2
            if len(self._buf) < end:
                return frames
            data = bytes(self._buf[4:4 + n])
            if self._buf[end - 1] == END and (cmd + n + sum(data)) & 0xFF == self._buf[end - 2]:
                frames.append((cmd, data))
                del self._buf[:end]
            else:
                # Not a real frame. Skip one byte only: in "F2 F2 F2 ..." the
                # real header may start at the second F2.
                del self._buf[:1]


def height_of(cmd, data):
    """Height in inches for a height report, else None."""
    if cmd == CMD_HEIGHT and len(data) >= 2:
        return int.from_bytes(data[:2], "big") / 10
    return None
