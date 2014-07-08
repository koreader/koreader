#!/bin/sh
#
# KUAL KOReader actions helper script
#
##

## A bit of helper functions...
# Check which type of init system we're running on
if [ -d /etc/upstart ] ; then
	INIT_TYPE="upstart"
	# We'll need that for logging
	[ -f /etc/upstart/functions ] && source /etc/upstart/functions
else
	INIT_TYPE="sysv"
	# We'll need that for logging
	[ -f /etc/rc.d/functions ] && source /etc/rc.d/functions
fi

# We need to get the proper constants for our model...
kmodel="$(cut -c3-4 /proc/usid)"
case "${kmodel}" in
	"24" | "1B" | "1D" | "1F" | "1C" | "20" | "D4" | "5A" | "D5" | "D6" | "D7" | "D8" | "F2" | "17" )
		# PaperWhite...
		SCREEN_X_RES=768	# NOTE: Yes, 768, not 758...
		SCREEN_Y_RES=1024
		EIPS_X_RES=16
		EIPS_Y_RES=24		# Manually mesured, should be accurate.
	;;
	* )
		# Handle legacy devices...
		if [ -f "/etc/rc.d/functions" ] && grep "EIPS" "/etc/rc.d/functions" > /dev/null 2>&1 ; then
			# Already done...
			#. /etc/rc.d/functions
			echo "foo" >/dev/null
		else
			# Touch
			SCREEN_X_RES=600	# _v_width @ upstart/functions
			SCREEN_Y_RES=800	# _v_height @ upstart/functions
			EIPS_X_RES=12		# from f_puts @ upstart/functions
			EIPS_Y_RES=20		# from f_puts @ upstart/functions
		fi
	;;
esac
# And now we can do the maths ;)
EIPS_MAXCHARS="$((${SCREEN_X_RES} / ${EIPS_X_RES}))"
EIPS_MAXLINES="$((${SCREEN_Y_RES} / ${EIPS_Y_RES}))"

# Adapted from libkh[5]
eips_print_bottom_centered()
{
	# We need at least two args
	if [ $# -lt 2 ] ; then
		echo "not enough arguments passed to eips_print_bottom ($# while we need at least 2)"
		return
	fi

	kh_eips_string="${1}"
	kh_eips_y_shift_up="${2}"

	# Get the real string length now
	kh_eips_strlen="${#kh_eips_string}"

	# Add the right amount of left & right padding, since we're centered, and eips doesn't trigger a full refresh,
	# so we'll have to padd our string with blank spaces to make sure two consecutive messages don't run into each other
	kh_padlen="$(((${EIPS_MAXCHARS} - ${kh_eips_strlen}) / 2))"

	# Left padding...
	while [ ${#kh_eips_string} -lt $((${kh_eips_strlen} + ${kh_padlen})) ] ; do
		kh_eips_string=" ${kh_eips_string}"
	done

	# Right padding (crop to the edge of the screen)
	while [ ${#kh_eips_string} -lt ${EIPS_MAXCHARS} ] ; do
		kh_eips_string="${kh_eips_string} "
	done

	# Sleep a tiny bit to workaround the logic in the 'new' (K4+) eInk controllers that tries to bundle updates,
	# otherwise it may drop part of our messages because of other screen updates from KUAL...
	usleep 150000	# 150ms

	# And finally, show our formatted message centered on the bottom of the screen (NOTE: Redirect to /dev/null to kill unavailable character & pixel not in range warning messages)
	eips 0 $((${EIPS_MAXLINES} - 2 - ${kh_eips_y_shift_up})) "${kh_eips_string}" >/dev/null
}

## Handle logging...
logmsg()
{
	# Use the right tools for the platform
	if [ "${INIT_TYPE}" == "sysv" ] ; then
		msg "koreader: ${1}" "I"
	elif [ "${INIT_TYPE}" == "upstart" ] ; then
		f_log I koreader kual "" "${1}"
	fi

	# And handle user visual feedback via eips...
	eips_print_bottom_centered "${1}" 1
}

## And now the actual useful stuff!

# Update koreader
update_koreader()
{
	# Check if we were called by install_koreader...
	if [ "${1}" == "clean" ] ; then
		do_clean_install="true"
	else
		do_clean_install="false"
	fi

	found_koreader_package="false"
	# Try to find a koreader package... Behavior undefined if there are multiple packages...
	for file in /mnt/us/koreader-kindle-*.zip ; do
		if [ -f "${file}" ] ; then
			found_koreader_package="${file}"
		fi
	done

	if [ "${found_koreader_package}" == "false" ] ; then
		# Go away
		logmsg "No KOReader package found"
	else
		# Do we want to do a clean install?
		if [ "${do_clean_install}" == "true" ] ; then
			logmsg "Removing current KOReader directory . . ."
			rm -rf /mnt/us/koreader
			logmsg "Uninstall finished."
		fi

		# Get the version of the package...
		koreader_pkg_ver="${found_koreader_package%.*}"
		koreader_pkg_ver="${koreader_pkg_ver#*-v}"
		# Install it!
		logmsg "Updating to KOReader ${koreader_pkg_ver} . . ."
		unzip -q -o "${found_koreader_package}" -d "/mnt/us"
		if [ $? -eq 0 ] ; then
			logmsg "Finished updating KOReader ${koreader_pkg_ver} :)"
		else
			logmsg "Failed to update to KOReader ${koreader_pkg_ver} :("
		fi
	fi
}

# Clean install of koreader
install_koreader()
{
	# Let update_koreader do the job for us ;p.
	update_koreader "clean"
}

# Handle cre's settings...
set_cre_prop()
{
	# We need at least two args
	if [ $# -lt 2 ] ; then
		logmsg "not enough arg passed to set_cre_prop"
		return
	fi

	cre_prop_key="${1}"
	cre_prop_value="${2}"

	cre_config="/mnt/us/koreader/data/cr3.ini"

	# Check that the config exists...
	if [ -f "${cre_config}" ] ; then
		# dos2unix
		sed -e "s/$(echo -ne '\r')$//g" -i "${cre_config}"

		# And finally set the prop
		sed -re "s/^(${cre_prop_key})(=)(.*?)$/\1\2${cre_prop_value}/" -i "${cre_config}"
		if [ $? -eq 0 ] ; then
			logmsg "Set ${cre_prop_key} to ${cre_prop_value}"
		else
			logmsg "Failed to set ${cre_prop_key}"
		fi
	else
		logmsg "No CRe config, launch CRe once first"
	fi
}

# Handle CRe's font.hinting.mode
cre_autohint()
{
	set_cre_prop "font.hinting.mode" "2"
}
cre_bci()
{
	set_cre_prop "font.hinting.mode" "1"
}
cre_nohinting()
{
	set_cre_prop "font.hinting.mode" "0"
}

# Handle CRe's font.kerning.enabled
cre_kerning()
{
	set_cre_prop "font.kerning.enabled" "1"
}
cre_nokerning()
{
	set_cre_prop "font.kerning.enabled" "0"
}


## Main
case "${1}" in
	"update_koreader" )
		${1}
	;;
	"install_koreader" )
		${1}
	;;
	"cre_autohint" )
		${1}
	;;
	"cre_bci" )
		${1}
	;;
	"cre_nohinting" )
		${1}
	;;
	"cre_kerning" )
		${1}
	;;
	"cre_nokerning" )
		${1}
	;;
	* )
		logmsg "invalid action (${1})"
	;;
esac
