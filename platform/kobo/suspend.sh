#!/bin/sh
export PATH=$PATH:/sbin:/usr/sbin

#disable wifi
if lsmod | grep -q sdio_wifi_pwr ; then
	wlarm_le -i eth0 down
	ifconfig eth0 down
	rmmod -r dhd
	rmmod -r sdio_wifi_pwr
fi

#go to sleep
sync
echo 1 > /sys/power/state-extended
echo mem > /sys/power/state
