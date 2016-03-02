#!/bin/sh
export PATH="${PATH}:/sbin:/usr/sbin"

echo "[$(date +'%x @ %X')] Kobo Suspend: BEGIN!"
# Disable wifi
if lsmod | grep -q sdio_wifi_pwr ; then
	wlarm_le -i eth0 down
	ifconfig eth0 down
	rmmod -r dhd
	rmmod -r sdio_wifi_pwr
	echo "[$(date +'%x @ %X')] Kobo Suspend: Killed WiFi"
fi

# Go to sleep
current_wakeup_count="$(cat /sys/power/wakeup_count)"
echo "[$(date +'%x @ %X')] Kobo Suspend: Current WakeUp count: ${current_wakeup_count}"
echo 1 > /sys/power/state-extended
# NOTE: Sets gSleep_Mode_Suspend to 1. Used as a flag throughout the kernel to suspend/resume various subsystems
#       cf. kernel/power/main.c @ L#207
echo "[$(date +'%x @ %X')] Kobo Suspend: Asked the kernel to put subsystems to sleep"
sleep 2
echo "[$(date +'%x @ %X')] Kobo Suspend: Waited for 2s because of reasons..."
sync
echo "[$(date +'%x @ %X')] Kobo Suspend: Synced FS"
echo ${current_wakeup_count} > /sys/power/wakeup_count
echo "[$(date +'%x @ %X')] Kobo Suspend: Wrote WakeUp count: ${current_wakeup_count} ($?)"
echo mem > /sys/power/state
echo "[$(date +'%x @ %X')] Kobo Suspend: Asked to suspend to RAM... ZzZ ZzZ ZzZ? ($?)"
## NOTE: Ideally, we'd need a way to warn the user that suspending gloriously failed at this point...
##       We can safely assume that just from a non-zero return code, without looking at the detailed stderr message
##       (most of the failures we'll see are -EBUSY anyway)
## For reference, when that happens to nickel, it appears to keep retrying to wakeup & sleep ad nauseam,
## which is where the non-sensical 1 -> mem -> 0 loop idea comes from...
## cf. nickel_suspend_strace.txt for more details.

echo "[$(date +'%x @ %X')] Kobo Suspend: END! (WakeUp count: $(cat /sys/power/wakeup_count))"
