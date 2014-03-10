#!/bin/sh
export LC_ALL="en_US.UTF-8"

# we're always starting from our working directory
cd /mnt/onboard/.kobo/koreader/

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# stop Nickel
killall -STOP nickel

# store the content of the framebuffer
#dd if=/dev/fb0 of=.last_screen_content

# finally call reader
./reader.lua /mnt/onboard 2> crash.log

# continue with nickel
#cat .last_screen_content | /usr/local/Kobo/pickel showpic
#rm .last_screen_content
killall -CONT nickel
