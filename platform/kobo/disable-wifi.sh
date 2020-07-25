#!/bin/sh

# Disable wifi, and remove all modules.
# NOTE: Save our resolv.conf to avoid ending up with an empty one, in case the DHCP client wipes it on release (#6424).
cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
if [ -x "/sbin/dhcpcd" ]; then
    env -u LD_LIBRARY_PATH dhcpcd -d -k "${INTERFACE}"
    killall udhcpc default.script 2>/dev/null
else
    killall udhcpc default.script dhcpcd 2>/dev/null
fi
mv -f "/tmp/resolv.ko" "/etc/resolv.conf"
wpa_cli terminate

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
