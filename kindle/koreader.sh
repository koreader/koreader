#!/bin/sh
export LC_ALL="en_US.UTF-8"

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
[ -e $PROC_KEYPAD ] && echo unlock > $PROC_KEYPAD
[ -e $PROC_FIVEWAY ] && echo unlock > $PROC_FIVEWAY

# KOReader's working directory
KOREADER_DIR="/mnt/us/koreader"

# Load our helper functions...
if [ -f "${KOREADER_DIR}/libkohelper.sh" ] ; then
	source "${KOREADER_DIR}/libkohelper.sh"
else
	echo "Can't source helper functions, aborting!"
	exit 1
fi

# Handle logging...
logmsg()
{
	# Use the right tools for the platform
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		msg "koreader: ${1}" "I"
	elif [ "${INIT_TYPE}" == "upstart" ] ; then
		f_log I koreader wrapper "" "${1}"
	fi

	# And throw that on stdout too, for the DIY crowd ;)
	echo "${1}"
}

# Go away if we're on FW 5.0, it's not supported
if [ "${INIT_TYPE}" == "upstart" ] ; then
	if grep '^Kindle 5\.0' /etc/prettyversion.txt > /dev/null 2>&1 ; then
		logmsg "FW 5.0 is not supported. Update to 5.1!"
		# And... scene!
		exit 0
	fi
fi

# Keep track of what we do with pillow...
PILLOW_DISABLED="no"

# Keep track of if we were started through KUAL
FROM_KUAL="no"

# By default, don't stop the framework.
if [ "$1" == "--framework_stop" ] ; then
	shift 1
	STOP_FRAMEWORK="yes"
	NO_SLEEP="no"
elif [ "$1" == "--asap" ] ; then
	# Start as soon as possible, without sleeping to workaround UI quirks
	shift 1
	NO_SLEEP="yes"
	STOP_FRAMEWORK="no"
else
	STOP_FRAMEWORK="no"
	NO_SLEEP="no"
fi

# Detect if we were started by KUAL by checking our nice value...
if [ "$(nice)" == "5" ] ; then
	FROM_KUAL="yes"
	if [ "${NO_SLEEP}" == "no" ] ; then
		# Yield a bit to let stuff stop properly...
		logmsg "Hush now . . ."
		# NOTE: This may or may not be terribly useful...
		usleep 250000
	fi

	# Kindlet threads spawn with a nice value of 5, go back to a neutral value
	logmsg "Be nice!"
	renice -n -5 $$
fi

# we're always starting from our working directory
cd "${KOREADER_DIR}"

# Handle pending OTA update
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
if [ -f "${NEWUPDATE}" ] ; then
	logmsg "Updating koreader . . ."
	# Look for our own GNU tar build to do a fancy progress tracking...
	GNUTAR_BIN="${KOREADER_DIR}/tar"
	if [ -x "${GNUTAR_BIN}" ] ; then
		# Let our checkpoint script handle the detailed visual feedback...
		eips_print_bottom_centered "Updating koreader" 1
		${GNUTAR_BIN} -C "/mnt/us" --checkpoint=200 --checkpoint-action=exec='./kotar_cpoint $TAR_CHECKPOINT' -xf "${NEWUPDATE}"
	else
		# Fall back to busybox tar
		eips_print_bottom_centered "Updating koreader . . ." 1
		tar -C "/mnt/us" -xf "${NEWUPDATE}"
	fi
	# Cleanup behind us...
	if [ $? -eq 0 ] ; then
		rm "${NEWUPDATE}"
		logmsg "Update sucessful :)"
		eips_print_bottom_centered "Update sucessful :)" 1
	else
		# Huh ho...
		logmsg "Update failed :("
		eips_print_bottom_centered "Update failed :(" 1
	fi
fi

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# accept input ports for zsync plugin
logmsg "Setting up IPTables rules . . ."
iptables -A INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

# bind-mount system fonts
if ! grep ${KOREADER_DIR}/fonts/host /proc/mounts > /dev/null 2>&1 ; then
	logmsg "Mounting system fonts . . ."
	mount -o bind /usr/java/lib/fonts ${KOREADER_DIR}/fonts/host
fi

# bind-mount altfonts
if [ -d /mnt/us/fonts ] ; then
	mkdir -p ${KOREADER_DIR}/fonts/altfonts
	if ! grep ${KOREADER_DIR}/fonts/altfonts /proc/mounts > /dev/null 2>&1 ; then
		logmsg "Mounting altfonts . . ."
		mount -o bind /mnt/us/fonts ${KOREADER_DIR}/fonts/altfonts
	fi
fi

# bind-mount linkfonts
if [ -d /mnt/us/linkfonts/fonts ] ; then
	mkdir -p ${KOREADER_DIR}/fonts/linkfonts
	if ! grep ${KOREADER_DIR}/fonts/linkfonts /proc/mounts > /dev/null 2>&1 ; then
		logmsg "Mounting linkfonts . . ."
		mount -o bind /mnt/us/linkfonts/fonts ${KOREADER_DIR}/fonts/linkfonts
	fi
fi

# check if we are supposed to shut down the Amazon framework
if [ "${STOP_FRAMEWORK}" == "yes" ] ; then
	logmsg "Stopping the framework . . ."
	# Upstart or SysV?
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		/etc/init.d/framework stop
	else
		# The framework job sends a SIGTERM on stop, trap it so we don't get killed if we were launched by KUAL
		trap "" SIGTERM
		stop lab126_gui
		# NOTE: Let the framework teardown finish, so we don't start before the black screen...
		usleep 1250000
		# And remove the trap like a ninja now!
		trap - SIGTERM
	fi
fi

# check if kpvbooklet was launched for more than once, if not we will disable pillow
# there's no pillow if we stopped the framework, and it's only there on systems with upstart anyway
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "upstart" ] ; then
	count=$(lipc-get-prop -eiq com.github.koreader.kpvbooklet.timer count)
	if [ "$count" == "" -o "$count" == "0" ] ; then
		#logmsg "Disabling pillow . . ."
		#lipc-set-prop com.lab126.pillow disableEnablePillow disable
		logmsg "Hiding the status bar . . ."
		# NOTE: One more great find from eureka (http://www.mobileread.com/forums/showpost.php?p=2454141&postcount=34)
		lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.hideMe();"}'
		PILLOW_DISABLED="yes"
		if [ "${NO_SLEEP}" == "no" ] ; then
			# NOTE: Leave the framework time to refresh the screen, so we don't start before it has finished redrawing after collapsing the title bar
			usleep 250000
			# NOTE: If we were started from KUAL, we risk getting a list item to popup right over us, so, wait some more...
			# The culprit appears to be a I WindowManager:flashTimeoutExpired:window=Root 0 0 600x30
			if [ "${FROM_KUAL}" == "yes" ] ; then
				logmsg "Playing possum to wait for the window manager . . ."
				usleep 2500000
			fi
		fi
	fi
fi

# stop cvm (sysv & framework up only)
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "sysv" ] ; then
	logmsg "Stopping cvm . . ."
	killall -stop cvm
fi

# finally call reader
logmsg "Starting KOReader . . ."
eips_print_bottom_centered "Starting KOReader . . ." 1
./reader.lua "$@" 2> crash.log

# clean up our own process tree in case the reader crashed (if needed, to avoid flooding KUAL's log)
if pidof reader.lua > /dev/null 2>&1 ; then
	logmsg "Sending a SIGTERM to stray KOreader processes . . ."
	killall -TERM reader.lua
fi

# unmount system fonts
if grep ${KOREADER_DIR}/fonts/host /proc/mounts > /dev/null 2>&1 ; then
	logmsg "Unmounting system fonts . . ."
	umount ${KOREADER_DIR}/fonts/host
fi

# unmount altfonts
if grep ${KOREADER_DIR}/fonts/altfonts /proc/mounts > /dev/null 2>&1 ; then
	logmsg "Unmounting altfonts . . ."
	umount ${KOREADER_DIR}/fonts/altfonts
fi

# unmount linkfonts
if grep ${KOREADER_DIR}/fonts/linkfonts /proc/mounts > /dev/null 2>&1 ; then
	logmsg "Unmounting linkfonts . . ."
	umount ${KOREADER_DIR}/fonts/linkfonts
fi

# Resume cvm (only if we stopped it)
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "sysv" ] ; then
	logmsg "Resuming cvm . . ."
	killall -cont cvm
fi

# Restart framework (if need be)
if [ "${STOP_FRAMEWORK}" == "yes" ] ; then
	logmsg "Restarting framework . . ."
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		/etc/init.d/framework start
	else
		start lab126_gui
	fi
fi

# display chrome bar (upstart & framework up only)
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "upstart" ] ; then
	# Only if we actually killed it...
	if [ "${PILLOW_DISABLED}" == "yes" ] ; then
		#logmsg "Enabling pillow . . ."
		#lipc-set-prop com.lab126.pillow disableEnablePillow enable
		logmsg "Restoring the status bar . . ."
		lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.showMe();"}'
		# Poke the search bar too, so that we get a proper refresh ;)
		lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "search_bar", "function": "nativeBridge.hideMe(); nativeBridge.showMe();"}'
	fi
fi

# restore firewall rules
logmsg "Restoring IPTables rules . . ."
iptables -D INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -D INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

