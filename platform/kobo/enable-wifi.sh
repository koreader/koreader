#!/bin/sh

# Load wifi modules and enable wifi.

lsmod | grep -q sdio_wifi_pwr || insmod /drivers/$PLATFORM/wifi/sdio_wifi_pwr.ko
lsmod | grep -q dhd || insmod /drivers/$PLATFORM/wifi/dhd.ko
sleep 1

ifconfig eth0 up
wlarm_le -i eth0 up

pidof wpa_supplicant >/dev/null || \
    env -u LD_LIBRARY_PATH \
    wpa_supplicant -s -ieth0 -O /var/run/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant.conf -B
