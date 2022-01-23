#!/bin/sh

# disable wifi and remove modules

# clean stop (if it's running) of main wpa_supplicant service, used by xochitl
systemctl stop wpa_supplicant
# clean stop of non-service wpa_supplicant, if running
wpa_cli terminate 2>/dev/null

# power down wifi interface
ifconfig wlan0 down 2>/dev/null

# remove module
modprobe -r brcmfmac 2>/dev/null
