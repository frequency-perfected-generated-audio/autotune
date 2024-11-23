import wave

import serial

# opens serial port, waits for 6 seconds of 8kHz audio data, writes it to output.wav

# set to proper serial port name and WAV!
# find the port name using test_ports.py
# CHANGE ME
SERIAL_PORT_NAME = "/dev/cu.usbserial-8874292302131"
FS = 44100

ser = serial.Serial(SERIAL_PORT_NAME, bytesize=serial.EIGHTBITS, baudrate=460800)
print("Serial port initialized")

print("Recording 6 seconds of audio:")
samples = []
for i in range(FS * 6):
    val = int.from_bytes(ser.read(), "little")
    if (i + 1) % FS == 0:
        print(f"{(i+1)/FS} seconds complete")
    samples.append(val)

with wave.open("output.wav", "wb") as wf:
    wf.setframerate(FS)
    wf.setnchannels(1)
    wf.setsampwidth(1)
    samples = bytearray(samples)
    wf.writeframes(samples)
    print("Recording saved to output.wav")
