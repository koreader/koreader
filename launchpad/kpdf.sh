#!/bin/sh
SLIDER_EVENT_PIPE="/tmp/event_slider"
export LC_ALL="en_US.UTF-8"

echo unlock > /proc/keypad
echo unlock > /proc/fiveway
cd /mnt/us/kindlepdfviewer/

# create the named pipe for power slider event
if [ ! -p $SLIDER_EVENT_PIPE ]; then
	mkfifo $SLIDER_EVENT_PIPE
fi
killall slider_watcher
./slider_watcher $SLIDER_EVENT_PIPE &

./reader.lua $1 2> /mnt/us/kindlepdfviewer/crash.log
killall -cont cvm
echo 1 > /proc/eink_fb/update_display
