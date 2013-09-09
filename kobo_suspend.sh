#!/bin/sh
export PATH=$PATH:/sbin:/usr/sbin

ts_file=/tmp/back_from_suspend

if test -e $ts_file ; then
	sec_back_suspend=$(stat -t $ts_file | awk '{print $13}' )
	delta_sec=$(( $(date +%s) - $sec_back_suspend ))
	echo sec_back_suspend=$sec_back_suspend delta_sec=$delta_sec >> /tmp/event_test.txt
	test $delta_sec -gt 2 || exit 
fi

sleep 1

if lsmod | grep -q sdio_wifi_pwr ; then 
	wlarm_le -i eth0 down
	ifconfig eth0 down
	/sbin/rmmod -r dhd
	/sbin/rmmod -r sdio_wifi_pwr
fi


sleep 1

sync
echo 1 > /sys/power/state-extended
echo mem > /sys/power/state
echo 0 > /sys/power/state-extended

touch $ts_file
