#!/bin/sh
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib:"

# We don't need to duplicate any of the env setup from rcS, since we will only ever run this to *restart* nickel, and not bootstrap it.
# Meaning we've already got most of the necessary env from nickel itself via both our launcher (fmon/KFMon) and our own startup script.
# NOTE: LD_LIBRARY_PATH is the only late export from rcS we don't siphon in koreader.sh, for obvious reasons ;).
export LD_LIBRARY_PATH="/usr/local/Kobo"

# Reset PWD, and clear up our own custom stuff from the env while we're there, otherwise, USBMS may become very wonky on newer FW...
# shellcheck disable=SC2164
cd /
unset OLDPWD
unset LC_ALL TESSDATA_PREFIX STARDICT_DATA_DIR EXT_FONT_DIR
unset KO_NO_CBB

# Ensures fmon will restart. Note that we don't have to worry about reaping this, nickel kills on-animator.sh on start.
(
    if [ "${PLATFORM}" = "freescale" ] || [ "${PLATFORM}" = "mx50-ntx" ] || [ "${PLATFORM}" = "mx6sl-ntx" ]; then
        usleep 400000
    fi
    /etc/init.d/on-animator.sh
) &

# Make sure we kill the Wi-Fi first, because nickel apparently doesn't like it if it's up... (cf. #1520)
# NOTE: That check is possibly wrong on PLATFORM == freescale (because I don't know if the sdio_wifi_pwr module exists there), but we don't terribly care about that.
if lsmod | grep -q sdio_wifi_pwr; then
    killall -q -TERM restore-wifi-async.sh enable-wifi.sh obtain-ip.sh
    cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
    old_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"
    if [ -x "/sbin/dhcpcd" ]; then
        env -u LD_LIBRARY_PATH dhcpcd -d -k "${INTERFACE}"
        killall -q -TERM udhcpc default.script
    else
        killall -q -TERM udhcpc default.script dhcpcd
    fi
    # NOTE: dhcpcd -k waits for the signalled process to die, but busybox's killall doesn't have a -w, --wait flag,
    #       so we have to wait for udhcpc to die ourselves...
    # NOTE: But if all is well, there *isn't* any udhcpc process or script left to begin with...
    kill_timeout=0
    while pkill -0 udhcpc; do
        # Stop waiting after 5s
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
    wpa_cli terminate
    [ "${WIFI_MODULE}" != "8189fs" ] && [ "${WIFI_MODULE}" != "8192es" ] && wlarm_le -i "${INTERFACE}" down
    ifconfig "${INTERFACE}" down
    # NOTE: Kobo's busybox build is weird. rmmod appears to be modprobe in disguise, defaulting to the -r flag...
    #       But since there's currently no modules.dep file being shipped, nor do they include the depmod applet,
    #       go with what the FW is doing, which is rmmod.
    # c.f., #2394?
    usleep 250000
    rmmod "${WIFI_MODULE}"
    usleep 250000
    rmmod sdio_wifi_pwr
fi

# Flush buffers to disk, who knows.
sync

# And finally, simply restart nickel.
# We don't care about horribly legacy stuff, because if people switch between nickel and KOReader in the first place, I assume they're using a decently recent enough FW version.
# Last tested on an H2O & a Forma running FW 4.7.x - 4.12.x
/usr/local/Kobo/hindenburg &
LIBC_FATAL_STDERR_=1 /usr/local/Kobo/nickel -platform kobo -skipFontLoad &
udevadm trigger &

# Handle sdcard
if [ -e "/dev/mmcblk1p1" ]; then
    echo sd add /dev/mmcblk1p1 >>/tmp/nickel-hardware-status &
fi

return 0
