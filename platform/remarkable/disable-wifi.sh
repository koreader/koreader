#!/bin/sh

# clean stop of wpa_supplicant service, used by xochitl
if systemctl is-active -q wpa_supplicant; then
    systemctl stop wpa_supplicant
fi

# clean stop of non-service wpa_supplicant
if pidof wpa_supplicant >/dev/null; then
    wpa_cli terminate
fi

# stop dhcpcd if not enabled
if ! systemctl is-enabled -q dhcpcd; then
    systemctl stop dhcpcd
fi

# power down wifi interface
ifconfig wlan0 down

# unload brcmfmac kernel module
if grep -q "^brcmfmac " "/proc/modules"; then
    modprobe -r brcmfmac
fi
