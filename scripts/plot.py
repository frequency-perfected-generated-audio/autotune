#!/usr/bin/env python3

import sys

import matplotlib.pyplot as plt
import numpy as np


def add_plot(axs, fname):
    with open(fname) as f:
        tones = [line.strip() for line in f]

    taus = np.array(list(map(float, tones)))

    tones = (44100 / taus)
    tones[tones > 1500] = 0
    n = len(tones)
    axs.plot(np.linspace(1, n, n), tones)
    axs.set_title(fname)


nplots = len(sys.argv) - 1
fig, axs = plt.subplots(1, nplots, squeeze=False)
for i in range(nplots):
    add_plot(axs[0][i], sys.argv[1 + i])

plt.show()
