#!/bin/sh
#
# KUAL KOReader actions helper script
#
##

# KOReader's working directory
KOREADER_DIR="/mnt/us/koreader"

# Load our helper functions...
if [ -f "${KOREADER_DIR}/libkoreader.inc" ] ; then
	source "${KOREADER_DIR}/libkoreader.inc"
else
	echo "Can't source helper functions, aborting!"
	exit 1
fi

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
			logmsg "Update to v${koreader_pkg_ver} successful :)"
			# Cleanup behind us...
			rm -f "${found_koreader_package}"
		else
			logmsg "Failed to update to v${koreader_pkg_ver} :("
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
