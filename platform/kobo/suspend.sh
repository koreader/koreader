#!/bin/sh
export PATH="${PATH}:/sbin:/usr/sbin"

# Disable wifi
if lsmod | grep -q sdio_wifi_pwr ; then
	wlarm_le -i eth0 down
	ifconfig eth0 down
	rmmod -r dhd
	rmmod -r sdio_wifi_pwr
fi

# Go to sleep
sync
echo 1 > /sys/power/state-extended
sleep 2	# Because reasons?
echo mem > /sys/power/state	# This will return -EBUSY, for some reason...
