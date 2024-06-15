#!/bin/sh

lsmod | grep -q g_file_storage || exit 1

modprobe -r g_file_storage
sleep 1

PCB_ID=$(/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ":" -f2)
DISK=/dev/mmcblk

if [ "${PCB_ID}" -eq 22 ] || [ "${PCB_ID}" -eq 23 ]; then
    PARTITION="${DISK}0p7"
else
    PARTITION="${DISK}0p4"
fi

MOUNT_ARGS="noatime,nodiratime,shortname=mixed,utf8"

dosfsck -a -w "${PARTITION}" >dosfsck.log 2>&1

mount -o "${MOUNT_ARGS}" -t vfat "${PARTITION}" /mnt/onboard

PARTITION=${DISK}1p1

[ -e "${PARTITION}" ] && mount -o "${MOUNT_ARGS}" -t vfat "${PARTITION}" /mnt/sd
