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
	# stop kobo software because is running
	killall nickel hindenburg fmon 2>/dev/null
fi

# fallback for old fmon (and advboot) users (-> if no args were passed to the sript, start the FM)
if [ "$#" -eq 0 ] ; then
	args="/mnt/onboard"
else
	args="$@"
fi

# check whether PLATFORM has a value assigned by rcS
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

./reader.lua "${args}" 2> crash.log

if [ "${from_nickel}" == "true" ] ; then
	# start kobo software because was running before koreader
	./nickel.sh
else
	# if we were called from advboot then we must reboot to go to the menu
	if [ -d "/mnt/onboard/.kobo/advboot" ] ; then
	# FIXME: This is not precise enough, cf. #1503; but that alternate proposition is way too drastic, it doesn't account for people running neither KSM nor advboot
	#if ! pkill -0 ksmhome.sh ; then
		reboot
	fi
fi
