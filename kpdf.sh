#!/bin/sh
export LC_ALL="en_US.UTF-8"

echo unlock > /proc/keypad
echo unlock > /proc/fiveway

# we're always starting from our working directory
cd /mnt/us/kindlepdfviewer/

# bind-mount system fonts
if ! grep /mnt/us/kindlepdfviewer/fonts/host /proc/mounts; then
	mount -o bind /usr/java/lib/fonts /mnt/us/kindlepdfviewer/fonts/host
fi

# check if we are supposed to shut down the Amazon framework
if test "$1" == "--framework_stop"; then
	shift 1
	/etc/init.d/framework stop
fi

# stop cvm
killall -stop cvm

export LD_LIBRARY_PATH=`pwd`/libs
# finally call reader
./reader.lua "$1" 2> /mnt/us/kindlepdfviewer/crash.log || cat /mnt/us/kindlepdfviewer/crash.log

# unmount system fonts
if grep /mnt/us/kindlepdfviewer/fonts/host /proc/mounts; then
	umount /mnt/us/kindlepdfviewer/fonts/host
fi

# always try to continue cvm
killall -cont cvm || /etc/init.d/framework start
