#!/bin/sh
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib"

# Handle the rotation weirdness on some devices
cur_rotate="$(cat "/sys/class/graphics/fb0/rotate")"

# start fmon again. Note that we don't have to worry about reaping this, nickel kills on-animator.sh on start.
( usleep 400000; /etc/init.d/on-animator.sh ) &

# environment needed by nickel, from /etc/init.d/rcS:

if [ ! -n "${WIFI_MODULE_PATH}" ] ; then
	INTERFACE="wlan0"
	WIFI_MODULE="ar6000"
	if [ "${PLATFORM}" != "freescale" ] ; then
		INTERFACE="eth0"
		WIFI_MODULE="dhd"
	fi
	export INTERFACE
	export WIFI_MODULE
	export WIFI_MODULE_PATH="/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko"
fi

export NICKEL_HOME="/mnt/onboard/.kobo"
export LD_LIBRARY_PATH="/usr/local/Kobo"

export LANG="en_US.UTF-8"

# Make sure we kill the WiFi first, because nickel apparently doesn't like it if it's up... (cf. #1520)
# NOTE: That check is possibly wrong on PLATFORM == freescale (because I don't know if the sdio_wifi_pwr module exists there), but we don't terribly care about that.
if lsmod | grep -q sdio_wifi_pwr ; then
	killall udhcpc default.script wpa_supplicant 2>/dev/null
	wlarm_le -i ${INTERFACE} down
	ifconfig ${INTERFACE} down
	# NOTE: Kobo's busybox build is weird. rmmod appears to be modprobe in disguise, defaulting to the -r flag. If re-specifying -r starts to fail one day, switch to rmmod without args, or modprobe -r.
	rmmod -r ${WIFI_MODULE}
	rmmod -r sdio_wifi_pwr
fi

# Flush buffers to disk, who knows.
sync

# start nickel again (inspired from KSM, vlasovsoft & the base rcS), this should
# cover at least firmware versions from 2.6.1 to 3.12.1 (tested on a kobo
# mini with 3.4.1 firmware & a H2O on 3.12.1)

# NOTE: Since we're not cold booting, this is technically redundant... On the other hand, it doesn't really hurt either ;).
(
	/usr/local/Kobo/pickel disable.rtc.alarm

	if [ ! -e "/etc/wpa_supplicant/wpa_supplicant.conf" ] ; then
		cp "/etc/wpa_supplicant/wpa_supplicant.conf.template" "/etc/wpa_supplicant/wpa_supplicant.conf"
	fi

	# FWIW, that appears to be gone from recent rcS scripts. AFAICT, still harmless, though.
	echo 1 > "/sys/devices/platform/mxc_dvfs_core.0/enable"

	/sbin/hwclock -s -u
) &

# Hey there, nickel!
if [ ! -e "/usr/local/Kobo/platforms/libkobo.so" ] ; then
	export QWS_KEYBOARD="imx508kbd:/dev/input/event0"
	export QT_PLUGIN_PATH="/usr/local/Kobo/plugins"
	if [ -e "/usr/local/Kobo/plugins/gfxdrivers/libimxepd.so" ] ; then
		export QWS_DISPLAY="imxepd"
	else
		export QWS_DISPLAY="Transformed:imx508:Rot90"
		export QWS_MOUSE_PROTO="tslib_nocal:/dev/input/event1"
	fi
	# NOTE: Send the output to the void, to avoid spamming the shell with the output of the string of killall commands they periodically send
	/usr/local/Kobo/hindenburg > /dev/null 2>&1 &
	/usr/local/Kobo/nickel -qws -skipFontLoad > /dev/null 2>&1 &
else
	/usr/local/Kobo/hindenburg > /dev/null 2>&1 &
	lsmod | grep -q lowmem || insmod "/drivers/${PLATFORM}/misc/lowmem.ko" &
	if grep -q "dhcpcd=true" "/mnt/onboard/.kobo/Kobo/Kobo eReader.conf" ; then
		dhcpcd -d -t 10 &
	fi
	/usr/local/Kobo/nickel -platform kobo -skipFontLoad > /dev/null 2>&1 &
fi

# Ahoy, annoying sickel!
if [ -x /usr/local/Kobo/sickel ] ; then
    /usr/local/Kobo/sickel -platform kobo:noscreen > /dev/null 2>&1 &
fi


# Rotation weirdness, part II
echo "${cur_rotate}" > "/sys/class/graphics/fb0/rotate"
cat "/sys/class/graphics/fb0/rotate" > "/sys/class/graphics/fb0/rotate"

# Handle sdcard
if [ -e "/dev/mmcblk1p1" ] ; then
	echo sd add /dev/mmcblk1p1 >> /tmp/nickel-hardware-status &
fi

return 0
