#!/bin/sh
export LC_ALL="en_US.UTF-8"

# Compute our working directory in an extremely defensive manner
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
# NOTE: We need to remember the *actual* KOREADER_DIR, not the relocalized version in /tmp...
export KOREADER_DIR="${KOREADER_DIR:-${SCRIPT_DIR}}"

# We rely on starting from our working directory, and it needs to be set, sane and absolute.
cd "${KOREADER_DIR:-/dev/null}" || exit

# To make USBMS behave, relocalize ourselves outside of onboard
if [ "${SCRIPT_DIR}" != "/tmp" ]; then
    cp -pf "${0}" "/tmp/koreader.sh"
    chmod 777 "/tmp/koreader.sh"
    exec "/tmp/koreader.sh" "$@"
fi

# Attempt to switch to a sensible CPUFreq governor when that's not already the case...
IFS= read -r current_cpufreq_gov <"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
# NOTE: What's available depends on the HW, so, we'll have to take it step by step...
#       Roughly follow Nickel's behavior (which prefers interactive), and prefer interactive, then ondemand, and finally conservative/dvfs.
if [ "${current_cpufreq_gov}" != "interactive" ]; then
    if grep -q "interactive" "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; then
        ORIG_CPUFREQ_GOV="${current_cpufreq_gov}"
        echo "interactive" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    elif [ "${current_cpufreq_gov}" != "ondemand" ]; then
        if grep -q "ondemand" "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; then
            # NOTE: This should never really happen: every kernel that supports ondemand already supports interactive ;).
            #       They were both introduced on Mk. 6
            ORIG_CPUFREQ_GOV="${current_cpufreq_gov}"
            echo "ondemand" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        elif [ -e "/sys/devices/platform/mxc_dvfs_core.0/enable" ]; then
            # The rest of this block assumes userspace is available...
            if grep -q "userspace" "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; then
                ORIG_CPUFREQ_GOV="${current_cpufreq_gov}"
                export CPUFREQ_DVFS="true"

                # If we can use conservative, do so, but we'll tweak it a bit to make it somewhat useful given our load patterns...
                # We unfortunately don't have any better choices on those kernels,
                # the only other governors available are powersave & performance (c.f., #4114)...
                if grep -q "conservative" "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"; then
                    export CPUFREQ_CONSERVATIVE="true"
                    echo "conservative" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    # NOTE: The knobs survive a governor switch, which is why we do this now ;).
                    echo "2" >"/sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor"
                    echo "50" >"/sys/devices/system/cpu/cpufreq/conservative/freq_step"
                    echo "11" >"/sys/devices/system/cpu/cpufreq/conservative/down_threshold"
                    echo "12" >"/sys/devices/system/cpu/cpufreq/conservative/up_threshold"
                    # NOTE: The default sampling_rate is a bit high for my tastes,
                    #       but it unfortunately defaults to its lowest possible setting...
                fi

                # NOTE: Now, here comes the freaky stuff... On a H2O, DVFS is only enabled when Wi-Fi is *on*.
                #       When it's off, DVFS is off, which pegs the CPU @ max clock given that DVFS means the userspace governor.
                #       The flip may originally have been switched by the sdio_wifi_pwr module itself,
                #       via ntx_wifi_power_ctrl @ arch/arm/mach-mx5/mx50_ntx_io.c (which is also the CM_WIFI_CTRL (208) ntx_io ioctl),
                #       but the code in the published H2O kernel sources actually does the reverse, and is commented out ;).
                #       It is now entirely handled by Nickel, right *before* loading/unloading that module.
                #       (There's also a bug(?) where that behavior is inverted for the *first* Wi-Fi session after a cold boot...)
                if grep -q "sdio_wifi_pwr" "/proc/modules"; then
                    # Wi-Fi is enabled, make sure DVFS is on
                    echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    echo "1" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
                else
                    # Wi-Fi is disabled, make sure DVFS is off
                    echo "0" >"/sys/devices/platform/mxc_dvfs_core.0/enable"

                    # Switch to conservative to avoid being stuck at max clock if we can...
                    if [ -n "${CPUFREQ_CONSERVATIVE}" ]; then
                        echo "conservative" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    else
                        # Otherwise, we'll be pegged at max clock...
                        echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                        # The kernel should already be taking care of that...
                        cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"
                    fi
                fi
            fi
        fi
    fi
fi

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        ./fbink -q -y -7 -pmh "Updating KOReader"
        # Setup the FBInk daemon
        export FBINK_NAMED_PIPE="/tmp/koreader.fbink"
        rm -f "${FBINK_NAMED_PIPE}"
        FBINK_PID="$(./fbink --daemon 1 %KOREADER% -q -y -6 -P 0)"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        BLOCKS="$((FILESIZE / 20))"
        export CPOINTS="$((BLOCKS / 100))"
        # shellcheck disable=SC2016
        ./tar xf "${NEWUPDATE}" --strip-components=1 --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='printf "%s" $((TAR_CHECKPOINT / CPOINTS)) > ${FBINK_NAMED_PIPE}'
        fail=$?
        kill -TERM "${FBINK_PID}"
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            ./fbink -q -y -6 -pm "Update successful :)"
            ./fbink -q -y -5 -pm "KOReader will start momentarily . . ."

            # Warn if the startup script has been updated...
            if [ "$(md5sum "/tmp/koreader.sh" | cut -f1 -d' ')" != "$(md5sum "${KOREADER_DIR}/koreader.sh" | cut -f1 -d' ')" ]; then
                ./fbink -q -pmMh "Update contains a startup script update!"
            fi
        else
            # Uh oh...
            ./fbink -q -y -6 -pmh "Update failed :("
            ./fbink -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate to prevent update loops
        unset CPOINTS FBINK_NAMED_PIPE
        unset BLOCKS FILESIZE FBINK_PID
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        sync
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

# Quick'n dirty way of checking if we were started while Nickel was running (e.g., KFMon),
# or from another launcher entirely, outside of Nickel (e.g., KSM).
VIA_NICKEL="false"
if pkill -0 nickel; then
    VIA_NICKEL="true"
fi
# NOTE: Do not delete this line because KSM detects newer versions of KOReader by the presence of the phrase 'from_nickel'.

if [ "${VIA_NICKEL}" = "true" ]; then
    # Detect if we were started from KFMon
    FROM_KFMON="false"
    if pkill -0 kfmon; then
        # That's a start, now check if KFMon truly is our parent...
        if [ "$(pidof -s kfmon)" -eq "${PPID}" ]; then
            FROM_KFMON="true"
        fi
    fi

    # Check if Nickel is our parent...
    FROM_NICKEL="false"
    if [ -n "${NICKEL_HOME}" ]; then
        FROM_NICKEL="true"
    fi

    # If we were spawned outside of Nickel, we'll need a few extra bits from its own env...
    if [ "${FROM_NICKEL}" = "false" ]; then
        # Siphon a few things from nickel's env (namely, stuff exported by rcS *after* on-animator.sh has been launched)...
        # shellcheck disable=SC2046
        export $(grep -s -E -e '^(DBUS_SESSION_BUS_ADDRESS|NICKEL_HOME|WIFI_MODULE|LANG|INTERFACE)=' "/proc/$(pidof -s nickel)/environ")
        # NOTE: Quoted variant, w/ the busybox RS quirk (c.f., https://unix.stackexchange.com/a/125146):
        #eval "$(awk -v 'RS="\0"' '/^(DBUS_SESSION_BUS_ADDRESS|NICKEL_HOME|WIFI_MODULE|LANG|INTERFACE)=/{gsub("\047", "\047\\\047\047"); print "export \047" $0 "\047"}' "/proc/$(pidof -s nickel)/environ")"
    fi

    # Flush disks, might help avoid trashing nickel's DB...
    sync
    # And we can now stop the full Kobo software stack
    # NOTE: We don't need to kill KFMon, it's smart enough not to allow running anything else while we're up
    # NOTE: We kill Nickel's master dhcpcd daemon on purpose,
    #       as we want to be able to use our own per-if processes w/ custom args later on.
    #       A SIGTERM does not break anything, it'll just prevent automatic lease renewal until the time
    #       KOReader actually sets the if up itself (i.e., it'll do)...
    killall -q -TERM nickel hindenburg sickel fickel adobehost foxitpdf iink dhcpcd-dbus dhcpcd fmon

    # Wait for Nickel to die... (oh, procps with killall -w, how I miss you...)
    kill_timeout=0
    while pkill -0 nickel; do
        # Stop waiting after 4s
        if [ ${kill_timeout} -ge 15 ]; then
            break
        fi
        usleep 250000
        kill_timeout=$((kill_timeout + 1))
    done
    # Remove Nickel's FIFO to avoid udev & udhcpc scripts hanging on open() on it...
    rm -f /tmp/nickel-hardware-status

    # We don't need to grab input devices (unless MiniClock is running, in which case that neatly inhibits it while we run).
    if [ ! -d "/tmp/MiniClock" ]; then
        export KO_DONT_GRAB_INPUT="true"
    fi
fi

# check whether PLATFORM & PRODUCT have a value assigned by rcS
if [ -z "${PRODUCT}" ]; then
    # shellcheck disable=SC2046
    export $(grep -s -e '^PRODUCT=' "/proc/$(pidof -s udevd)/environ")
fi

if [ -z "${PRODUCT}" ]; then
    PRODUCT="$(/bin/kobo_config.sh 2>/dev/null)"
    export PRODUCT
fi

# PLATFORM is used in koreader for the path to the Wi-Fi drivers (as well as when restarting nickel)
if [ -z "${PLATFORM}" ]; then
    # shellcheck disable=SC2046
    export $(grep -s -e '^PLATFORM=' "/proc/$(pidof -s udevd)/environ")
fi

if [ -z "${PLATFORM}" ]; then
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
if [ -z "${INTERFACE}" ]; then
    # That's what we used to hardcode anyway
    INTERFACE="eth0"
    export INTERFACE
fi

# We'll enforce UR in ko_do_fbdepth, so make sure further FBInk usage (USBMS)
# will also enforce UR... (Only actually meaningful on sunxi).
if [ "${PLATFORM}" = "b300-ntx" ]; then
    export FBINK_FORCE_ROTA=0
    # And we also cannot use batched updates for the crash screens, as buffers are private,
    # so each invocation essentially draws in a different buffer...
    FBINK_BATCH_FLAG=""
    # Same idea for backgroundless...
    FBINK_BGLESS_FLAG="-B GRAY9"
    # It also means we need explicit background padding in the OT codepath...
    FBINK_OT_PADDING=",padding=BOTH"

    # Make sure we poke the right input device
    KOBO_TS_INPUT="/dev/input/by-path/platform-0-0010-event"
else
    FBINK_BATCH_FLAG="-b"
    FBINK_BGLESS_FLAG="-O"
    FBINK_OT_PADDING=""
    KOBO_TS_INPUT="/dev/input/event1"
fi

# Make sure we only keep two cores online on the Elipsa.
# NOTE: That's a bit optimistic, we might actually need to tone that down to one,
#       and just toggle the second one on demand (e.g., PDF).
if [ "${PRODUCT}" = "europa" ]; then
    echo "1" >"/sys/devices/system/cpu/cpu1/online"
    echo "0" >"/sys/devices/system/cpu/cpu2/online"
    echo "0" >"/sys/devices/system/cpu/cpu3/online"
fi

# We'll want to ensure Portrait rotation to allow us to use faster blitting codepaths @ 8bpp,
# so remember the current one before fbdepth does its thing.
IFS= read -r ORIG_FB_ROTA <"/sys/class/graphics/fb0/rotate"
echo "Original fb rotation is set @ ${ORIG_FB_ROTA}" >>crash.log 2>&1

# In the same vein, swap to 8bpp,
# because 16bpp is the worst idea in the history of time, as RGB565 is generally a PITA without hardware blitting,
# and 32bpp usually gains us nothing except a performance hit (we're not Qt5 with its QPainter constraints).
# The reduced size & complexity should hopefully make things snappier,
# (and hopefully prevent the JIT from going crazy on high-density screens...).
# NOTE: Even though both pickel & Nickel appear to restore their preferred fb setup, we'll have to do it ourselves,
#       as they fail to flip the grayscale flag properly. Plus, we get to play nice with every launch method that way.
#       So, remember the current bitdepth, so we can restore it on exit.
IFS= read -r ORIG_FB_BPP <"/sys/class/graphics/fb0/bits_per_pixel"
echo "Original fb bitdepth is set @ ${ORIG_FB_BPP}bpp" >>crash.log 2>&1
# Sanity check...
case "${ORIG_FB_BPP}" in
    8) ;;
    16) ;;
    32) ;;
    *)
        # Uh oh? Don't do anything...
        unset ORIG_FB_BPP
        ;;
esac

# The actual swap is done in a function, because we can disable it in the Developer settings, and we want to honor it on restart.
ko_do_fbdepth() {
    # On sunxi, the fb state is meaningless, and the minimal disp fb doesn't actually support 8bpp anyway,
    # so just make sure we're set @ UR.
    if [ "${PLATFORM}" = "b300-ntx" ]; then
        echo "Making sure that rotation is set to Portrait" >>crash.log 2>&1
        ./fbdepth -d 32 -R UR >>crash.log 2>&1

        return
    fi

    # Check if the swap has been disabled...
    if grep -q '\["dev_startup_no_fbdepth"\] = true' 'settings.reader.lua' 2>/dev/null; then
        # Swap back to the original bitdepth (in case this was a restart)
        if [ -n "${ORIG_FB_BPP}" ]; then
            # Unless we're a Forma/Libra, don't even bother to swap rotation if the fb is @ 16bpp, because RGB565 is terrible anyways,
            # so there's no faster codepath to achieve, and running in Portrait @ 16bpp might actually be broken on some setups...
            if [ "${ORIG_FB_BPP}" -eq "16" ] && [ "${PRODUCT}" != "frost" ] && [ "${PRODUCT}" != "storm" ]; then
                echo "Making sure we're using the original fb bitdepth @ ${ORIG_FB_BPP}bpp & rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
                ./fbdepth -d "${ORIG_FB_BPP}" -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
            else
                echo "Making sure we're using the original fb bitdepth @ ${ORIG_FB_BPP}bpp, and that rotation is set to Portrait" >>crash.log 2>&1
                ./fbdepth -d "${ORIG_FB_BPP}" -R UR >>crash.log 2>&1
            fi
        fi
    else
        # Swap to 8bpp if things looke sane
        if [ -n "${ORIG_FB_BPP}" ]; then
            echo "Switching fb bitdepth to 8bpp & rotation to Portrait" >>crash.log 2>&1
            ./fbdepth -d 8 -R UR >>crash.log 2>&1
        fi
    fi
}

# Ensure we start with a valid nameserver in resolv.conf, otherwise we're stuck with broken name resolution (#6421, #6424).
# Fun fact: this wouldn't be necessary if Kobo were using a non-prehistoric glibc... (it was fixed in glibc 2.26).
ko_do_dns() {
    # If there aren't any servers listed, append CloudFlare's
    if ! grep -q '^nameserver' "/etc/resolv.conf"; then
        echo "# Added by KOReader because your setup is broken" >>"/etc/resolv.conf"
        echo "nameserver 1.1.1.1" >>"/etc/resolv.conf"
    fi
}

# Remount the SD card RW if it's inserted and currently RO
if awk '$4~/(^|,)ro($|,)/' /proc/mounts | grep ' /mnt/sd '; then
    mount -o remount,rw /mnt/sd
fi

# we keep at most 500KB worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# List of supported special return codes
KO_RC_RESTART=85
KO_RC_USBMS=86
KO_RC_HALT=88
# Because we *want* an initial fbdepth pass ;).
RETURN_VALUE=${KO_RC_RESTART}
while [ ${RETURN_VALUE} -ne 0 ]; do
    if [ ${RETURN_VALUE} -eq ${KO_RC_RESTART} ]; then
        # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
        ko_update_check
        # Do or double-check the fb depth switch, or restore original bitdepth if requested
        ko_do_fbdepth
        # Make sure we have a sane resolv.conf
        ko_do_dns
    fi

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    # Did we crash?
    if [ ${RETURN_VALUE} -ne 0 ] && [ ${RETURN_VALUE} -ne ${KO_RC_RESTART} ] && [ ${RETURN_VALUE} -ne ${KO_RC_USBMS} ] && [ ${RETURN_VALUE} -ne ${KO_RC_HALT} ]; then
        # Increment the crash counter
        CRASH_COUNT=$((CRASH_COUNT + 1))
        CRASH_TS=$(date +'%s')
        # Reset it to a first crash if it's been a while since our last crash...
        if [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ]; then
            CRASH_COUNT=1
        fi

        # Check if the user requested to always abort on crash
        if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
            ALWAYS_ABORT="true"
            # In which case, make sure we pause on *every* crash
            CRASH_COUNT=1
        else
            ALWAYS_ABORT="false"
        fi

        # Show a fancy bomb on screen
        viewWidth=600
        viewHeight=800
        FONTH=16
        eval "$(./fbink -e | tr ';' '\n' | grep -e viewWidth -e viewHeight -e FONTH | tr '\n' ';')"
        # Compute margins & sizes relative to the screen's resolution, so we end up with a similar layout, no matter the device.
        # Height @ ~56.7%, w/ a margin worth 1.5 lines
        bombHeight=$((viewHeight / 2 + viewHeight / 15))
        bombMargin=$((FONTH + FONTH / 2))
        # Start with a big gray screen of death, and our friendly old school crash icon ;)
        # U+1F4A3, the hard way, because we can't use \u or \U escape sequences...
        # shellcheck disable=SC2039,SC3003
        ./fbink -q ${FBINK_BATCH_FLAG} -c -B GRAY9 -m -t regular=./fonts/freefont/FreeSerif.ttf,px=${bombHeight},top=${bombMargin} -W GL16 -- $'\xf0\x9f\x92\xa3'
        # With a little notice at the top of the screen, on a big gray screen of death ;).
        ./fbink -q ${FBINK_BATCH_FLAG} ${FBINK_BGLESS_FLAG} -m -y 1 "Don't Panic! (Crash n°${CRASH_COUNT} -> ${RETURN_VALUE})" -W GL16
        if [ ${CRASH_COUNT} -eq 1 ]; then
            # Warn that we're waiting on a tap to continue...
            ./fbink -q ${FBINK_BATCH_FLAG} ${FBINK_BGLESS_FLAG} -m -y 2 "Tap the screen to continue." -W GL16
        fi
        # And then print the tail end of the log on the bottom of the screen...
        crashLog="$(tail -n 25 crash.log | sed -e 's/\t/    /g')"
        # The idea for the margins being to leave enough room for an fbink -Z bar, small horizontal margins, and a font size based on what 6pt looked like @ 265dpi
        # shellcheck disable=SC2086
        ./fbink -q ${FBINK_BATCH_FLAG} ${FBINK_BGLESS_FLAG} -t regular=./fonts/droid/DroidSansMono.ttf,top=$((viewHeight / 2 + FONTH * 2 + FONTH / 2)),left=$((viewWidth / 60)),right=$((viewWidth / 60)),px=$((viewHeight / 64))${FBINK_OT_PADDING} -W GL16 -- "${crashLog}"
        if [ "${PLATFORM}" != "b300-ntx" ]; then
            # So far, we hadn't triggered an actual screen refresh, do that now, to make sure everything is bundled in a single flashing refresh.
            ./fbink -q -f -s
        fi
        # Cue a lemming's faceplant sound effect!

        {
            echo "!!!!"
            echo "Uh oh, something went awry... (Crash n°${CRASH_COUNT}: $(date +'%x @ %X'))"
            echo "Running FW $(cut -f3 -d',' /mnt/onboard/.kobo/version) on Linux $(uname -r) ($(uname -v))"
        } >>crash.log 2>&1
        if [ ${CRASH_COUNT} -lt 5 ] && [ "${ALWAYS_ABORT}" = "false" ]; then
            echo "Attempting to restart KOReader . . ." >>crash.log 2>&1
            echo "!!!!" >>crash.log 2>&1
        fi

        # Pause a bit if it's the first crash in a while, so that it actually has a chance of getting noticed ;).
        if [ ${CRASH_COUNT} -eq 1 ]; then
            # NOTE: We don't actually care about what read read, we're just using it as a fancy sleep ;).
            #       i.e., we pause either until the 15s timeout, or until the user touches the screen.
            # shellcheck disable=SC2039,SC3045
            read -r -t 15 <"${KOBO_TS_INPUT}"
        fi
        # Cycle the last crash timestamp
        CRASH_PREV_TS=${CRASH_TS}

        # But if we've crashed more than 5 consecutive times, exit, because we wouldn't want to be stuck in a loop...
        # NOTE: No need to check for ALWAYS_ABORT, CRASH_COUNT will always be 1 when it's true ;).
        if [ ${CRASH_COUNT} -ge 5 ]; then
            echo "Too many consecutive crashes, aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            break
        fi

        # If the user requested to always abort on crash, do so.
        if [ "${ALWAYS_ABORT}" = "true" ]; then
            echo "Aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            break
        fi
    else
        # Reset the crash counter if that was a sane exit/restart
        CRASH_COUNT=0
    fi

    if [ ${RETURN_VALUE} -eq ${KO_RC_USBMS} ]; then
        # User requested an USBMS session, setup the tool outside of onboard
        USBMS_HOME="/mnt/usbms"
        mkdir -p "${USBMS_HOME}"
        # We're using a custom tmpfs in case /tmp is too small (mainly because we may need to import a large CJK font in there...)
        if ! mount -t tmpfs tmpfs ${USBMS_HOME} -o defaults,size=32M,mode=1777,noatime; then
            echo "Failed to create the USBMS tmpfs, restarting KOReader . . ." >>crash.log 2>&1
            continue
        fi

        if ! ./tar xzf "./data/KoboUSBMS.tar.gz" -C "${USBMS_HOME}"; then
            echo "Couldn't unpack KoboUSBMS, restarting KOReader . . ." >>crash.log 2>&1
            if ! umount "${USBMS_HOME}"; then
                echo "Couldn't unmount the USBMS tmpfs, shutting down in 30 sec!" >>crash.log 2>&1
                sleep 30
                poweroff -f
            fi
            rm -rf "${USBMS_HOME}"
            continue
        fi

        # Then siphon KOReader's language for i18n...
        if grep -q '\["language"\]' 'settings.reader.lua' 2>/dev/null; then
            usbms_lang="$(grep '\["language"\]' 'settings.reader.lua' | cut -d'"' -f4)"
        else
            usbms_lang="C"
        fi

        # If the language is CJK, copy the CJK font, too...
        case "${usbms_lang}" in
            ja* | ko* | zh*)
                cp -pf "${KOREADER_DIR}/fonts/noto/NotoSansCJKsc-Regular.otf" "${USBMS_HOME}/resources/fonts/NotoSansCJKsc-Regular.otf"
                ;;
        esac

        # Here we go!
        if ! cd "${USBMS_HOME}"; then
            echo "Couldn't chdir to ${USBMS_HOME}, restarting KOReader . . ." >>crash.log 2>&1
            if ! umount "${USBMS_HOME}"; then
                echo "Couldn't unmount the USBMS tmpfs, shutting down in 30 sec!" >>crash.log 2>&1
                sleep 30
                poweroff -f
            fi
            rm -rf "${USBMS_HOME}"
            continue
        fi
        env LANGUAGE="${usbms_lang}" ./usbms
        fail=$?
        if [ ${fail} -ne 0 ]; then
            # NOTE: Early init failures return KO_RC_USBMS,
            #       to allow simply restarting KOReader when we know the integrity of onboard hasn't been compromised...
            if [ ${fail} -eq ${KO_RC_USBMS} ]; then
                echo "KoboUSBMS failed to setup an USBMS session, restarting KOReader . . ." >>"${KOREADER_DIR}/crash.log" 2>&1
            else
                # Hu, oh, something went wrong... Stay around for 90s (enough time to look at the syslog over Wi-Fi), and then shutdown.
                logger -p "DAEMON.CRIT" -t "koreader.sh[$$]" "USBMS session failed (${fail}), shutting down in 90 sec!"
                sleep 90
                poweroff -f
            fi
        fi

        # Jump back to the right place, and keep on trucking
        if ! cd "${KOREADER_DIR}"; then
            logger -p "DAEMON.CRIT" -t "koreader.sh[$$]" "Couldn't chdir back to KOREADER_DIR (${KOREADER_DIR}), shutting down in 30 sec!"
            sleep 30
            poweroff -f
        fi

        # Tear down the tmpfs...
        if ! umount "${USBMS_HOME}"; then
            logger -p "DAEMON.CRIT" -t "koreader.sh[$$]" "Couldn't unmount the USBMS tmpfs, shutting down in 30 sec!"
            sleep 30
            poweroff -f
        fi
        rm -rf "${USBMS_HOME}"
    fi

    # Did we request a reboot/shutdown?
    if [ ${RETURN_VALUE} -eq ${KO_RC_HALT} ]; then
        break
    fi
done

# Restore original fb bitdepth if need be...
# Since we also (almost) always enforce Portrait, we also have to restore the original rotation no matter what ;).
if [ -n "${ORIG_FB_BPP}" ]; then
    echo "Restoring original fb bitdepth @ ${ORIG_FB_BPP}bpp & rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
    ./fbdepth -d "${ORIG_FB_BPP}" -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
else
    echo "Restoring original fb rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
    ./fbdepth -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
fi

# Restore original CPUFreq governor if need be...
if [ -n "${ORIG_CPUFREQ_GOV}" ]; then
    echo "${ORIG_CPUFREQ_GOV}" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

    # NOTE: Leave DVFS alone, it'll be handled by Nickel if necessary.
fi

# If we requested a reboot/shutdown, no need to bother with this...
if [ ${RETURN_VALUE} -ne ${KO_RC_HALT} ]; then
    if [ "${VIA_NICKEL}" = "true" ]; then
        if [ "${FROM_KFMON}" = "true" ]; then
            # KFMon is the only launcher that has a toggle to either reboot or restart Nickel on exit
            if grep -q "reboot_on_exit=false" "/mnt/onboard/.adds/kfmon/config/koreader.ini" 2>/dev/null; then
                # KFMon asked us to restart nickel on exit (default since KFMon 0.9.5)
                ./nickel.sh &
            else
                # KFMon asked us to restart the device on exit
                /sbin/reboot
            fi
        else
            # Otherwise, just restart Nickel
            ./nickel.sh &
        fi
    else
        # if we were called from advboot then we must reboot to go to the menu
        # NOTE: This is actually achieved by checking if KSM or a KSM-related script is running:
        #       This might lead to false-positives if you use neither KSM nor advboot to launch KOReader *without nickel running*.
        if ! pgrep -f kbmenu >/dev/null 2>&1; then
            /sbin/reboot
        fi
    fi
fi

# Wipe the clones on exit
rm -f "/tmp/koreader.sh"

exit ${RETURN_VALUE}
