#!/bin/sh
#
# Wi-Fi up/down for Bookeen Cybook devices.

IFACE=wlan0
WLAN_MODULE=/lib/modules/3.0.8+/8188eu.ko
IFCONFIG=/sbin/ifconfig
INSMOD=/sbin/insmod
LSMOD=/sbin/lsmod
RMMOD=/sbin/rmmod
# Use absolute paths because KOReader may inherit a limited PATH.
WPA_SUPPLICANT=/usr/sbin/wpa_supplicant
WPA_CLI=/usr/sbin/wpa_cli
WPA_CTRL_DIR=/var/run/wpa_supplicant

# Disable leisure power save in the Bookeen 8188eu driver. This must be set when
# the module loads because the driver copies the value during initialization.
WLAN_MODULE_PARAMS="rtw_power_mgnt=0"

# Start wpa_supplicant and wait for the Bookeen control socket.
start_supplicant()
{
	if [ ! -e "$WPA_CTRL_DIR/$IFACE" ]; then
		# Bookeen has no wpa_supplicant.conf; KOReader supplies networks later.
		$WPA_SUPPLICANT -B -D wext -i $IFACE -C $WPA_CTRL_DIR
	fi

	# Wait up to 10 seconds; Bookeen BusyBox sleep has only whole-second waits.
	ctrl_timeout=0
	while [ ! -e "$WPA_CTRL_DIR/$IFACE" ]; do
		if [ $ctrl_timeout -ge 40 ]; then
			echo "wlan.sh: wpa_supplicant control socket $WPA_CTRL_DIR/$IFACE never appeared"
			return 1
		fi
		usleep 250000
		ctrl_timeout=$((ctrl_timeout + 1))
	done

	return 0
}

start ()
{
	echo "Loading WLAN driver"

	#check if wlan driver is already up
	wlan_if=`$IFCONFIG | grep $IFACE`

	if [ -n "$wlan_if" ]; then
		# The interface may survive suspend while wpa_supplicant does not.
		start_supplicant
		return $?
	fi

	# Reload a leftover module so WLAN_MODULE_PARAMS is applied on Bookeen.
	if [ -n "`$LSMOD | grep 8188eu`" ]; then
		echo "wlan.sh: 8188eu loaded but $IFACE is down, reloading for parameters"
		$RMMOD 8188eu
	fi

	if [ ! -f $WLAN_MODULE ]; then
		return 1
	fi

	/sbin/nvram
	if [ $? -ne 0 ]; then
		echo "Error : nvram is in read only. Using default MAC address : 90:D7:4F:42:42:42"
		MAC_ADDR="90:D7:4F:42:42:42"
	else
		MAC_ADDR=`/sbin/nvram -e | cut -d '=' -f2`
	fi

	$INSMOD $WLAN_MODULE rtw_initmac=$MAC_ADDR $WLAN_MODULE_PARAMS

	sleep 1

	wlan_loaded=`$LSMOD | grep 8188eu`

	if [ -n "$wlan_loaded" ]; then
		$IFCONFIG $IFACE up
	else
		return 2
	fi

	start_supplicant
	return $?
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
		# The Bookeen control socket lives under the temporary runtime directory.
		$WPA_CLI -p $WPA_CTRL_DIR -i $IFACE terminate
		$IFCONFIG $IFACE down
		$RMMOD 8188eu
		return 0
	else
		return 1
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

# Propagate the action's status. The vendor script always exited 0, which hid
# every failure above from NetworkMgr.
exit $?
