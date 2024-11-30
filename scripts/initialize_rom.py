from pathlib import Path

BASE_PATH = Path(__file__).resolve().parent.parent
ROM_FILE_PATH = BASE_PATH / "data" / "semitones.mem"

A4 = 44100 / 440
notes = []
for i in range(-25, 40):  # Range to cover periods from ~20 to ~1000
    frequency = A4 * (2 ** (i / 12))
    notes.append(int(frequency))

hex_notes = [hex(note) for note in notes]

with open(ROM_FILE_PATH, "w") as rom_file:
    rom_file.write("\n".join(hex_notes))
