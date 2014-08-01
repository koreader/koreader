#!/bin/sh
# NOTE: KatePart is being stupid, probably because of the file extension. Get me a decent syntax HL anyway.
#kate: syntax bash;

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
	"24" | "1B" | "1D" | "1F" | "1C" | "20" | "D4" | "5A" | "D5" | "D6" | "D7" | "D8" | "F2" | "17" | "60" | "F4" | "F9" | "62" | "61" | "5F" )
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
