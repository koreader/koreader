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
    for file in /mnt/us/koreader-kindle*.tar.xz /mnt/us/koreader-kindle*.targz /mnt/us/koreader-kindle*.zip; do
        if [ -f "${file}" ]; then
            found_koreader_package="${file}"
            case "${file}" in
                *.tar.xz) koreader_pkg_type='txz' ;;
                *.targz) koreader_pkg_type='tgz' ;;
                *.zip) koreader_pkg_type='zip' ;;
            esac
            break
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
        if case "${koreader_pkg_type}" in
            txz) tar -C '/mnt/us' -xJf "${found_koreader_package}" ;;
            tgz) tar -C '/mnt/us' -xzf "${found_koreader_package}" ;;
            zip) unzip -q -o "${found_koreader_package}" -d '/mnt/us' ;;
        esac then
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

start_ssh() {
    iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -p tcp --sport 2222 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    (cd /mnt/us/koreader && ./dropbear -E -R -p 2222 -P /tmp/dropbear_koreader.pid)
}

stop_ssh() {
    pid="$(cat /tmp/dropbear_koreader.pid)"
    for spec in TERM:20 KILL:10; do
        signal=${spec%:*}
        tries=${spec#*:}
        for n in $(seq "${tries}"); do
            if [ -z "${pid}" ] || ! [ -d "/proc/${pid}" ]; then
                break
            fi
            if [ "${n}" = 1 ]; then
                kill -"${signal}" "${pid}"
            fi
            sleep 0.1
        done
    done
    rm /tmp/dropbear_koreader.pid
    iptables -D INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
    iptables -D OUTPUT -p tcp --sport 2222 -m conntrack --ctstate ESTABLISHED -j ACCEPT
}

## Main
case "${1}" in
    "update_koreader")
        ${1}
        ;;
    "install_koreader")
        ${1}
        ;;
    start_ssh | stop_ssh)
        ${1}
        ;;
    *)
        logmsg "invalid action (${1})"
        ;;
esac
