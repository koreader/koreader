#!/bin/sh

## A bit of helper functions...
# Check which type of init system we're running on
if [ -d /etc/upstart ] ; then
	export INIT_TYPE="upstart"
	# We'll need that for logging
	# shellcheck disable=SC1091
	[ -f /etc/upstart/functions ] && . /etc/upstart/functions
else
	export INIT_TYPE="sysv"
	# We'll need that for logging
	# shellcheck disable=SC1091
	[ -f /etc/rc.d/functions ] && . /etc/rc.d/functions
fi

# We need to get the proper constants for our model...
kmodel="$(cut -c3-4 /proc/usid)"
case "${kmodel}" in
	"13" | "54" | "2A" | "4F" | "52" | "53" )
		# Voyage...
		SCREEN_X_RES=1088	# NOTE: Yes, 1088, not 1072 or 1080...
		SCREEN_Y_RES=1448
		EIPS_X_RES=16
		EIPS_Y_RES=24		# Manually mesured, should be accurate.
	;;
	"24" | "1B" | "1D" | "1F" | "1C" | "20" | "D4" | "5A" | "D5" | "D6" | "D7" | "D8" | "F2" | "17" | "60" | "F4" | "F9" | "62" | "61" | "5F" )
		# PaperWhite...
		SCREEN_X_RES=768	# NOTE: Yes, 768, not 758...
		SCREEN_Y_RES=1024
		EIPS_X_RES=16
		EIPS_Y_RES=24		# Manually mesured, should be accurate.
	;;
	"C6" | "DD" )
		# KT2...
		SCREEN_X_RES=608
		SCREEN_Y_RES=800
		EIPS_X_RES=16
		EIPS_Y_RES=24
	;;
	"0F" | "11" | "10" | "12" )
		# Touch
		SCREEN_X_RES=600	# _v_width @ upstart/functions
		SCREEN_Y_RES=800	# _v_height @ upstart/functions
		EIPS_X_RES=12		# from f_puts @ upstart/functions
		EIPS_Y_RES=20		# from f_puts @ upstart/functions
	;;
	* )
		# Handle legacy devices...
		if [ -f "/etc/rc.d/functions" ] && grep "EIPS" "/etc/rc.d/functions" > /dev/null 2>&1 ; then
			# Already done...
			#. /etc/rc.d/functions
			echo "foo" >/dev/null
		else
			# Try the new device ID scheme...
			kmodel="$(cut -c4-6 /proc/usid)"
			case "${kmodel}" in
				"0G1" | "0G2" | "0G4" | "0G5" | "0G6" | "0G7" | "0KB" | "0KC" | "0KD" | "0KE" | "0KF" | "0KG" )
					# PW3... NOTE: Hopefully matches the KV...
					SCREEN_X_RES=1088
					SCREEN_Y_RES=1448
					EIPS_X_RES=16
					EIPS_Y_RES=24
				;;
				"0GC" | "0GD" | "0GP" | "0GQ" | "0GR" | "0GS" )
					# Oasis... NOTE: Hopefully matches the KV...
					SCREEN_X_RES=1088
					SCREEN_Y_RES=1448
					EIPS_X_RES=16
					EIPS_Y_RES=24
				;;
				"0DT" | "0K9" | "0KA" )
					# KT3... NOTE: Hopefully matches the KT2...
					SCREEN_X_RES=608
					SCREEN_Y_RES=800
					EIPS_X_RES=16
					EIPS_Y_RES=24
				;;
				* )
					# Fallback... We shouldn't ever hit that.
					SCREEN_X_RES=600
					SCREEN_Y_RES=800
					EIPS_X_RES=12
					EIPS_Y_RES=20
				;;
			esac
		fi
	;;
esac
# And now we can do the maths ;)
EIPS_MAXCHARS="$((SCREEN_X_RES / EIPS_X_RES))"
EIPS_MAXLINES="$((SCREEN_Y_RES / EIPS_Y_RES))"

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
	kh_padlen="$(((EIPS_MAXCHARS - kh_eips_strlen) / 2))"

	# Left padding...
	while [ ${#kh_eips_string} -lt $((kh_eips_strlen + kh_padlen)) ] ; do
		kh_eips_string=" ${kh_eips_string}"
	done

	# Right padding (crop to the edge of the screen)
	while [ ${#kh_eips_string} -lt ${EIPS_MAXCHARS} ] ; do
		kh_eips_string="${kh_eips_string} "
	done

	# Sleep a tiny bit to workaround the logic in the 'new' (K4+) eInk controllers that tries to bundle updates,
	# otherwise it may drop part of our messages because of other screen updates from KUAL...
	# Unless we really don't want to sleep, for special cases...
	if [ ! -n "${EIPS_NO_SLEEP}" ] ; then
		usleep 150000	# 150ms
	fi

	# And finally, show our formatted message centered on the bottom of the screen (NOTE: Redirect to /dev/null to kill unavailable character & pixel not in range warning messages)
	eips 0 $((EIPS_MAXLINES - 2 - kh_eips_y_shift_up)) "${kh_eips_string}" >/dev/null
}
