#!/bin/sh
#
# Wi-Fi up/down for Bookeen Cybook devices.
#
# This is the vendor's own /etc/init.d/wlan with three additions, all of which
# exist because KOReader -- unlike the stock reader -- talks to wpa_supplicant
# over its control socket instead of spawning its own:
#
#   1. wpa_supplicant is started here (the vendor script leaves that to boordr).
#   2. `start` WAITS for the control socket to appear before returning, and
#   3. `start` no longer returns early when the interface is already up without
#      checking that a supplicant is actually running behind it.
#
# (2) and (3) are not cosmetic. NetworkMgr:turnOnWifi() calls `./wlan.sh start`
# and then goes straight into reconnectOrShowNetworkMenu(), whose very first act
# is WpaClient.new("/var/run/wpa_supplicant/wlan0"). wpa_supplicant -B daemonizes
# *before* it has bound that socket, so returning as soon as the fork happened is
# a race: KOReader connects to a path that does not exist yet, reports "Failed to
# initialize network control client", and the whole connection attempt is aborted
# even though the radio came up fine. The vendor's fixed `sleep 1` covered the
# insmod, not the supplicant.
#
# Likewise, the early `return 0` on "interface already up" was reached on every
# retry after such a failure -- and on resume, where the module survived but the
# supplicant did not -- leaving KOReader to talk to a socket that would never
# appear.

IFACE=wlan0
WLAN_MODULE=/lib/modules/3.0.8+/8188eu.ko
IFCONFIG=/sbin/ifconfig
INSMOD=/sbin/insmod
LSMOD=/sbin/lsmod
RMMOD=/sbin/rmmod
# Spelled out because these two live in /usr/sbin, which is the directory most
# likely to be missing from an inherited PATH (BusyBox init exports only
# /sbin:/usr/sbin:/bin:/usr/bin, and /etc/profile's fuller PATH is set for
# interactive login shells only -- KOReader can be launched from ebrmain, which is
# neither). Same reason koreader.sh writes /bin/eink out in full.
WPA_SUPPLICANT=/usr/sbin/wpa_supplicant
WPA_CLI=/usr/sbin/wpa_cli
WPA_CTRL_DIR=/var/run/wpa_supplicant

# Disable 802.11 leisure power save on the radio.
#
# The shipped 8188eu.ko (v4.1.2_4787.20120803) is built with CONFIG_LPS and its
# compiled-in default is rtw_power_mgnt=1 -- read straight out of the binary's
# .data, not inferred: rtw_smart_ps=2, rtw_power_mgnt=1, rtw_ips_mode=1. With
# power_mgnt != PS_MODE_ACTIVE, rtw_pwrctrl.c sets bLeisurePs and
# rtw_dynamic_check_timer_handlder() calls LPS_Enter() whenever a 2-second window
# saw fewer than 8 packets (core/rtw_cmd.c:1937). LPS_Enter then waits for
# LpsIdleCount >= 2, i.e. ~4 s of idle, and drops the STA into PS mode.
#
# For a *reader* that is exactly the wrong heuristic. Browsing OPDS, syncing
# progress, or fetching news is bursty: request, several idle seconds while the
# user reads, next request. So the radio is in power save at the start of very
# nearly every transfer, and this driver generation is notoriously bad at getting
# back out -- the AP buffers, the null-frame handshake is missed, and the transfer
# stalls until something times out. That matches the reported symptom precisely:
# association succeeds and stays up (so the UI shows a connection), but anything
# that actually uses the link fails.
#
# rtw_power_mgnt is a module_param with 0644 permissions, so this could also be
# poked via /sys/module/8188eu/parameters -- but only *before* association, since
# pwrctrlpriv.power_mgnt is copied from registrypriv at init (rtw_pwrctrl.c:1216)
# and bLeisurePs is latched from it at line 1217. Setting it at insmod time is the
# only way to be sure it is honoured. IPS is left alone: rtw_ps_processor() only
# enters it when *not* linked (rtw_pwrctrl.c:196), so it costs nothing while
# connected and still saves power with the radio up but idle.
WLAN_MODULE_PARAMS="rtw_power_mgnt=0"

# Start wpa_supplicant unless one is already listening, then wait for its control
# socket. Returns non-zero if the socket never showed up, so `start` can report
# failure to NetworkMgr instead of letting it fail confusingly later on.
#
# -D wext is explicit rather than inherited. The stock wpa_supplicant (v0.7.3)
# has both wext and nl80211 compiled in, and 8188eu.ko is built with
# CONFIG_IOCTL_CFG80211 *and* keeps its wext handlers (os_intfs.c:960), so both
# interfaces answer. Its built-in probe order happens to try wext first, but
# relying on that is fragile, and wext is the one the vendor drives (`wext` and
# `/var/run/wpa_supplicant` both appear in strings on /mnt/app/boordr) -- i.e.
# the only one with any field mileage on this driver.
start_supplicant()
{
	if [ ! -e "$WPA_CTRL_DIR/$IFACE" ]; then
		# -C rather than -c: there is no /etc/wpa_supplicant.conf on this
		# rootfs, and -C is only honoured when -c is absent (per the binary's
		# own usage text). The networks are pushed in over the control socket
		# afterwards -- by KOReader's WpaSupplicant backend on a normal connect,
		# or by restore-wifi-async.sh on a resume.
		#
		# $WPA_CTRL_DIR is under /var/run, a symlink to ../tmp, i.e. tmpfs --
		# so wpa_supplicant can mkdir it even though / is mounted read-only.
		$WPA_SUPPLICANT -B -D wext -i $IFACE -C $WPA_CTRL_DIR
	fi

	# 10s at 250ms. `usleep` is a busybox applet on this rootfs; `sleep` only
	# takes whole seconds.
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
		# WLAN interface already up -- but the supplicant may not be (see the
		# header). Make sure of it before claiming success.
		start_supplicant
		return $?
	fi

	# The interface is not up, but the module may still be loaded -- the stock
	# reader leaves it that way, and so does a `$IFCONFIG $IFACE down` without an
	# rmmod. insmod would simply fail with EEXIST there, and the vendor script
	# limped on because the $LSMOD check below then succeeded and it just brought
	# the interface up. That silently keeps whatever parameters the *other* loader
	# chose, i.e. LPS enabled (see WLAN_MODULE_PARAMS). Drop it first so our
	# parameters actually take effect; nothing can be connected with the interface
	# down, so there is nothing to lose.
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
		# -p because the socket is under $WPA_CTRL_DIR; wpa_cli's compiled-in
		# default happens to be the same path, but do not depend on it.
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
