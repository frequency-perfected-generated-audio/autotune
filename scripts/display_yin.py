#!/usr/bin/env python3
# definitely not based on, inspired, or derived from
# https://stackoverflow.com/questions/40126176/fast-live-plotting-in-matplotlib-pyplot
# at all
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
    f0 = np.zeros(len(x))
    fig = plt.figure()
    plt.get_current_fig_manager().full_screen_toggle()
    ax = plt.gca()

    (line,) = ax.plot([])

    ax.set_xlim(x.min(), x.max())
    ax.set_ylim([0, 1500])

    fig.canvas.draw()  # note that the first draw comes before setting data

    if blit:
        # cache the background
        ax2background = fig.canvas.copy_from_bbox(ax.bbox)

    plt.show(block=False)

    while True:
        # TODO: update y
        tau = 8 * int.from_bytes(ser.read(), "little")
        f0 = np.roll(f0, -1)
        tone = 44100 / (tau + 0.01)
        f0[-1] = tone
        print(f"{tau=} {tone=}")
        line.set_data(x, f0)
        if blit:
            # restore background
            fig.canvas.restore_region(ax2background)

            # redraw just the points
            ax.draw_artist(line)

            # fill in the axes rectangle
            fig.canvas.blit(ax.bbox)

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

        if not plt.fignum_exists(fig.number):
            break


live_update_demo(True)
