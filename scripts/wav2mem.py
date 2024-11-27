#!/usr/bin/env python3


import sys

import numpy as np
from scipy.io import wavfile


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


if len(sys.argv) != 3:
    eprint("Please provide input and output filenames")
    sys.exit(69)

input = sys.argv[1]
output = sys.argv[2]

samplerate, data = wavfile.read(input)

data = data.view(dtype=np.uint16) ^ 0x8000 # convert to unsigned

with open(output, "w") as f:
    f.writelines(f"{sample}\n" for sample in data)
