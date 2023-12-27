#!/bin/sh

# load brcmfmac kernel module
if ! lsmod | grep -q brcmfmac; then
    modprobe brcmfmac
    sleep 1
fi

# clean stop of wpa_supplicant service, used by xochitl
if systemctl is-active -q wpa_supplicant; then
    systemctl stop wpa_supplicant
fi

# clean stop of non-service wpa_supplicant
if pidof wpa_supplicant >/dev/null; then
    wpa_cli terminate
fi

# power up wifi interface
ifconfig wlan0 up

# make sure dhcpcd is running
if ! systemctl is-active -q dhcpcd; then
    systemctl start dhcpcd
fi

wpa_supplicant -i wlan0 -C /var/run/wpa_supplicant -B
