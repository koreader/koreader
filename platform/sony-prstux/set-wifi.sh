#!/bin/bash

set -x
if [ "$1" = "on" ]; then
    wmiconfig -i wlan0 --wlan enable
    wmiconfig -i wlan0 --setreassocmode 0
    wmiconfig -i wlan0 --power maxperf
    echo "WiFi Enabled"
else
    wmiconfig -i wlan0 --abortscan
    wmiconfig -i wlan0 --wlan disable
    echo "Wifi Disabled"
fi
