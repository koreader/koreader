#!/bin/sh
export PATH="${PATH}:/sbin:/usr/sbin"

echo "[$(date +'%x @ %X')] Kobo Suspend: Going to sleep . . ."
# NOTE: Sleep as little as possible here, sleeping has a tendency to make everything mysteriously hang...

# Depending on device/FW version, some kernels do not support wakeup_count, account for that
if [ -e "/sys/power/wakeup_count" ] ; then
	#HAS_WAKEUP_COUNT="true"
	# NOTE: ... and of course, it appears to be broken, which probably explains why nickel doesn't use this facility...
	#	(By broken, I mean that the system wakes up right away).
	#	So, unless that changes, unconditionally disable it.
	HAS_WAKEUP_COUNT="false"
fi

# Clear the kernel ring buffer... (we're missing a proper -C flag...)
#dmesg -c >/dev/null

# Go to sleep
if [ "${HAS_WAKEUP_COUNT}" == "true" ] ; then
	current_wakeup_count="$(cat /sys/power/wakeup_count)"
	echo "[$(date +'%x @ %X')] Kobo Suspend: Current WakeUp count: ${current_wakeup_count}"
fi
echo 1 > /sys/power/state-extended
# NOTE: Sets gSleep_Mode_Suspend to 1. Used as a flag throughout the kernel to suspend/resume various subsystems
#       cf. kernel/power/main.c @ L#207
echo "[$(date +'%x @ %X')] Kobo Suspend: Asked the kernel to put subsystems to sleep"
sleep 2
echo "[$(date +'%x @ %X')] Kobo Suspend: Waited for 2s because of reasons..."
sync
echo "[$(date +'%x @ %X')] Kobo Suspend: Synced FS"
if [ "${HAS_WAKEUP_COUNT}" == "true" ] ; then
	echo ${current_wakeup_count} > /sys/power/wakeup_count
	echo "[$(date +'%x @ %X')] Kobo Suspend: Wrote WakeUp count: ${current_wakeup_count} ($?)"
fi
echo "[$(date +'%x @ %X')] Kobo Suspend: Asking for a suspend to RAM . . ."
echo mem > /sys/power/state
# NOTE: At this point, we *should* be in suspend to RAM, as such, execution should only resume on wakeup...
echo "[$(date +'%x @ %X')] Kobo Suspend: ZzZ ZzZ ZzZ? ($?)"
## NOTE: Ideally, we'd need a way to warn the user that suspending gloriously failed at this point...
##       We can safely assume that just from a non-zero return code, without looking at the detailed stderr message
##       (most of the failures we'll see are -EBUSY anyway)
## For reference, when that happens to nickel, it appears to keep retrying to wakeup & sleep ad nauseam,
## which is where the non-sensical 1 -> mem -> 0 loop idea comes from...
## cf. nickel_suspend_strace.txt for more details.

if [ "${HAS_WAKEUP_COUNT}" == "true" ] ; then
	echo "[$(date +'%x @ %X')] Kobo Suspend: Woke up! (WakeUp count: $(cat /sys/power/wakeup_count))"
else
	echo "[$(date +'%x @ %X')] Kobo Suspend: Woke up!"
fi

# Print tke kernel log since our attempt to sleep...
#dmesg -c

# Now that we're up, unflag subsystems for suspend...
# NOTE: We do that in Kobo:resume() to keep things tidy and easier to follow
#echo 0 > /sys/power/state-extended
#echo "[$(date +'%x @ %X')] Kobo Suspend: Unflagged kernel subsystems for suspend"
