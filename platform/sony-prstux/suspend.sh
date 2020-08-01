#!/bin/bash

set -x

# disable Wi-Fi
./set-wifi.sh off

# enter sleep, disabling all devices except CPU
echo mem >/sys/power/state

# set minimum CPU frequency during sleep
echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# wait for sleep to complete
cat /sys/power/wait_for_fb_sleep
