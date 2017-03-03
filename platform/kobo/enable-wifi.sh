#!/bin/sh

# Load wifi modules and enable wifi.

lsmod | grep -q sdio_wifi_pwr || insmod /drivers/$PLATFORM/wifi/sdio_wifi_pwr.ko
# WIFI_MODULE_PATH = /drivers/$PLATFORM/wifi/$WIFI_MODULE.ko
lsmod | grep -q $WIFI_MODULE || insmod $WIFI_MODULE_PATH
sleep 1

ifconfig eth0 up
wlarm_le -i eth0 up

pidof wpa_supplicant >/dev/null || \
    env -u LD_LIBRARY_PATH \
    wpa_supplicant -D wext -s -ieth0 -O /var/run/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant.conf -B
