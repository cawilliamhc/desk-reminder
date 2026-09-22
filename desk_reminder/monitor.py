"""Receive-only serial monitor. This module never writes to the port."""

import glob
import threading
import time

import serial

from .protocol import FrameParser, height_of

BAUD = 9600


def find_port():
    ports = sorted(glob.glob("/dev/cu.usbserial*"))
    return ports[0] if ports else None


class DeskMonitor(threading.Thread):
    """Calls on_height(inches) for every height report; reconnects if unplugged."""

    def __init__(self, on_height, on_status=lambda s: None):
        super().__init__(daemon=True)
        self.on_height = on_height
        self.on_status = on_status

    def run(self):
        while True:
            port = find_port()
            if not port:
                self.on_status("adapter not found")
                time.sleep(5)
                continue
            try:
                with serial.Serial(port, BAUD, timeout=0.2) as ser:
                    ser.dtr = False
                    ser.rts = False
                    self.on_status("connected")
                    parser = FrameParser()
                    while True:
                        for cmd, data in parser.feed(ser.read(256)):
                            h = height_of(cmd, data)
                            if h is not None:
                                self.on_height(h)
            except (serial.SerialException, OSError):
                self.on_status("adapter disconnected")
                time.sleep(5)
