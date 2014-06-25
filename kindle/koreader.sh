#!/bin/sh
export LC_ALL="en_US.UTF-8"

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
[ -e $PROC_KEYPAD ] && echo unlock > $PROC_KEYPAD
[ -e $PROC_FIVEWAY ] && echo unlock > $PROC_FIVEWAY

# By default, don't stop the framework.
if [ "$1" == "--framework_stop" ] ; then
	shift 1
	STOP_FRAMEWORK="yes"
	# Yield a bit to let stuff stop properly...
	echo "Stopping framework . . ."
	sleep 2
else
	STOP_FRAMEWORK="no"
fi

# Check which type of init system we're using
if [ -d /etc/upstart ] ; then
	INIT_TYPE="upstart"
else
	INIT_TYPE="sysv"
fi

# we're always starting from our working directory
cd /mnt/us/koreader

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# accept input ports for zsync plugin
iptables -A INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

# bind-mount system fonts
if ! grep /mnt/us/koreader/fonts/host /proc/mounts ; then
	mount -o bind /usr/java/lib/fonts /mnt/us/koreader/fonts/host
fi

# bind-mount altfonts
if [ -d /mnt/us/fonts ] ; then
	mkdir -p /mnt/us/koreader/fonts/altfonts
	if ! grep /mnt/us/koreader/fonts/altfonts /proc/mounts ; then
		mount -o bind /mnt/us/fonts /mnt/us/koreader/fonts/altfonts
	fi
fi

# bind-mount linkfonts
if [ -d /mnt/us/linkfonts/fonts ] ; then
	mkdir -p /mnt/us/koreader/fonts/linkfonts
	if ! grep /mnt/us/koreader/fonts/linkfonts /proc/mounts ; then
		mount -o bind /mnt/us/linkfonts/fonts /mnt/us/koreader/fonts/linkfonts
	fi
fi

# check if we are supposed to shut down the Amazon framework
if [ "${STOP_FRAMEWORK}" == "yes" ]; then
	# Upstart or SysV?
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		/etc/init.d/framework stop
	else
		# The framework job sends a SIGTERM on stop, trap it so we don't get killed if we were launched by KUAL
		trap "" SIGTERM
		stop lab126_gui
	fi
fi

# check if kpvbooklet was launched for more than once, if not we will disable pillow
# there's no pillow if we stopped the framework, and it's only there on systems with upstart anyway
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "upstart" ] ; then
	count=`lipc-get-prop -eiq com.github.koreader.kpvbooklet.timer count`
	if [ "$count" == "" -o "$count" == "0" ]; then
		lipc-set-prop com.lab126.pillow disableEnablePillow disable
	fi
fi

# stop cvm (sysv & framework up only)
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "sysv" ] ; then
	killall -stop cvm
fi

# finally call reader
./reader.lua "$@" 2> crash.log

# clean up forked process in case the reader crashed
if [ "${INIT_TYPE}" == "sysv" ] ; then
	killall -TERM reader.lua
else
	# We trapped SIGTERM, remember? ;)
	killall -KILL reader.lua
fi

# unmount system fonts
if grep /mnt/us/koreader/fonts/host /proc/mounts ; then
	umount /mnt/us/koreader/fonts/host
fi

# unmount altfonts
if grep /mnt/us/koreader/fonts/altfonts /proc/mounts ; then
	umount /mnt/us/koreader/fonts/altfonts
fi

# unmount linkfonts
if grep /mnt/us/koreader/fonts/linkfonts /proc/mounts ; then
	umount /mnt/us/koreader/fonts/linkfonts
fi

# always try to continue cvm
if ! killall -cont cvm ; then
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		/etc/init.d/framework start
	else
		start lab126_gui
	fi
fi

# display chrome bar (upstart & framework up only)
if [ "${STOP_FRAMEWORK}" == "no" -a "${INIT_TYPE}" == "upstart" ] ; then
	lipc-set-prop com.lab126.pillow disableEnablePillow enable
fi

# restore firewall rules
iptables -D INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -D INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

