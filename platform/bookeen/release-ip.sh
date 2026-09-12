#!/bin/sh
#
# Drop the DHCP lease and deconfigure the Wi-Fi interface.
#
# This one is deliberately synchronous: it is fast (a signal plus a short wait),
# and both callers -- NetworkMgr:turnOffWifi() and obtain-ip.sh -- need the old
# address gone before the next step runs. Leaving a stale address behind is the
# other half of the "connected but nothing works" failure: after switching APs,
# the interface still carries the previous subnet's IP and default route, so
# every packet is routed at the wrong gateway (c.f. hasLeaseForCurrentNetwork()
# in frontend/ui/network/manager.lua).
#
# BusyBox on this rootfs has `killall` and `pidof` but NOT `pkill`/`pgrep`
# (checked against the applet table in the stock /bin/busybox), so this uses
# killall/pidof throughout -- unlike platform/kobo/release-ip.sh, which relies on
# `pkill -0`.
#
# SIGTERM rather than SIGUSR2: the vendor's own reader uses
# `killall -SIGTERM udhcpc` to release (strings on /mnt/app/boordr), and busybox
# udhcpc's SIGTERM path exits cleanly. It does not necessarily run the script's
# `deconfig` case on the way out, though, so the address is cleared explicitly
# below rather than assumed gone.

INTERFACE="${INTERFACE:-wlan0}"

# Save resolv.conf so a client that wipes it on release cannot leave us with an
# empty one (the same #6424 defence kobo's release-ip.sh has). /etc/resolv.conf
# is a symlink to ../tmp/resolv.conf here, i.e. tmpfs, so this is writable even
# though / is mounted read-only.
old_hash=""
if [ -r /etc/resolv.conf ]; then
    cp -f /etc/resolv.conf /tmp/resolv.ko 2>/dev/null
    old_hash="$(md5sum /etc/resolv.conf 2>/dev/null | cut -f1 -d' ')"
fi

killall -TERM udhcpc 2>/dev/null

if [ -x /sbin/dhcpcd ]; then
    # -k releases and waits for the daemon to exit. Harmless if none is running
    # (it just reports "dhcpcd not running"), so no need to probe first.
    /sbin/dhcpcd -k "${INTERFACE}" >/dev/null 2>&1
fi

# BusyBox killall has no --wait, so poll for udhcpc's demise ourselves, for at
# most 5s. `usleep` is a busybox applet here; `sleep` only takes whole seconds.
kill_timeout=0
while pidof udhcpc >/dev/null 2>&1; do
    if [ ${kill_timeout} -ge 20 ]; then
        # Still there: escalate rather than carry on with a client that will
        # fight the next lease.
        killall -KILL udhcpc 2>/dev/null
        break
    fi
    usleep 250000
    kill_timeout=$((kill_timeout + 1))
done

# Clear the address and the default route we may have installed. Both are no-ops
# if the interface is already down or was never configured.
/sbin/ifconfig "${INTERFACE}" 0.0.0.0 2>/dev/null
while /sbin/route del default gw 0.0.0.0 dev "${INTERFACE}" 2>/dev/null; do
    :
done

# Put back the network-specific resolv.conf if the client emptied it on release.
if [ -n "${old_hash}" ] && [ -f /tmp/resolv.ko ]; then
    new_hash="$(md5sum /etc/resolv.conf 2>/dev/null | cut -f1 -d' ')"
    if [ "${new_hash}" != "${old_hash}" ]; then
        cat /tmp/resolv.ko >/etc/resolv.conf 2>/dev/null
    fi
    rm -f /tmp/resolv.ko
fi

exit 0
