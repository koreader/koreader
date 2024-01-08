#!/bin/sh

# stop wpa_supplicant service cleanly, used by xochitl
if systemctl is-active -q wpa_supplicant; then
    systemctl stop wpa_supplicant
fi

# stop non-service wpa_supplicant cleanly
if pidof wpa_supplicant; then
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
