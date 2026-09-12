#!/bin/sh
#
# Drop the DHCP lease and deconfigure the Wi-Fi interface.

INTERFACE="${INTERFACE:-wlan0}"

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
