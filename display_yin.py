#!/usr/bin/env python3
import sys

import numpy as np
import serial
from matplotlib import pyplot as plt


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


eprint("README!!! If the script is not working, make sure your serial port is correct")
eprint("README!!! Also make sure your baud rate is correct w.r.t the FPGA")
eprint("README!!! Also read the high bits")
eprint("README!!! Aight I'm out")

SERIAL_PORT_NAME = "/dev/cu.usbserial-8874292302131"
WINDOWS_PER_SECOND = 44100 // 2048
SECONDS = 3

ser = serial.Serial(SERIAL_PORT_NAME, bytesize=serial.EIGHTBITS, baudrate=460800)
eprint("Serial port initialized")


def live_update_demo(blit=False):
    x = np.linspace(1, WINDOWS_PER_SECOND * SECONDS, WINDOWS_PER_SECOND * SECONDS)
    y = np.zeros(len(x))
    fig = plt.figure()
    ax2 = fig.add_subplot(1, 1, 1)

    (line,) = ax2.plot([], lw=3)
    text = ax2.text(0.8, 0.5, "")

    ax2.set_xlim(x.min(), x.max())
    ax2.set_ylim([0, 1500])

    fig.canvas.draw()  # note that the first draw comes before setting data

    if blit:
        # cache the background
        ax2background = fig.canvas.copy_from_bbox(ax2.bbox)

    plt.show(block=False)

    k = 0.0

    while True:
        # TODO: update y
        sample = int.from_bytes(ser.read(), "little")
        y = np.roll(y, -1)
        y[-1] = sample
        line.set_data(x, y)
        k += 0.11
        if blit:
            # restore background
            fig.canvas.restore_region(ax2background)

            # redraw just the points
            ax2.draw_artist(line)
            ax2.draw_artist(text)

            # fill in the axes rectangle
            fig.canvas.blit(ax2.bbox)

            # in this post http://bastibe.de/2013-05-30-speeding-up-matplotlib.html
            # it is mentionned that blit causes strong memory leakage.
            # however, I did not observe that.

        else:
            # redraw everything
            fig.canvas.draw()

        fig.canvas.flush_events()
        # alternatively you could use
        # plt.pause(0.000000000001)
        # however plt.pause calls canvas.draw(), as can be read here:
        # http://bastibe.de/2013-05-30-speeding-up-matplotlib.html


live_update_demo(True)
