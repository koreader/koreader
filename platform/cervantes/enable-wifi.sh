#!/bin/sh

# Debian Wheezy ships an old wpa_supplicant binary (1.0.3). Please refer to
# https://manpages.debian.org/wheezy/wpasupplicant/wpa_supplicant.8.en.html
# to see which command line options are available.

# Do not run this script twice (ie: when no wireless is available or wireless
# association to ap failed.

# select wifi driver based on pcb.
PCB_ID=$(/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ":" -f2)
if [ "${PCB_ID}" -eq 22 ] || [ "${PCB_ID}" -eq 23 ]; then
    MODULE="dhd"
    WPA_DRIVER="nl80211"
else
    MODULE="8189fs"
    WPA_DRIVER="wext"
fi

./disable-wifi.sh

if ! lsmod | grep -q ${MODULE}; then
    modprobe ${MODULE}
    sleep 1
fi

ifconfig eth0 up
sleep 1

wpa_supplicant -i eth0 -C /var/run/wpa_supplicant -B -D ${WPA_DRIVER} 2>/dev/null
sleep 1
