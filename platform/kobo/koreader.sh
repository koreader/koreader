#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# update to new version from OTA directory
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
if [ -f "${NEWUPDATE}" ] ; then
	# TODO: any graphic indication for the updating progress?
	cd "${KOREADER_DIR%/*}" && tar xf "${NEWUPDATE}" && mv "${NEWUPDATE}" "${INSTALLED}"
fi

# we're always starting from our working directory
cd "${KOREADER_DIR}"

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directory
export EXT_FONT_DIR="/mnt/onboard/fonts"

# fast and dirty way of check if we are called from nickel
# through fmon, or from another launcher (KSM or advboot)
from_nickel="false"
if pkill -0 nickel ; then
	from_nickel="true"
fi

if [ "${from_nickel}" == "true" ] ; then
	# Siphon a few things from nickel's env...
	eval "$(xargs -n 1 -0 < /proc/$(pidof nickel)/environ | grep -e DBUS_SESSION_BUS_ADDRESS -e WIFI_MODULE -e PLATFORM -e WIFI_MODULE_PATH -e INTERFACE -e PRODUCT 2>/dev/null)"
	export DBUS_SESSION_BUS_ADDRESS WIFI_MODULE PLATFORM WIFI_MODULE_PATH INTERFACE PRODUCT

	# flush disks, might help avoid trashing nickel's DB...
	sync
	# stop kobo software because it's running
	killall nickel hindenburg fmon 2>/dev/null
fi

# fallback for old fmon (and advboot) users (-> if no args were passed to the sript, start the FM)
if [ "$#" -eq 0 ] ; then
	args="/mnt/onboard"
else
	args="$@"
fi

# check whether PLATFORM & PRODUCT have a value assigned by rcS
if [ ! -n "${PRODUCT}" ] ; then
	PRODUCT="$(/bin/kobo_config.sh)"
	[ "${PRODUCT}" != "trilogy" ] && PREFIX="${PRODUCT}-"
	export PRODUCT
fi

# PLATFORM is used in koreader for the path to the WiFi drivers
if [ ! -n "${PLATFORM}" ] ; then
	PLATFORM="freescale"
	if dd if="/dev/mmcblk0" bs=512 skip=1024 count=1 | grep -q "HW CONFIG" ; then
		CPU="$(ntx_hwconfig -s -p /dev/mmcblk0 CPU)"
		PLATFORM="${CPU}-ntx"
	fi

	if [ "${PLATFORM}" == "freescale" ] ; then
		if [ ! -s "/lib/firmware/imx/epdc_E60_V220.fw" ] ; then
			mkdir -p "/lib/firmware/imx"
			dd if="/dev/mmcblk0" bs=512K skip=10 count=1 | zcat > "/lib/firmware/imx/epdc_E60_V220.fw"
			sync
		fi
	elif [ ! -e "/etc/u-boot/${PLATFORM}/u-boot.mmc" ] ; then
		PLATFORM="ntx508"
	fi
	export PLATFORM
fi
# end of value check of PLATFORM

# Remount the SD card RW if it's inserted and currently RO
if awk '$4~/(^|,)ro($|,)/' /proc/mounts | grep ' /mnt/sd ' ; then
	mount -o remount,rw /mnt/sd
fi

./reader.lua "${args}" 2> crash.log

if [ "${from_nickel}" == "true" ] ; then
	# start kobo software because it was running before koreader
	./nickel.sh &
else
	# if we were called from advboot then we must reboot to go to the menu
	# NOTE: This is actually achieved by checking if KSM or a KSM-related script is running:
	#       This might lead to false-positives if you use neither KSM nor advboot to launch KOReader *without nickel running*.
	if ! pgrep -f kbmenu > /dev/null 2>&1 ; then
		reboot
	fi
fi

return 0
