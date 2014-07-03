#!/bin/sh
export LC_ALL="en_US.UTF-8"

# we're always starting from our working directory
cd /mnt/onboard/.kobo/koreader/

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# exit from nickel
killall nickel
killall hindenburg

# finally call the launcher
./reader.lua /mnt/onboard 2> crash.log

# back to nickel
./nickel.sh
