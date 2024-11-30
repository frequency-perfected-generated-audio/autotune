#!/usr/bin/env python3


import sys
import wave

import numpy as np


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


if len(sys.argv) != 3:
    eprint("Please provide input and output filenames")
    sys.exit(69)

input = sys.argv[1]
output = sys.argv[2]

samples = []
with open(input, "rb") as f:
    for line in f.readlines():
        samples.append(int(line.strip(), base=16) ^ 0x8000)

with wave.open(output, "wb") as wf:
    wf.setframerate(44100)
    wf.setnchannels(1)
    wf.setsampwidth(2)
    samples = np.array(samples, dtype=np.uint16).view(dtype=np.int16).tobytes()
    wf.writeframes(samples)
