#!/bin/sh


if [ "$#" -ne 2 ]; then
    echo "Usage: yin.sh <input wav> <output file>"
    exit 69
fi

TOPLEVEL=$(git rev-parse --show-toplevel)

cargo run --release --manifest-path "$TOPLEVEL/yin-rs/Cargo.toml" -- \
    --taumax=2048 --window-size=2048 --file="$1" > "$2"
