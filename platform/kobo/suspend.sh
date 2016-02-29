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
echo "[$(date +'%x @ %X')] Kobo Suspend: Asked for a Sleep mode suspend"
sleep 2
echo "[$(date +'%x @ %X')] Kobo Suspend: Waited for 2s because of reasons..."
sync
echo "[$(date +'%x @ %X')] Kobo Suspend: Synced FS"
echo ${current_wakeup_count} > /sys/power/wakeup_count
echo "[$(date +'%x @ %X')] Kobo Suspend: Wrote WakeUp count: ${current_wakeup_count} ($?)"
echo mem > /sys/power/state
echo "[$(date +'%x @ %X')] Kobo Suspend: Asked to suspend to RAM... ZzZ ZzZ ZzZ? ($?)"

## And nickel apparently loops like a crazy person if the write to /sys/power/state returns EBUSY...
#echo 0 > /sys/power/state-extended
#echo "Kobo Suspend: Asked to wakeup"

echo "[$(date +'%x @ %X')] Kobo Suspend: END! (WakeUp count: $(cat /sys/power/wakeup_count))"
