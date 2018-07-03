#!/bin/sh
export LC_ALL="en_US.UTF-8"

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
[ -e "${PROC_KEYPAD}" ] && echo unlock >"${PROC_KEYPAD}"
[ -e "${PROC_FIVEWAY}" ] && echo unlock >"${PROC_FIVEWAY}"

# KOReader's working directory
KOREADER_DIR="/mnt/us/koreader"

# Load our helper functions...
if [ -f "${KOREADER_DIR}/libkohelper.sh" ]; then
    # shellcheck source=/dev/null
    . "${KOREADER_DIR}/libkohelper.sh"
else
    echo "Can't source helper functions, aborting!"
    exit 1
fi

# Handle logging...
logmsg() {
    # Use the right tools for the platform
    if [ "${INIT_TYPE}" = "sysv" ]; then
        msg "koreader: ${1}" "I"
    elif [ "${INIT_TYPE}" = "upstart" ]; then
        f_log I koreader wrapper "" "${1}"
    fi

    # And throw that on stdout too, for the DIY crowd ;)
    echo "${1}"
}

# Go away if we're on FW 5.0, it's not supported
if [ "${INIT_TYPE}" = "upstart" ]; then
    if grep '^Kindle 5\.0' /etc/prettyversion.txt >/dev/null 2>&1; then
        logmsg "FW 5.0 is not supported. Update to 5.1!"
        # And... scene!
        exit 0
    fi
fi

# Keep track of what we do with pillow...
export AWESOME_STOPPED="no"
export VOLUMD_STOPPED="no"
PILLOW_HARD_DISABLED="no"
PILLOW_SOFT_DISABLED="no"
PASSCODE_DISABLED="no"

# Keep track of if we were started through KUAL
FROM_KUAL="no"

# By default, don't stop the framework.
if [ "$1" = "--framework_stop" ]; then
    shift 1
    STOP_FRAMEWORK="yes"
    NO_SLEEP="no"
elif [ "$1" = "--asap" ]; then
    # Start as soon as possible, without sleeping to workaround UI quirks
    shift 1
    NO_SLEEP="yes"
    STOP_FRAMEWORK="no"
    # Don't sleep during eips calls either...
    export EIPS_NO_SLEEP="true"
else
    STOP_FRAMEWORK="no"
    NO_SLEEP="no"
fi

# Detect if we were started by KUAL by checking our nice value...
if [ "$(nice)" = "5" ]; then
    FROM_KUAL="yes"
    if [ "${NO_SLEEP}" = "no" ]; then
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
cd "${KOREADER_DIR}" || exit

# Handle pending OTA update
ko_update_check() {
    local NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    local INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        logmsg "Updating koreader . . ."
        # Look for our own GNU tar build to do a fancy progress tracking...
        local GNUTAR_BIN="${KOREADER_DIR}/tar"
        local fail
        if [ -x "${GNUTAR_BIN}" ]; then
            # Let our checkpoint script handle the detailed visual feedback...
            eips_print_bottom_centered "Updating KOReader" 3
            # shellcheck disable=SC2016
            ${GNUTAR_BIN} -C "/mnt/us" --no-same-owner --no-same-permissions --checkpoint=200 --checkpoint-action=exec='./kotar_cpoint $TAR_CHECKPOINT' -xf "${NEWUPDATE}"
            fail=$?
        else
            # Fall back to busybox tar
            eips_print_bottom_centered "Updating KOReader . . ." 3
            tar -C "/mnt/us" -xf "${NEWUPDATE}"
            fail=$?
        fi
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            logmsg "Update successful :)"
            eips_print_bottom_centered "Update successful :)" 2
            eips_print_bottom_centered "KOReader will start momentarily . . ." 1
        else
            # Huh ho...
            logmsg "Update failed :("
            eips_print_bottom_centered "Update failed :(" 2
            eips_print_bottom_centered "KOReader may fail to function properly" 1
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
    fi
}
# NOTE: Keep doing an initial update check, in addition to one during the restart loop...
ko_update_check

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directories (In order: stock, stock custom (both legacy & 5.9.6+), stock extra, font hack)
export EXT_FONT_DIR="/usr/java/lib/fonts;/mnt/us/fonts;/var/local/font/mnt;/mnt/us/linkfonts/fonts"

# Only setup IPTables on devices where it makes sense to do so (FW 5.x & K4)
if [ "${INIT_TYPE}" = "upstart" ] || [ "$(uname -r)" = "2.6.31-rt11-lab126" ]; then
    logmsg "Setting up IPTables rules . . ."
    # accept input ports for zsync plugin
    iptables -A INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
    iptables -A INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT
    # accept input ports for calibre companion
    iptables -A INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT
fi

# check if we need to disable the system passcode, because it messes with us in fun and interesting (and, more to the point, intractable) ways...
# NOTE: The most egregious one being that it inhibits the outOfScreenSaver event on wakeup until the passcode is validated, which we can't do, since we capture all input...
if [ -f "/var/local/system/userpasswdenabled" ]; then
    logmsg "Disabling system passcode . . ."
    rm -f "/var/local/system/userpasswdenabled"
    PASSCODE_DISABLED="yes"
fi

# check if we are supposed to shut down the Amazon framework
if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Stopping the framework . . ."
    # Upstart or SysV?
    if [ "${INIT_TYPE}" = "sysv" ]; then
        /etc/init.d/framework stop
    else
        # The framework job sends a SIGTERM on stop, trap it so we don't get killed if we were launched by KUAL
        trap "" TERM
        stop lab126_gui
        # NOTE: Let the framework teardown finish, so we don't start before the black screen...
        usleep 1250000
        # And remove the trap like a ninja now!
        trap - TERM
    fi
fi

# check if kpvbooklet was launched more than once, if not we will disable pillow
# there's no pillow if we stopped the framework, and it's only there on systems with upstart anyway
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "upstart" ]; then
    count="$(lipc-get-prop -eiq com.github.koreader.kpvbooklet.timer count)"
    if [ "$count" = "" ] || [ "$count" = "0" ]; then
        # NOTE: Dump the fb so we can restore something useful on exit...
        cat /dev/fb0 >/var/tmp/koreader-fb.dump
        # NOTE: We want to disable the status bar (at the very least). Unfortunately, the soft hide/unhide method doesn't work properly anymore since FW 5.6.5...
        # shellcheck disable=SC2046
        if [ "$(printf "%.3s" $(grep '^Kindle 5' /etc/prettyversion.txt 2>&1 | sed -n -r 's/^(Kindle)([[:blank:]]*)([[:digit:].]*)(.*?)$/\3/p' | tr -d '.'))" -ge "565" ]; then
            PILLOW_HARD_DISABLED="yes"
            # FIXME: So we resort to killing pillow completely on FW >= 5.6.5...
            logmsg "Disabling pillow . . ."
            lipc-set-prop com.lab126.pillow disableEnablePillow disable
            # NOTE: And, oh, joy, on FW >= 5.7.2, this is not enough to prevent the clock from refreshing, so, take the bull by the horns, and SIGSTOP the WM while we run...
            # shellcheck disable=SC2046
            if [ "$(printf "%.3s" $(grep '^Kindle 5' /etc/prettyversion.txt 2>&1 | sed -n -r 's/^(Kindle)([[:blank:]]*)([[:digit:].]*)(.*?)$/\3/p' | tr -d '.'))" -ge "572" ]; then
                logmsg "Stopping awesome . . ."
                killall -stop awesome
                AWESOME_STOPPED="yes"
            fi
        else
            logmsg "Hiding the status bar . . ."
            # NOTE: One more great find from eureka (http://www.mobileread.com/forums/showpost.php?p=2454141&postcount=34)
            lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.hideMe();"}'
            PILLOW_SOFT_DISABLED="yes"
        fi
        # NOTE: We don't need to sleep at all if we've already SIGSTOPped awesome ;)
        if [ "${NO_SLEEP}" = "no" ] && [ "${AWESOME_STOPPED}" = "no" ]; then
            # NOTE: Leave the framework time to refresh the screen, so we don't start before it has finished redrawing after collapsing the title bar
            usleep 250000
            # NOTE: If we were started from KUAL, we risk getting a list item to popup right over us, so, wait some more...
            # The culprit appears to be a I WindowManager:flashTimeoutExpired:window=Root 0 0 600x30
            if [ "${FROM_KUAL}" = "yes" ]; then
                logmsg "Playing possum to wait for the window manager . . ."
                usleep 2500000
            fi
        fi
    fi
fi

# stop cvm (sysv & framework up only)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "sysv" ]; then
    logmsg "Stopping cvm . . ."
    killall -stop cvm
fi

# SIGSTOP volumd, to inhibit USBMS (sysv & upstart)
if [ -e "/etc/init.d/volumd" ] || [ -e "/etc/upstart/volumd.conf" ]; then
    logmsg "Stopping volumd . . ."
    killall -stop volumd
    VOLUMD_STOPPED="yes"
fi

# finally call reader
logmsg "Starting KOReader . . ."
# That's not necessary when using KPVBooklet ;).
if [ "${FROM_KUAL}" = "yes" ]; then
    eips_print_bottom_centered "Starting KOReader . . ." 1
fi

# we keep at most 500KB worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

RETURN_VALUE=85
while [ "${RETURN_VALUE}" -eq 85 ]; do
    # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
    ko_update_check

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?
done

# clean up our own process tree in case the reader crashed (if needed, to avoid flooding KUAL's log)
if pidof reader.lua >/dev/null 2>&1; then
    logmsg "Sending a SIGTERM to stray KOreader processes . . ."
    killall -TERM reader.lua
fi

# Resume volumd, if need be
if [ "${VOLUMD_STOPPED}" = "yes" ]; then
    logmsg "Resuming volumd . . ."
    killall -cont volumd
fi

# Resume cvm (only if we stopped it)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "sysv" ]; then
    logmsg "Resuming cvm . . ."
    killall -cont cvm
    # We need to handle the screen refresh ourselves, frontend/device/kindle/device.lua's Kindle3.exit is called before we resume cvm ;).
    echo 'send 139' >/proc/keypad
    echo 'send 139' >/proc/keypad
fi

# Restart framework (if need be)
if [ "${STOP_FRAMEWORK}" = "yes" ]; then
    logmsg "Restarting framework . . ."
    if [ "${INIT_TYPE}" = "sysv" ]; then
        cd / && env -u LD_LIBRARY_PATH /etc/init.d/framework start
    else
        cd / && env -u LD_LIBRARY_PATH start lab126_gui
    fi
fi

# Display chrome bar if need be (upstart & framework up only)
if [ "${STOP_FRAMEWORK}" = "no" ] && [ "${INIT_TYPE}" = "upstart" ]; then
    # Depending on the FW version, we may have handled things in a few different manners...
    if [ "${AWESOME_STOPPED}" = "yes" ]; then
        logmsg "Resuming awesome . . ."
        killall -cont awesome
    fi
    if [ "${PILLOW_HARD_DISABLED}" = "yes" ]; then
        logmsg "Enabling pillow . . ."
        lipc-set-prop com.lab126.pillow disableEnablePillow enable
        # NOTE: Try to leave the user with a slightly more useful FB content than our own last screen...
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
        # NOTE: In case we ever need an extra full flash refresh...
        #eips -s w=${SCREEN_X_RES},h=${SCREEN_Y_RES} -f
    fi
    if [ "${PILLOW_SOFT_DISABLED}" = "yes" ]; then
        logmsg "Restoring the status bar . . ."
        # NOTE: Try to leave the user with a slightly more useful FB content than our own last screen...
        cat /var/tmp/koreader-fb.dump >/dev/fb0
        rm -f /var/tmp/koreader-fb.dump
        lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId": "default_status_bar", "function": "nativeBridge.showMe();"}'
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    fi
fi

if [ "${INIT_TYPE}" = "upstart" ] || [ "$(uname -r)" = "2.6.31-rt11-lab126" ]; then
    logmsg "Restoring IPTables rules . . ."
    # restore firewall rules
    iptables -D INPUT -i wlan0 -p udp --dport 8134 -j ACCEPT
    iptables -D INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
    iptables -D INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT
fi

if [ "${PASSCODE_DISABLED}" = "yes" ]; then
    logmsg "Restoring system passcode . . ."
    touch "/var/local/system/userpasswdenabled"
fi

exit ${RETURN_VALUE}
