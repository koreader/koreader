#!/bin/sh

PCB_ID=$(/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ":" -f2)

# disable wifi and remove all modules
killall udhcpc wpa_supplicant 2>/dev/null
ifconfig eth0 down 2>/dev/null
if [ "${PCB_ID}" -ne 22 ] && [ "${PCB_ID}" -ne 23 ]; then #For pcb_id==22 or 23 we avoid removing the module as it's known to freeze the wifi subsystem
    MODULE="8189fs"
    modprobe -r ${MODULE} 2>/dev/null
fi
