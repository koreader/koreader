#!/bin/sh

if lsmod | grep -q brcmfmac; then
    ifconfig wlan0 up
else
    modprobe brcmfmac
fi

# clean stop (if it's running) of main wpa_supplicant service, used by xochitl
systemctl stop wpa_supplicant
# clean stop of non-service wpa_supplicant, if running
wpa_cli terminate 2>/dev/null

sleep 1

wpa_supplicant -i wlan0 -C /var/run/wpa_supplicant -B 2>/dev/null
