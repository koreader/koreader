#!/bin/sh

# load brcmfmac kernel module
if ! grep -q "^brcmfmac " "/proc/modules"; then
    modprobe brcmfmac
    sleep 1
fi

# stop wpa_supplicant service cleanly, used by xochitl
if systemctl is-active -q wpa_supplicant; then
    systemctl stop wpa_supplicant
fi

# stop non-service wpa_supplicant cleanly
if pidof wpa_supplicant; then
    wpa_cli terminate
fi

# power up wifi interface
ifconfig wlan0 up

# make sure dhcpcd is running
if ! systemctl is-active -q dhcpcd; then
    systemctl start dhcpcd
fi

wpa_supplicant -i wlan0 -C /var/run/wpa_supplicant -B
