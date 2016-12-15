#!/bin/sh

# Disable wifi, and remove all modules.

killall udhcpc default.script wpa_supplicant 2>/dev/null

wlarm_le -i eth0 down
ifconfig eth0 down

# Some sleep in between may avoid system getting hung
# (we test if a module is actually loaded to avoid unneeded sleeps)
if lsmod | grep -q dhd ; then
    usleep 200000
    rmmod -r dhd
fi
if lsmod | grep -q sdio_wifi_pwr ; then
    usleep 200000
    rmmod -r sdio_wifi_pwr
fi
