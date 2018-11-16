#!/bin/sh

# Debian Wheezy ships an old wpa_supplicant binary (1.0.3). Please refer to
# https://manpages.debian.org/wheezy/wpasupplicant/wpa_supplicant.8.en.html
# to see which command line options are available.

# Do not run this script twice (ie: when no wireless is available or wireless
# association to ap failed.
./disable-wifi.sh

if ! lsmod | grep -q 8189fs; then
    modprobe 8189fs
    sleep 1
fi

ifconfig eth0 up
sleep 1

wpa_supplicant -i eth0 -C /var/run/wpa_supplicant -B -D wext 2>/dev/null
