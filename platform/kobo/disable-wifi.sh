#!/bin/sh

# Disable wifi, and remove all modules.
# NOTE: Trying to do this nicely with 'wpa_cli terminate' and 'dhcpcd -d -k "${INTERFACE}"' trips mysterious buggy corner-cases... (#6424)
killall udhcpc default.script dhcpcd wpa_supplicant 2>/dev/null

[ "${WIFI_MODULE}" != "8189fs" ] && [ "${WIFI_MODULE}" != "8192es" ] && wlarm_le -i "${INTERFACE}" down
ifconfig "${INTERFACE}" down

# Some sleep in between may avoid system getting hung
# (we test if a module is actually loaded to avoid unneeded sleeps)
if lsmod | grep -q "${WIFI_MODULE}"; then
    usleep 250000
    rmmod "${WIFI_MODULE}"
fi
if lsmod | grep -q sdio_wifi_pwr; then
    usleep 250000
    rmmod sdio_wifi_pwr
fi
