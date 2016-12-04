#!/bin/sh

# Disable wifi, and remove all modules.

killall udhcpc default.script wpa_supplicant 2>/dev/null

wlarm_le -i eth0 down
ifconfig eth0 down

rmmod -r dhd
sleep 1 # sleeping a bit here may avoid system getting hung
rmmod -r sdio_wifi_pwr
