#!/bin/sh
# Standalone KOReader application for BQ Cervantes
# this file is intended to replace /etc/rc.local on BQ developers firmware

# turn off the green flashing led.
echo "ch 4" >/sys/devices/platform/pmic_light.1/lit
echo "cur 0" >/sys/devices/platform/pmic_light.1/lit
echo "dc 0" >/sys/devices/platform/pmic_light.1/lit

# ensure we have a proper time.
if [ "$(date '+%Y')" -lt 2010 ]; then
    echo "Fixing date before 2010"
    date +%Y%m%d -s "20100101"
    hwclock -w
fi

# assign public & private partition devices based on pcb.
PCB_ID=$(/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ":" -f2)
if [ "${PCB_ID}" -eq 22 ] || [ "${PCB_ID}" -eq 23 ]; then
    PRIVATE="/dev/mmcblk0p5"
    PUBLIC="/dev/mmcblk0p7"
else
    PRIVATE="/dev/mmcblk0p7"
    PUBLIC="/dev/mmcblk0p4"
fi

# mount internal partitions
mount ${PRIVATE} /mnt/private
mount ${PUBLIC} /mnt/public

# mount sdcard if present
if [ -b /dev/mmcblk1p1 ]; then
    mount /dev/mmcblk1p1 /mnt/sd
fi

# stop connman daemon, KOReader will use wpa_supplicant directly.
[ -x /etc/init.d/connman ] && /etc/init.d/connman stop

# for Cervantes 4 unload realtek module.
if [ "${PCB_ID}" -eq 68 ] && lsmod | grep -q 8189fs; then
    modprobe -r 8189fs
fi

# use 'safemode' tool whenever possible instead of enabling usbnet unconditionally.
if [ -x /usr/bin/safemode ]; then
    safemode network
else
    # start usbnet using BQ scripts
    /usr/bin/usbup.sh
    /usr/sbin/inetd
fi

# check if KOReader script exists.
if [ -x /mnt/private/koreader/koreader.sh ]; then
    # yada! KOReader is installed and ready to run.
    while true; do
        /mnt/private/koreader/koreader.sh
        if [ -x /usr/bin/safemode ]; then
            safemode storage || sleep 1
        else
            sleep 1
        fi
    done
else
    # KOReader script not found or not executable.
    # if 'safemode' was found enable usbnet now, since it is currently disabled
    if [ -x /usr/bin/safemode ]; then
        /usr/bin/usbup.sh
        /usr/sbin/inetd
    fi

    exit 1
fi

exit 0
