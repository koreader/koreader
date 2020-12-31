#!/bin/sh

if lsmod | grep -q brcmfmac; then
    ifconfig wlan0 up
else
    modprobe brcmfmac
fi

# clean out any other running instances of wpa_supplicant
killall wpa_supplicant 2>/dev/null

sleep 1

wpa_supplicant -i wlan0 -C /var/run/wpa_supplicant -B 2>/dev/null
