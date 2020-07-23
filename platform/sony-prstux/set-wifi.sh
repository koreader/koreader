#!/bin/bash

set -x
if [ "$1" = "on" ]; then
    wmiconfig -i wlan0 --wlan enable
    wmiconfig -i wlan0 --setreassocmode 0
    wmiconfig -i wlan0 --power maxperf
    echo "Wi-Fi Enabled"
else
    wmiconfig -i wlan0 --abortscan
    wmiconfig -i wlan0 --wlan disable
    echo "Wi-Fi Disabled"
fi
