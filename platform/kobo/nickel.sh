#!/bin/sh
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib:"

# Ensures fmon will restart. Note that we don't have to worry about reaping this, nickel kills on-animator.sh on start.
(
    # NOTE: Recent FW versions appear to do away with the sleep on some platforms (I'm assuming the newer, faster, better ones!)
    usleep 400000
    /etc/init.d/on-animator.sh
) &

# We don't need to duplicate any of the env setup from rcS, since we will only ever run this to *restart* nickel, and not bootstrap it.
# Meaning we've already got most of the necessary env from nickel itself via both our launcher (fmon/KFMon) and our own startup script.
export LD_LIBRARY_PATH="/usr/local/Kobo"

# Make sure we kill the WiFi first, because nickel apparently doesn't like it if it's up... (cf. #1520)
# NOTE: That check is possibly wrong on PLATFORM == freescale (because I don't know if the sdio_wifi_pwr module exists there), but we don't terribly care about that.
if lsmod | grep -q sdio_wifi_pwr; then
    killall udhcpc default.script wpa_supplicant 2>/dev/null
    [ "${WIFI_MODULE}" != "8189fs" ] && wlarm_le -i "${INTERFACE}" down
    ifconfig "${INTERFACE}" down
    # NOTE: Kobo's busybox build is weird. rmmod appears to be modprobe in disguise, defaulting to the -r flag. If re-specifying -r starts to fail one day, switch to rmmod without args, or modprobe -r.
    # c.f., #2394?
    usleep 200000
    rmmod -r "${WIFI_MODULE}"
    usleep 200000
    rmmod -r sdio_wifi_pwr
fi

# Flush buffers to disk, who knows.
sync

# And finally, simply restart nickel.
# We don't care about horribly legacy stuff, because if people switch between nickel and KOReader in the first place, I assume they're using a decently recent enough FW version.
# Last tested on an H2O running FW 4.7.x
/usr/local/Kobo/hindenburg &
LIBC_FATAL_STDERR_=1 /usr/local/Kobo/nickel -platform kobo -skipFontLoad &

# Handle sdcard
if [ -e "/dev/mmcblk1p1" ]; then
    echo sd add /dev/mmcblk1p1 >>/tmp/nickel-hardware-status &
fi

return 0
