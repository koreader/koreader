#!/bin/sh

# disable wifi and remove modules

read -r MACHINE_TYPE <"/sys/devices/soc0/machine"

if [ "reMarkable 2.0" = "${MACHINE_TYPE}" ]; then
    # clean stop (if it's running) of main wpa_supplicant service, used by xochitl
    systemctl stop wpa_supplicant
    # clean stop of non-service wpa_supplicant, if running
    wpa_cli terminate 2>/dev/null

    # power down wifi interface
    ifconfig wlan0 down 2>/dev/null

    # remove module: IMPORTANT to do this before device suspends
    modprobe -r brcmfmac 2>/dev/null
fi
