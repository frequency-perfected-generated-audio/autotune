import sys

import serial


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


eprint(
    "README!!! If the script is not working, make sure you're serial port is correct"
)
eprint("README!!! Also make sure you're baud rate is correct w.r.t the FPGA")
eprint("README!!! Also read the high bits")
eprint("README!!! Aight I'm out")

SERIAL_PORT_NAME = "/dev/cu.usbserial-8874292302131"
WINDOWS_PER_SECOND = 44100 // 2048

ser = serial.Serial(SERIAL_PORT_NAME, bytesize=serial.EIGHTBITS, baudrate=460800)
eprint("Serial port initialized")

eprint("Recording 6 seconds of windows:")
ypoints = []
for i in range(WINDOWS_PER_SECOND * 6):
    val = int.from_bytes(ser.read(), "little")
    if (i + 1) % WINDOWS_PER_SECOND == 0:
        eprint(f"{(i+1)/WINDOWS_PER_SECOND} seconds complete")
    ypoints.append(val)

for y in ypoints:
    print(y)
