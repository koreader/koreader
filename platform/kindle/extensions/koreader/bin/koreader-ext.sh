#!/bin/sh
#
# KUAL KOReader actions helper script
#
##

# Load our helper functions...
if [ -f "./bin/libkohelper.sh" ]; then
    # shellcheck source=/dev/null
    . "./bin/libkohelper.sh"
else
    echo "Can't source helper functions, aborting!"
    exit 1
fi

## Handle logging...
logmsg() {
    # Use the right tools for the platform
    if [ "${INIT_TYPE}" = "sysv" ]; then
        msg "koreader: ${1}" "I"
    elif [ "${INIT_TYPE}" = "upstart" ]; then
        f_log I koreader kual "" "${1}"
    fi

    # And handle user visual feedback via FBInk/eips...
    eips_print_bottom_centered "${1}" 1
}

## And now the actual useful stuff!

# Update koreader
update_koreader() {
    # Check if we were called by install_koreader...
    if [ "${1}" = "clean" ]; then
        do_clean_install="true"
    else
        do_clean_install="false"
    fi

    found_koreader_package="false"
    # Try to find a koreader package... Behavior undefined if there are multiple packages...
    for file in /mnt/us/koreader-kindle*.targz; do
        if [ -f "${file}" ]; then
            found_koreader_package="${file}"
            koreader_pkg_type="tgz"
        fi
    done
    for file in /mnt/us/koreader-kindle*.zip; do
        if [ -f "${file}" ]; then
            found_koreader_package="${file}"
            koreader_pkg_type="zip"
        fi
    done

    if [ "${found_koreader_package}" = "false" ]; then
        # Go away
        logmsg "No KOReader package found"
    else
        # Do we want to do a clean install?
        if [ "${do_clean_install}" = "true" ]; then
            logmsg "Removing current KOReader directory . . ."
            rm -rf /mnt/us/koreader
            logmsg "Uninstall finished."
        fi

        # Get the version of the package...
        koreader_pkg_ver="${found_koreader_package%.*}"
        koreader_pkg_ver="${koreader_pkg_ver#*-v}"
        # Strip the date purely because of screen space constraints
        koreader_pkg_ver="${koreader_pkg_ver%_*}"
        # Install it!
        logmsg "Updating to KOReader ${koreader_pkg_ver} . . ."
        if [ "${koreader_pkg_type}" = "tgz" ]; then
            tar -C "/mnt/us" -xzf "${found_koreader_package}"
            fail=$?
        else
            unzip -q -o "${found_koreader_package}" -d "/mnt/us"
            fail=$?
        fi
        if [ ${fail} -eq 0 ]; then
            # Cleanup behind us...
            rm -f "${found_koreader_package}"
            # Flush to disk first...
            sync
            logmsg "Update to v${koreader_pkg_ver} successful :)"
        else
            # Flush to disk first anyway...
            sync
            logmsg "Failed to update to v${koreader_pkg_ver} :("
        fi
    fi
}

# Clean install of koreader
install_koreader() {
    # Let update_koreader do the job for us ;p.
    update_koreader "clean"
}

## Main
case "${1}" in
    "update_koreader")
        ${1}
        ;;
    "install_koreader")
        ${1}
        ;;
    *)
        logmsg "invalid action (${1})"
        ;;
esac
