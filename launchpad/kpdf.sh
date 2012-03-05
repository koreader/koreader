#!/bin/sh
echo unlock > /proc/keypad
echo unlock > /proc/fiveway
cd /mnt/us/kindlepdfviewer/
./reader.lua $1
echo 1 > /proc/eink_fb/update_display
