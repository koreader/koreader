#!/bin/sh
#
# KOReader launcher for Bookeen Cybook devices (Allwinner A13 / sun5i).
#
# WHY THIS EXISTS AT ALL
#
# KOReader on this port is not merely *conventionally* started from its own
# directory -- it is unable to start from anywhere else. Three separate things
# resolve relative to the current working directory:
#
#   1. reader.lua's shebang is `#!./luajit`. The kernel resolves an interpreter
#      path relative to the cwd of the process calling execve(), so launching it
#      from the wrong directory fails with ENOENT on the *interpreter*, which
#      reports as "no such file or directory" for reader.lua itself.
#   2. frontend/version.lua does io.open("git-rev") with a relative path, so the
#      version KOReader reports is whichever install tree it happens to be
#      standing in -- not the one it was built from. A stale copy elsewhere on
#      the device silently wins, which is exactly how a freshly installed build
#      kept displaying an old version string.
#   3. frontend/device/bookeen/device.lua shells out to "./wlan.sh start|stop"
#      for Wi-Fi, and setupkoenv.lua builds package.path/cpath from ".".
#
# So the single most important line in this file is the `cd` below. Everything
# else is convenience.
#
# ON-SCREEN FEEDBACK
#
# Every other port's launcher drives fbink for on-screen progress and the crash
# "bomb" screen. fbink is not built for bookeen (thirdparty/fbink is excluded for
# this target, and there is no fbink or fbdepth in the install tree), so none of
# that machinery is available here.
#
# The panel is not unreachable from shell, though: the stock rootfs ships
# /bin/eink and /bin/epd-display, which open /dev/fb0 + /dev/disp and blit a BMP.
# The vendor's own scripts use them exactly as ko_splash() does below --
# `/bin/eink d /system/update_prompt_bat.bmp` (bin/update.sh:132),
# `/bin/epd-display d /system/factory_bundle.bmp` (S34bundle_setup.sh:16).
#
# So a *few* stock BMPs can be shown, and one is: the crash-abort screen, which
# is the only state where the user is otherwise left staring at a dead panel with
# no idea KOReader gave up. Progress reporting is deliberately not attempted --
# there are no assets for it beyond the vendor's update/factory bitmaps, and
# drawing to /dev/disp while KOReader is starting up would contend with
# framebuffer_mxcfb.lua for the same ioctls. Everything else goes to crash.log:
# `tail -f crash.log` over telnet/adb is the debugging path.
#
# There is likewise no fbdepth bitdepth/rotation dance: this target does not go
# through fbdev at all. framebuffer_mxcfb.lua opens /dev/disp and drives the
# vendor DISP_CMD_EINK_* ioctls directly, so there is no bpp to switch.
#
# USERLAND CONSTRAINTS -- checked against the stock rootfs, not assumed
#
# /bin/sh is BusyBox 1.18.3 ash (from rootfs.fex). The applets used below all
# exist in that binary: realpath, dirname, md5sum, pidof, sync, sleep, date,
# tail, grep, cp, rm. `eink` is not an applet but a separate stock binary at
# /bin/eink, checked for with -x before use. Notably ABSENT, so avoided here:
# `timeout` (kobo and remarkable use it to wait on a touch event), `pkill`/`pgrep`
# (cervantes and kobo use `pkill -0` for liveness -- `pidof` is used instead), and
# `xargs -r` (whose presence in BusyBox is a build-time feature flag, so the
# leftover cleanup below uses a read loop instead).

# There is no locale data anywhere in the stock rootfs -- no /usr/lib/locale, no
# /usr/lib/gconv, and /usr/share/locale is empty -- so this setlocale() request
# cannot succeed and glibc silently keeps the C locale. It is set anyway for
# parity with every other port, so that behaviour does not quietly diverge if a
# locale is ever added to the image. reader.lua pins LC_NUMERIC to C itself.
export LC_ALL="en_US.UTF-8"

# Draw a stock BMP to the panel. See "ON-SCREEN FEEDBACK" in the header: this is
# the vendor's own idiom, and only /system bitmaps that ship on the device are
# used, so there is nothing to install. Silent no-op if either is missing.
ko_splash() {
    [ -x /bin/eink ] && [ -e "$1" ] && /bin/eink d "$1" >/dev/null 2>&1
}

# KOReader's working directory, resolved to an absolute path *before* the
# relocation below, because after that exec $0 no longer points into the install
# tree. `realpath` also resolves the symlink farm `make update` builds the
# install tree out of.
if [ -z "${KOREADER_DIR}" ]; then
    if KOREADER_DIR="$(dirname "$(realpath "$0")" 2>/dev/null)" && [ -n "${KOREADER_DIR}" ]; then
        :
    else
        # Fallback for a BusyBox built without the realpath applet.
        KOREADER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
    fi
fi
export KOREADER_DIR
UNPACK_DIR="${KOREADER_DIR%/*}"

# Canonicalize non-option arguments against the *current* directory before the cd
# below moves us, so `./koreader.sh book.epub` from /mnt/fat still opens the right
# file. The device ports that skip this step (kobo, cervantes, remarkable) get
# away with it because a GUI launcher invokes them with no arguments at all; here
# a shell is the normal way in, so this matters. Same trick as
# platform/common/koreader.sh: pop from the left and push to the right, touching
# each argument exactly once, which preserves the original order.
for arg; do
    shift
    if [ -e "${PWD}/${arg}" ]; then
        arg="${PWD}/${arg}"
    fi
    set -- "$@" "${arg}"
done

# Relocalize ourselves to /tmp (a tmpfs, per /etc/fstab).
#
# Two reasons, both real:
#   - An OTA extracts over the install tree while this script is running. ash
#     reads a script incrementally rather than slurping it, so overwriting the
#     file underneath a running shell can make it resume mid-token in the *new*
#     bytes. Running from a private copy makes the update atomic from our side.
#   - It gives Bookeen:isStartupScriptUpToDate() something to compare against:
#     it md5s /tmp/koreader.sh (what is running) versus ./koreader.sh (what is
#     installed) and prompts for a full exit when an update changed this file.
if [ "$(dirname "$0")" != '/tmp' ]; then
    cp -pf "$0" '/tmp/koreader.sh' || exit 1
    chmod 755 '/tmp/koreader.sh'
    exec '/tmp/koreader.sh' "$@"
fi

# THE line. Everything above exists to make this correct; see the header.
cd "${KOREADER_DIR}" || exit 1

# We keep at most 500KB worth of crash log. Do this before writing anything, so
# a wedged loop cannot fill a small FAT partition.
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

if [ ! -x ./reader.lua ] || [ ! -x ./luajit ]; then
    echo "koreader.sh: ${KOREADER_DIR} is not a usable install (missing reader.lua or luajit)" >>crash.log 2>&1
    # The likeliest first-boot failure: unzipped to the wrong place, or unzipped
    # by something that dropped the exec bits. Worth saying on the panel, since a
    # user who got here has no shell output either.
    ko_splash /system/update_finished_error.bmp
    exit 1
fi

# Apply an update dropped in ota/ by OTAManager.
#
# Note that over-the-air updating is not actually wired up for this target:
# frontend/device/bookeen/device.lua sets no `ota_model`, so Device:otaModel()
# returns nil and OTAManager reports "Unable to determine OTA model" -- which is
# honest, because no KOReader OTA server hosts a bookeen build. This handler is
# still worth having, because it is the supported way to *side-load* a new build
# without unzipping over a live tree: drop the .tar.xz in ota/ as
# update.tar.xz and restart.
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/update.tar.xz"
    if [ -f "${NEWUPDATE}" ]; then
        echo "[$(date)] koreader.sh: applying update from ${NEWUPDATE}" >>crash.log 2>&1
        # Keep a copy of the old manifest so leftovers can be pruned afterwards.
        cp "${KOREADER_DIR}/ota/package.index" /tmp/package.index 2>/dev/null
        # `unpack` is the shipped bsdtar-derived extractor; -X is the variant that
        # emits a progress counter, which on other ports feeds an fbink daemon.
        # With no fbink here it just goes to the log.
        (cd "${UNPACK_DIR}" && "${KOREADER_DIR}/unpack" -X "${NEWUPDATE}" >>"${KOREADER_DIR}/crash.log" 2>&1)
        fail=$?
        if [ "${fail}" -eq 0 ]; then
            # Delete files the previous install had and this one does not.
            # A read loop rather than `xargs -r`, which BusyBox may not have.
            if [ -f /tmp/package.index ] && [ -f "${KOREADER_DIR}/ota/package.index" ]; then
                grep -x -v -F -f "${KOREADER_DIR}/ota/package.index" /tmp/package.index 2>/dev/null |
                    while IFS= read -r leftover; do
                        [ -n "${leftover}" ] && rm -f "${UNPACK_DIR}/${leftover}"
                    done
            fi
            echo "[$(date)] koreader.sh: update successful" >>crash.log 2>&1
        else
            echo "[$(date)] koreader.sh: update FAILED (${fail}); KOReader may not function properly" >>crash.log 2>&1
        fi
        # Always purge the payload, successful or not, to prevent an update loop.
        rm -f /tmp/package.index "${NEWUPDATE}"
        # Flush before restarting. This *will* stall for a while on this NAND.
        sync
    fi
}

# Keep an initial check in addition to the one in the restart loop, so an update
# to this very script is picked up on the next launch rather than the one after.
ko_update_check
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # We know we are in the right directory by now, so $0 is not needed.
    exec ./koreader.sh "$@"
fi

# Dictionaries, relative to KOREADER_DIR (see the cd above).
export STARDICT_DATA_DIR="data/dict"

# User-supplied fonts. /mnt/fat is the FAT user partition -- the one exposed over
# USB mass storage and where books live (/etc/fstab: /dev/fat -> /mnt/fat). The
# rootfs is ext2 mounted read-only and ships no fonts directory at all, so there
# is no system font path to offer instead.
export EXT_FONT_DIR="/mnt/fat/fonts"

# Optionally stop the stock reader while we run.
#
# The stock reader contends for the panel: both /mnt/app/ebrmain and
# /mnt/app/boordr reference /dev/disp (and /dev/fb0), i.e. they drive the same
# DISP_CMD_EINK_* ioctls this port does, and two processes issuing those
# concurrently can produce garbage. Every comparable port therefore stops its
# native app -- kobo kills nickel, cervantes kills QBookApp.
#
# This is nevertheless OPT-IN here, unlike those ports, because KOReader has
# already been run on this hardware *without* stopping it and behaved (touch,
# refresh and input all worked). Killing it by default would change a
# known-working setup on the strength of a theoretical conflict, and the failure
# mode is bad: /etc/init.d/ebrmain.sh stop is a `killall -9`, so if KOReader then
# fails to start, the device is left with no UI at all until it is rebooted.
#
# So: export KO_STOP_EBRMAIN=1 to enable it. Worth trying if the panel shows
# corruption or stale content that KOReader itself cannot explain.
#
# DO NOT set it if KOReader was started by the platform/bookeen/cybook_upgrade
# drop-in. That installs a shim at /mnt/app/boordr which ebrmain execv()s, so
# ebrmain is then this script's own grandparent: `ebrmain.sh stop` is
# `killall -9 ebrmain boordr`, and killing our own supervisor mid-run discards
# the RC_* exit code the shim was going to hand back (so power-off and the
# crash/USB-exposure path both stop working). When launched through the shim
# there is also nothing to stop -- the stock reader was never started.
#
# BusyBox here has no pkill/pgrep; pidof is the available liveness check. The
# vendor's own init script is used for both directions rather than reimplementing
# the kill (it also chmod +x's the binaries, remounting / rw to do so).
VIA_EBRMAIN="false"
if [ -n "${KO_STOP_EBRMAIN}" ] && [ -n "${KO_VIA_BOORDR_SHIM}" ]; then
    echo "[$(date)] koreader.sh: ignoring KO_STOP_EBRMAIN -- started via the boordr shim, ebrmain is our parent" >>crash.log 2>&1
elif [ -n "${KO_STOP_EBRMAIN}" ] && [ -x /etc/init.d/ebrmain.sh ]; then
    if pidof ebrmain >/dev/null 2>&1 || pidof boordr >/dev/null 2>&1; then
        VIA_EBRMAIN="true"
        echo "[$(date)] koreader.sh: stopping the stock reader (KO_STOP_EBRMAIN set)" >>crash.log 2>&1
        /etc/init.d/ebrmain.sh stop >>crash.log 2>&1
    fi
fi

CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# 85 is the magic value UIManager:quit() uses to ask for a restart (see
# UIManager:restartKOReader and the generic Device:install path). Seed with it so
# the loop runs once.
RETURN_VALUE=85

while [ ${RETURN_VALUE} -ne 0 ]; do
    if [ ${RETURN_VALUE} -eq 85 ]; then
        # Check again here, so "Restart KOReader" in the menu can apply an update.
        ko_update_check
    fi

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    # Do not restart with the original arguments: if a specific document is what
    # crashed us, reopening it would just crash again. KOReader restores the last
    # file from its own settings anyway.
    set --

    if [ ${RETURN_VALUE} -ne 0 ] && [ ${RETURN_VALUE} -ne 85 ]; then
        CRASH_COUNT=$((CRASH_COUNT + 1))
        CRASH_TS=$(date +'%s')
        # Treat it as a first crash again if the last one was a while ago.
        if [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ]; then
            CRASH_COUNT=1
        fi

        if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
            ALWAYS_ABORT="true"
            CRASH_COUNT=1
        else
            ALWAYS_ABORT="false"
        fi

        {
            echo "!!!!"
            echo "Uh oh, something went awry... (Crash n°${CRASH_COUNT} -> ${RETURN_VALUE}: $(date))"
            echo "Running on Linux $(uname -r) ($(uname -v))"
        } >>crash.log 2>&1

        if [ ${CRASH_COUNT} -ge 5 ]; then
            echo "Too many consecutive crashes, aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            # Give up visibly. Without this the panel keeps whatever was last
            # refreshed and the device looks merely frozen. This is the closest
            # stock bitmap to "it went wrong"; other ports draw an fbink bomb.
            ko_splash /system/update_finished_error.bmp
            break
        fi
        if [ "${ALWAYS_ABORT}" = "true" ]; then
            echo "Aborting on crash as requested . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            ko_splash /system/update_finished_error.bmp
            break
        fi

        echo "Attempting to restart KOReader . . ." >>crash.log 2>&1
        echo "!!!!" >>crash.log 2>&1
        # Breathe before retrying. Other ports wait on a touch event with
        # `timeout head /dev/input/event1`; BusyBox here has no timeout applet,
        # and with no fbink there is nothing on screen to acknowledge anyway, so
        # this is a plain short sleep rather than 15s of apparent hang.
        if [ ${CRASH_COUNT} -eq 1 ]; then
            sleep 5
        fi
        CRASH_PREV_TS=${CRASH_TS}
    else
        CRASH_COUNT=0
    fi
done

if [ "${VIA_EBRMAIN}" = "true" ]; then
    echo "[$(date)] koreader.sh: restarting the stock reader" >>crash.log 2>&1
    /etc/init.d/ebrmain.sh start >>crash.log 2>&1
fi

exit ${RETURN_VALUE}
