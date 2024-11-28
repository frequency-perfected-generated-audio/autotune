First, comment out `hdl/psola.sv`.

# Software Yin Results

Run:
```
./scripts/get-taus test_data/aladdin-felix.wav yin-sw.txt
```

# Hardware Yin Results

1. Load `reproducer.bit` ontob board
2. Run `./scripts/display_yin.py`
3. Go back to terminal to watch output
4. When you hit the reset button, the FPGA will play audio into the Yin, and
   the values should appear in the terminal.
