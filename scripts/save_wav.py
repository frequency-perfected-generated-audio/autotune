#!/usr/bin/env python3

import sys

import numpy as np
import serial
from scipy.io import wavfile


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


if len(sys.argv) == 1:
    eprint("Please provide output filename as first argument")
    sys.exit(69)
fname = sys.argv[1]

SERIAL_PORT_NAME = "/dev/cu.usbserial-8874292302131"
FS = 44100
SECONDS = int(sys.argv[2]) if len(sys.argv) == 3 else 15

ser = serial.Serial(SERIAL_PORT_NAME, bytesize=serial.EIGHTBITS, baudrate=1_000_000)
eprint("Serial port initialized")

eprint(f"Recording {SECONDS} seconds of audio:")
samples = []
for i in range(FS * SECONDS):
    hi = int.from_bytes(ser.read(), "little")
    lo = int.from_bytes(ser.read(), "little")
    if (i + 1) % FS == 0:
        eprint(f"{(i+1)/FS} seconds complete")
    samples.append((hi * 255 + lo) - 32768)


arr = np.array(samples, dtype=np.int16)
np.save(f"{fname}.npy", arr)

wavfile.write(fname, FS, arr)
