#!/bin/sh
#
# Acquire a DHCP lease on the Wi-Fi interface, WITHOUT blocking KOReader.

INTERFACE="${INTERFACE:-wlan0}"
UDHCPC_SCRIPT="/usr/share/udhcpc/default.script"

# The whole thing, including the release of any previous lease, runs detached.
# stdin is closed so nothing can inherit the terminal; stdout/stderr stay on the
# fds we were called with, which is crash.log (same as cervantes'
# restore-wifi-async.sh).
{
    ./release-ip.sh

    if [ -x /sbin/udhcpc ]; then
        echo "[$(date)] obtain-ip.sh: udhcpc on ${INTERFACE}"
        /sbin/udhcpc -i "${INTERFACE}" -s "${UDHCPC_SCRIPT}" -t 5 -T 3 -A 5 -b -S
    elif [ -x /sbin/dhcpcd ]; then
        # Fallback only. -b so it daemonizes immediately, --nohook wpa_supplicant
        # so it cannot terminate the supplicant KOReader is using (see above).
        echo "[$(date)] obtain-ip.sh: dhcpcd on ${INTERFACE} (udhcpc missing)"
        /sbin/dhcpcd -b -t 30 --nohook wpa_supplicant "${INTERFACE}"
    else
        echo "[$(date)] obtain-ip.sh: no DHCP client found, cannot configure ${INTERFACE}"
    fi
} </dev/null &

exit 0
