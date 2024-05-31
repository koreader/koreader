#!/bin/sh
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib:"

# We don't need to duplicate any of the env setup from rcS, since we will only ever run this to *restart* nickel, and not bootstrap it.
# Meaning we've already got most of the necessary env from nickel itself via both our launcher (fmon/KFMon) and our own startup script.
# NOTE: LD_LIBRARY_PATH is the only late export from rcS we don't siphon in koreader.sh, for obvious reasons ;).
export LD_LIBRARY_PATH="/usr/local/Kobo"
# Ditto, 4.28+
export QT_GSTREAMER_PLAYBIN_AUDIOSINK=alsasink
export QT_GSTREAMER_PLAYBIN_AUDIOSINK_DEVICE_PARAMETER=bluealsa:DEV=00:00:00:00:00:00

# Reset PWD, and clear up our own custom stuff from the env while we're there, otherwise, USBMS may become very wonky on newer FW...
# shellcheck disable=SC2164
cd /
unset OLDPWD
unset LC_ALL STARDICT_DATA_DIR EXT_FONT_DIR
unset KO_DONT_GRAB_INPUT
unset FBINK_FORCE_ROTA

# Ensures fmon will restart. Note that we don't have to worry about reaping this, nickel kills on-animator.sh on start.
(
    if [ "${PLATFORM}" = "freescale" ] || [ "${PLATFORM}" = "mx50-ntx" ] || [ "${PLATFORM}" = "mx6sl-ntx" ]; then
        usleep 400000
    fi
    /etc/init.d/on-animator.sh
) &

# Make sure we kill the Wi-Fi first, because nickel apparently doesn't like it if it's up... (cf. #1520)
if grep -q "^${WIFI_MODULE} " "/proc/modules"; then
    killall -q -TERM restore-wifi-async.sh enable-wifi.sh obtain-ip.sh

    cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
    old_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"

    if [ -x "/sbin/dhcpcd" ]; then
        dhcpcd -d -k "${INTERFACE}"
        killall -q -TERM udhcpc default.script
    else
        killall -q -TERM udhcpc default.script dhcpcd
    fi

    kill_timeout=0
    while pkill -0 udhcpc; do
        if [ ${kill_timeout} -ge 20 ]; then
            break
        fi
        usleep 250000
        kill_timeout=$((kill_timeout + 1))
    done

    new_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"
    # Restore our network-specific resolv.conf if the DHCP client wiped it when releasing the lease...
    if [ "${new_hash}" != "${old_hash}" ]; then
        mv -f "/tmp/resolv.ko" "/etc/resolv.conf"
    else
        rm -f "/tmp/resolv.ko"
    fi

    wpa_cli -i "${INTERFACE}" terminate

    [ "${WIFI_MODULE}" = "dhd" ] && wlarm_le -i "${INTERFACE}" down
    ifconfig "${INTERFACE}" down

    WIFI_DEP_MOD=""
    POWER_TOGGLE="module"
    SKIP_UNLOAD=""
    case "${WIFI_MODULE}" in
        "moal")
            WIFI_DEP_MOD="mlan"
            POWER_TOGGLE="ntx_io"
            ;;
        "wlan_drv_gen4m")
            POWER_TOGGLE="wmt"
            SKIP_UNLOAD="true"
            ;;
    esac

    if [ -z "${SKIP_UNLOAD}" ]; then
        usleep 250000
        rmmod "${WIFI_MODULE}"

        if [ -n "${WIFI_DEP_MOD}" ]; then
            if grep -q "^${WIFI_DEP_MOD} " "/proc/modules"; then
                usleep 250000
                rmmod "${WIFI_DEP_MOD}"
            fi
        fi
    fi

    case "${POWER_TOGGLE}" in
        "ntx_io")
            usleep 250000
            "${KOREADER_DIR}"/luajit "${KOREADER_DIR}"/frontend/device/kobo/ntx_io.lua 208 0
            ;;
        "wmt")
            echo 0 >/dev/wmtWifi
            ;;
        *)
            if grep -q "^sdio_wifi_pwr " "/proc/modules"; then
                if [ -n "${CPUFREQ_DVFS}" ]; then
                    echo "0" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
                    # Leave Nickel in its usual state, don't try to use conservative
                    echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"
                fi
                usleep 250000
                rmmod sdio_wifi_pwr
            fi

            if [ ! -e "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko" ]; then
                usleep 250000
                "${KOREADER_DIR}"/luajit "${KOREADER_DIR}"/frontend/device/kobo/ntx_io.lua 208 0
            fi
            ;;
    esac
fi

unset KOREADER_DIR
unset CPUFREQ_DVFS CPUFREQ_CONSERVATIVE

# Recreate Nickel's FIFO ourselves, like rcS does, because udev *will* write to it!
# Plus, we actually *do* want the stuff udev writes in there to be processed by Nickel, anyway.
rm -f "/tmp/nickel-hardware-status"
mkfifo "/tmp/nickel-hardware-status"

# Flush buffers to disk, who knows.
sync

# Handle the sdcard:
# We need to unmount it ourselves, or Nickel wigs out and shows an "unrecognized FS" popup until the next fake sd add event.
# The following udev trigger should then ensure there's a single sd add event enqueued in the FIFO for it to process,
# ensuring it gets sanely detected and remounted RO.
if [ -e "/dev/mmcblk1p1" ]; then
    umount /mnt/sd
fi

# And finally, simply restart nickel.
# We don't care about horribly legacy stuff, because if people switch between nickel and KOReader in the first place, I assume they're using a decently recent enough FW version.
# Last tested on an H2O & a Forma running FW 4.7.x - 4.25.x
/usr/local/Kobo/hindenburg &
LIBC_FATAL_STDERR_=1 /usr/local/Kobo/nickel -platform kobo -skipFontLoad &
[ "${PLATFORM}" != "freescale" ] && udevadm trigger &

return 0
