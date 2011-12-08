#!/bin/sh
echo unlock > /proc/keypad
echo unlock > /proc/fiveway
cd /mnt/us/test/
cat /dev/fb0 > /tmp/screen.fb0 &
if [ "x$1" == "x" ] ; then
	pdf=`lsof | grep /mnt/us/documents | cut -c81- | sort -u`
else
	pdf="$1"
fi
./reader.lua "$pdf"
cat /tmp/screen.fb0 > /dev/fb0
rm /tmp/screen.fb0
echo 1 > /proc/eink_fb/update_display
