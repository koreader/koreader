#!/bin/sh

# disable wifi and remove all modules
killall udhcpc wpa_supplicant 2>/dev/null
ifconfig eth0 down 2>/dev/null
modprobe -r 8189fs 2>/dev/null
