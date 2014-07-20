#!/bin/sh
export PATH=$PATH:/sbin:/usr/sbin

case $1 in
    on )
	for mod in sdio_wifi_pwr dhd; do
	    insmod /drivers/ntx508/wifi/${mod}.ko 2>/dev/null
	done
	sleep 1
	ifconfig eth0 up
	wlarm_le -i eth0 up
	wpa_supplicant -s -i eth0 -c /etc/wpa_supplicant/wpa_supplicant.conf -C /var/run/wpa_supplicant -B
	sleep 1
	udhcpc -S -i eth0 -s /etc/udhcpc.d/default.script -t15 -T10 -A3 -b -q >/dev/null 2>&1 &
	;;
    off )
	killall wpa_supplicant 2>/dev/null
	wlarm_le -i eth0 down
	ifconfig eth0 down
	rmmod -r dhd
	rmmod -r sdio_wifi_pwr
	;;
esac
