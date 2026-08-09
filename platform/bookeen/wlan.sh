#!/bin/sh

IFACE=wlan0
WLAN_MODULE=/lib/modules/3.0.8+/8188eu.ko
IFCONFIG=/sbin/ifconfig
INSMOD=/sbin/insmod
LSMOD=/sbin/lsmod
RMMOD=/sbin/rmmod

start ()
{
	echo "Loading WLAN driver"

	#check if wlan driver is already up
	wlan_if=`$IFCONFIG | grep $IFACE`

	if [ -n "$wlan_if" ]; then
		#WLAN interface already up
		return 0
	fi

	if [ ! -f $WLAN_MODULE ]; then
		return -1
	fi

	/sbin/nvram
	if [ $? -ne 0 ]; then
		echo "Error : nvram is in read only. Using default MAC address : 90:D7:4F:42:42:42"
		MAC_ADDR="90:D7:4F:42:42:42"
	else
		MAC_ADDR=`/sbin/nvram -e | cut -d '=' -f2`
	fi

	$INSMOD $WLAN_MODULE rtw_initmac=$MAC_ADDR

	sleep 1

	wlan_loaded=`$LSMOD | grep 8188eu`

	if [ -n "$wlan_loaded" ]; then
		$IFCONFIG $IFACE up
	else
		return -2
	fi
  
	wpa_supplicant -B -i wlan0 -C /var/run/wpa_supplicant
	
  return 0
}

suspend()
{
	power s 8188eu
}

resume()
{
	power 1 8188eu
}

stop ()
{
	echo "Unloading WLAN driver"
	wlan_loaded=`$LSMOD | grep 8188eu`

	if [ -n "$wlan_loaded" ]; then
		wpa_cli terminate
		$IFCONFIG $IFACE down
		$RMMOD 8188eu
		return 0
	else
		return -1
	fi
}

restart ()
{
	stop
	start
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	suspend)
		suspend
		;;
	resume)
		resume
		;;
	restart)
		restart
		;;
	*)
		echo "Usage: $0 {start|stop|restart}"
		exit 1
esac

exit 0
