#!/bin/sh
WPA_SUPPLICANT_CONF="/mnt/private/koreader/wpa_supplicant.conf"
CTRL_INTERFACE="/var/run/wpa_supplicant"

# create a new configuration if neccesary.
if [ ! -f "$WPA_SUPPLICANT_CONF" ]; then
    echo "ctrl_interface=DIR=${CTRL_INTERFACE}" > "$WPA_SUPPLICANT_CONF"
    echo "update_config=1" >> "$WPA_SUPPLICANT_CONF"
    sync
fi

if ! lsmod | grep -q 8189fs; then
    modprobe 8189fs
    sleep 1
fi

ifconfig eth0 up && sleep 1
wpa_supplicant -B -D wext -i eth0 -s -O "$CTRL_INTERFACE" -c "$WPA_SUPPLICANT_CONF" 2>/dev/null
