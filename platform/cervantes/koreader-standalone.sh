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
if [ "$PCB_ID" -eq 22 ] || [ "$PCB_ID" -eq 23 ]; then
    PRIVATE="/dev/mmcblk0p5"
    PUBLIC="/dev/mmcblk0p7"
else
    PRIVATE="/dev/mmcblk0p7"
    PUBLIC="/dev/mmcblk0p4"
fi

# mount internal partitions
mount $PRIVATE /mnt/private
mount $PUBLIC /mnt/public

# mount sdcard if present
if [ -b /dev/mmcblk1p1 ]; then
    mount /dev/mmcblk1p1 /mnt/sd
fi

# stop connman daemon, KOReader will use wpa_supplicant directly.
[ -x /etc/init.d/connman ] && /etc/init.d/connman stop

# for Cervantes 4 unload realtek module.
if [ "$PCB_ID" -eq 68 ] && lsmod | grep -q 8189fs; then
    modprobe -r 8189fs
fi

# start usbnet using BQ scripts (192.168.4.1/24 w/ hardcoded MAC addr)
/usr/bin/usbup.sh
/usr/sbin/inetd

# check if KOReader script exists.
if [ -x /mnt/private/koreader/koreader.sh ]; then
    # yada! KOReader is installed and ready to run.
    while true; do
        /mnt/private/koreader/koreader.sh
        sleep 1
    done
else
    # nothing to do, leaving rc.local.
    exit 1
fi

exit 0
