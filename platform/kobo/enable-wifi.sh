#!/bin/sh

# Load wifi modules and enable wifi.

lsmod | grep -q sdio_wifi_pwr || insmod "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko"
# Moar sleep!
usleep 500000
# WIFI_MODULE_PATH = /drivers/$PLATFORM/wifi/$WIFI_MODULE.ko
lsmod | grep -q "${WIFI_MODULE}" || insmod "${WIFI_MODULE_PATH}"
# Race-y as hell, don't try to optimize this!
sleep 1

ifconfig "${INTERFACE}" up
usleep 500000
[ "${WIFI_MODULE}" != "8189fs" ] && [ "${WIFI_MODULE}" != "8192es" ] && wlarm_le -i "${INTERFACE}" up && usleep 500000

pkill -0 wpa_supplicant ||
    env -u LD_LIBRARY_PATH \
        wpa_supplicant -D wext -s -i "${INTERFACE}" -O /var/run/wpa_supplicant -c /etc/wpa_supplicant/wpa_supplicant.conf -B

usleep 500000
