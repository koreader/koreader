#!/bin/bash

set -x
if [ "$1" = "on" ]; then
    wmiconfig -i wlan0 --wlan enable
    wmiconfig -i wlan0 --setreassocmode 0
    wmiconfig -i wlan0 --power maxperf
    /sbin/wpa_supplicant -B -i wlan0 -D wext -C /var/run/wpa_supplicant -f /var/log/wpa_supplicant.log
else
    if [ "$(pidof wpa_supplicant)" != "" ]; then
        kill "$(pidof wpa_supplicant)"
    fi
    wmiconfig -i wlan0 --wlan disable
fi
