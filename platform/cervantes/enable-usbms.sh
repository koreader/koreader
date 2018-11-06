#!/bin/sh

# adapted to BQ Cervantes from Baskerville's Plato
# https://github.com/baskerville/plato/blob/master/scripts/usb-enable.sh

# exit w/ error if usbms kernel module is loaded
lsmod | grep -q g_file_storage && exit 1

# internal storage partition scheme differs between models.
PCB_ID=$(/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ":" -f2)
DISK=/dev/mmcblk

if [ "$PCB_ID" -eq 22 ] || [ "$PCB_ID" -eq 23 ]; then
    PRODUCT_ID=${PRODUCT_ID:-"0xAD78"}
    PARTITIONS="${DISK}0p7"
else
    PRODUCT_ID=${PRODUCT_ID:-"0xAD79"}
    PARTITIONS="${DISK}0p4"
fi

# for BQ Cervantes
MODULE_PARAMETERS="vendor=0x2A47 product=${PRODUCT_ID} vendor_id=BQ product_id=Cervantes"

# share sdcard if present
[ -e "${DISK}1p1" ] && PARTITIONS="${PARTITIONS},${DISK}1p1"

sync
echo 3 >/proc/sys/vm/drop_caches

for name in public sd; do
    DIR=/mnt/"$name"
    if grep -q "$DIR" /proc/mounts; then
        umount "$DIR" || umount -l "$DIR"
        # exit w/ error if partition is still mounted
        mountpoint -q "$DIR" && exit 2
    fi
done

# shellcheck disable=SC2086
modprobe g_file_storage file="$PARTITIONS" stall=1 removable=1 $MODULE_PARAMETERS
sleep 1

# normal exit
exit 0
