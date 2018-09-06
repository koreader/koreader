#!/bin/bash

set -x

# wake all devices up
echo on >/sys/power/state

# go back to conservative governor
echo conservative >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# wait for resume to complete
cat /sys/power/wait_for_fb_wake
