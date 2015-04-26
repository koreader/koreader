#!/bin/sh
PATH="${PATH}:/usr/sbin:/sbin"

# Handle the rotation weirdness on some devices
cur_rotate="$(cat "/sys/class/graphics/fb0/rotate")"

# start fmon again:
( usleep 400000; /etc/init.d/on-animator.sh ) &

# environment needed by nickel, from /etc/init.d/rcS:

INTERFACE="wlan0"
WIFI_MODULE="ar6000"
if [ "${PLATFORM}" != "freescale" ] ; then
	INTERFACE="eth0"
	WIFI_MODULE="dhd"
fi
export INTERFACE
export WIFI_MODULE

export NICKEL_HOME="/mnt/onboard/.kobo"
export LD_LIBRARY_PATH="/usr/local/Kobo"

export WIFI_MODULE_PATH="/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko"
export LANG="en_US.UTF-8"


# start nickel again (from tshering's start menu v0.4), this should
# cover all firmware versions from 2.6.1 to 3.4.1 (tested on a kobo
# mini with 3.4.1 firmware)

(
	/usr/local/Kobo/pickel disable.rtc.alarm
	if [ ! -e "/etc/wpa_supplicant/wpa_supplicant.conf" ] ; then
		cp "/etc/wpa_supplicant/wpa_supplicant.conf.template" "/etc/wpa_supplicant/wpa_supplicant.conf"
	fi
	echo 1 > "/sys/devices/platform/mxc_dvfs_core.0/enable"
	/sbin/hwclock -s -u
) &

if [ ! -e "/usr/local/Kobo/platforms/libkobo.so" ] ; then
	export QWS_KEYBOARD="imx508kbd:/dev/input/event0"
	export QT_PLUGIN_PATH="/usr/local/Kobo/plugins"
	if [ -e "/usr/local/Kobo/plugins/gfxdrivers/libimxepd.so" ] ; then
		export QWS_DISPLAY="imxepd"
	else
		export QWS_DISPLAY="Transformed:imx508:Rot90"
		export QWS_MOUSE_PROTO="tslib_nocal:/dev/input/event1"
	fi
	/usr/local/Kobo/hindenburg &
	/usr/local/Kobo/nickel -qws -skipFontLoad
else
	/usr/local/Kobo/hindenburg &
	lsmod | grep -q lowmem || insmod "/drivers/${PLATFORM}/misc/lowmem.ko" &
	if grep -q "dhcpcd=true" "/mnt/onboard/.kobo/Kobo/Kobo eReader.conf" ; then
		dhcpcd -d -t 10 &
	fi
	/usr/local/Kobo/nickel -platform kobo -skipFontLoad
fi

# Rotation weirdness, part II
echo "${cur_rotate}" > "/sys/class/graphics/fb0/rotate"
cat "/sys/class/graphics/fb0/rotate" > "/sys/class/graphics/fb0/rotate"
