#!/bin/sh

# disable wifi and remove all modules
killall udhcpc default-script wpa_supplicant 2>/dev/null
ifconfig eth0 down

if lsmod | grep -q 8189fs; then
    modprobe -r 8189fs
fi
