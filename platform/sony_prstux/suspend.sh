#!/bin/bash

set -x

# enter sleep, disabling all devices except CPU
echo mem > /sys/power/state

# disable WiFi
./set-wifi.sh off

# set minimum CPU frequency during sleep
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# wait for sleep to complete
cat /sys/power/wait_for_fb_sleep
