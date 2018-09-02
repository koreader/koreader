#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# Attempt to switch to a sensible CPUFreq governor when that's not already the case...
current_cpufreq_gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
# NOTE: We're being fairly conservative here, because what's used and what's available varies depending on HW...
if [ "${current_cpufreq_gov}" != "ondemand" ] && [ "${current_cpufreq_gov}" != "interactive" ]; then
    # NOTE: Go with ondemand, because it's likely to be the lowest common denominator.
    #       Plus, interactive is hard to tune right, and only really interesting when it's a recent version,
    #       which I somehow doubt is the case anywhere here...
    if grep -q ondemand /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; then
        ORIG_CPUFREQ_GOV="${current_cpufreq_gov}"
        echo "ondemand" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    fi
fi
# NOTE: That doesn't actually help us poor userspace plebs, but, short of switching to performance,
#       I don't really have a golden bullet here... (conservative's rubberbanding is terrible, so that's a hard pass).
#       All I can say is that userspace is a terrible idea and behaves *very* strangely (c.f., #4114).

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        ./fbink -q -y -7 -pmh "Updating KOReader"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        BLOCKS="$(( $(stat -c %b "${NEWUPDATE}") / 20 ))"
        export CPOINTS="$(( ${BLOCKS} / 100 ))"
        # shellcheck disable=SC2016
        ./tar xf "${NEWUPDATE}" --strip-components=1 --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='./fbink -q -y -6 -P $(($TAR_CHECKPOINT/$CPOINTS))'
        fail=$?
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            ./fbink -q -y -6 -pm "Update successful :)"
            ./fbink -q -y -5 -pm "KOReader will start momentarily . . ."
        else
            # Huh ho...
            ./fbink -q -y -6 -pmh "Update failed :("
            ./fbink -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
        unset BLOCKS CPOINTS
    fi
}
# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check
# If an update happened, and was successful, reexec
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # By now, we know we're in the right directory, and our script name is pretty much set in stone, so we can forgo using $0
    exec ./koreader.sh "${@}"
fi

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directory
export EXT_FONT_DIR="/mnt/onboard/fonts"

# fast and dirty way of check if we are called from nickel
# through fmon/KFMon, or from another launcher (KSM or advboot)
# Do not delete this line because KSM detects newer versions of KOReader by the presence of the phrase 'from_nickel'.
export FROM_NICKEL="false"
if pkill -0 nickel; then
    FROM_NICKEL="true"
fi

if [ "${FROM_NICKEL}" = "true" ]; then
    # Detect if we were started from KFMon
    FROM_KFMON="false"
    if pkill -0 kfmon; then
        # That's a start, now check if KFMon truly is our parent...
        if [ "$(pidof kfmon)" -eq "${PPID}" ]; then
            FROM_KFMON="true"
        fi
    fi

    # Siphon a few things from nickel's env (namely, stuff exported by rcS *after* on-animator.sh has been launched)...
    eval "$(xargs -n 1 -0 <"/proc/$(pidof nickel)/environ" | grep -e DBUS_SESSION_BUS_ADDRESS -e NICKEL_HOME -e WIFI_MODULE -e LANG -e WIFI_MODULE_PATH -e INTERFACE 2>/dev/null)"
    export DBUS_SESSION_BUS_ADDRESS NICKEL_HOME WIFI_MODULE LANG WIFI_MODULE_PATH INTERFACE

    # flush disks, might help avoid trashing nickel's DB...
    sync
    # stop kobo software because it's running
    # NOTE: We don't need to kill KFMon, it's smart enough not to allow running anything else while we're up
    killall nickel hindenburg sickel fickel fmon 2>/dev/null
fi

# fallback for old fmon, KFMon and advboot users (-> if no args were passed to the script, start the FM)
if [ "$#" -eq 0 ]; then
    args="/mnt/onboard"
else
    args="$*"
fi

# check whether PLATFORM & PRODUCT have a value assigned by rcS
if [ ! -n "${PRODUCT}" ]; then
    PRODUCT="$(/bin/kobo_config.sh 2>/dev/null)"
    export PRODUCT
fi

# PLATFORM is used in koreader for the path to the WiFi drivers (as well as when restarting nickel)
if [ ! -n "${PLATFORM}" ]; then
    PLATFORM="freescale"
    if dd if="/dev/mmcblk0" bs=512 skip=1024 count=1 | grep -q "HW CONFIG"; then
        CPU="$(ntx_hwconfig -s -p /dev/mmcblk0 CPU 2>/dev/null)"
        PLATFORM="${CPU}-ntx"
    fi

    if [ "${PLATFORM}" != "freescale" ] && [ ! -e "/etc/u-boot/${PLATFORM}/u-boot.mmc" ]; then
        PLATFORM="ntx508"
    fi
    export PLATFORM
fi

# Make sure we have a sane-ish INTERFACE env var set...
if [ ! -n "${INTERFACE}" ]; then
    # That's what we used to hardcode anyway
    INTERFACE="eth0"
    export INTERFACE
fi
# end of value check of PLATFORM

# Remount the SD card RW if it's inserted and currently RO
if awk '$4~/(^|,)ro($|,)/' /proc/mounts | grep ' /mnt/sd '; then
    mount -o remount,rw /mnt/sd
fi

# we keep at most 500KB worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

RETURN_VALUE=85
while [ $RETURN_VALUE -eq 85 ]; do
    # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
    ko_update_check

    ./reader.lua "${args}" >>crash.log 2>&1
    RETURN_VALUE=$?
done

# Restore original CPUFreq governor if need be...
if [ -n "${ORIG_CPUFREQ_GOV}" ]; then
    echo "${ORIG_CPUFREQ_GOV}" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
fi

if [ "${FROM_NICKEL}" = "true" ]; then
    if [ "${FROM_KFMON}" != "true" ]; then
        # start kobo software because it was running before koreader
        ./nickel.sh &
    else
        if grep -q "reboot_on_exit=false" "/mnt/onboard/.adds/kfmon/config/koreader.ini" 2>/dev/null; then
            # KFMon asked us to restart nickel on exit (default since KFMon 0.9.5)
            ./nickel.sh &
        else
            # KFMon asked us to restart the device on exit
            /sbin/reboot
        fi
    fi
else
    # if we were called from advboot then we must reboot to go to the menu
    # NOTE: This is actually achieved by checking if KSM or a KSM-related script is running:
    #       This might lead to false-positives if you use neither KSM nor advboot to launch KOReader *without nickel running*.
    if ! pgrep -f kbmenu >/dev/null 2>&1; then
        /sbin/reboot
    fi
fi

exit $RETURN_VALUE
