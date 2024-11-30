#!/usr/bin/env python3

import sys
import wave

import numpy as np
import serial


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


if len(sys.argv) == 1:
    eprint("Please provide output filename as first argument")
    sys.exit(69)
fname = sys.argv[1]

SERIAL_PORT_NAME = "/dev/cu.usbserial-8874292302131"
FS = 44100
SECONDS = 3

ser = serial.Serial(SERIAL_PORT_NAME, bytesize=serial.EIGHTBITS, baudrate=460800)
eprint("Serial port initialized")

eprint(f"Recording {SECONDS} seconds of audio:")
samples = []
for i in range(FS * SECONDS):
    val = int.from_bytes(ser.read(), "little")
    if (i + 1) % FS == 0:
        eprint(f"{(i+1)/FS} seconds complete")
    samples.append(val * 256)

with wave.open(fname, "wb") as wf:
    wf.setframerate(FS)
    wf.setnchannels(1)
    wf.setsampwidth(2)
    samples = np.array(samples, dtype=np.uint16).tobytes()
    wf.writeframes(samples)
    eprint(f"Recording saved to {fname}")
