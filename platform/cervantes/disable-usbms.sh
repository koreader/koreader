
lsmod | grep -q g_file_storage || exit 1

modprobe -r g_file_storage
sleep 1

DISK=/dev/mmcblk
PARTITION=${DISK}0p3
MOUNT_ARGS="noatime,nodiratime,shortname=mixed,utf8"

dosfsck -a -w "$PARTITION" > dosfsck.log 2>&1

mount -o "$MOUNT_ARGS" -t vfat "$PARTITION" /mnt/onboard

PARTITION=${DISK}1p1

[ -e "$PARTITION" ] && mount -o "$MOUNT_ARGS" -t vfat "$PARTITION" /mnt/sd

