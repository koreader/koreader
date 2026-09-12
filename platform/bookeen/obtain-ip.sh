#!/bin/sh
#
# Acquire a DHCP lease on the Wi-Fi interface, WITHOUT blocking KOReader.
#
# WHY THIS IS ASYNCHRONOUS
#
# NetworkMgr:obtainIP() is called from reconnectOrShowNetworkMenu() on the Lua
# main loop, which is single-threaded: everything -- input, the e-ink refresh
# queue, the "Connecting to Wi-Fi…" InfoMessage that is on screen at that very
# moment -- is stalled for as long as os.execute() has not returned. A DHCP
# discover round takes seconds at best and 15+ seconds on a busy AP, and the
# previous implementation here was a bare `dhcpcd wlan0`, which does not
# daemonize until it has a lease or has timed out. That is precisely the
# "it says Connecting to Wi-Fi and then does nothing" symptom: the UI was frozen
# behind DHCP, and anything that timed out in the meantime (the HTTP request
# that asked for the network in the first place) failed.
#
# Backgrounding is safe because obtainIP() is *not* what decides we are online.
# NetworkMgr:scheduleConnectivityCheck() polls isConnected() -- which for this
# port is ifHasAnAddress(), i.e. operstate == up plus a getifaddrs() address --
# every 250 ms for up to 45 s, and only then broadcasts NetworkConnected. So
# returning immediately and letting the address show up a second later is
# exactly the contract that check was written for.
#
# WHY udhcpc RATHER THAN dhcpcd
#
# Both are on the stock rootfs (/sbin/udhcpc is a busybox symlink, /sbin/dhcpcd
# is dhcpcd 6.9.3), but udhcpc is what the vendor's own reader drives: `strings`
# on /mnt/app/boordr has "/sbin/udhcpc", "%s -i%s -n", "-t%d", "-T%d",
# "killall -SIGUSR1 udhcpc" (renew) and "killall -SIGTERM udhcpc" (release).
# Three concrete reasons to follow it rather than dhcpcd:
#
#   1. / is ext2 mounted read-only in normal operation (/etc/fstab says
#      `rw,noauto`, and the init scripts remount rw only briefly). dhcpcd wants
#      to write /etc/dhcpcd.duid and /var/db/dhcpcd-wlan0.lease; neither is on
#      tmpfs, so every run re-derives its DUID and cannot persist a lease.
#   2. dhcpcd's /libexec/dhcpcd-hooks/10-wpa_supplicant manages wpa_supplicant
#      itself, and on the DEPARTED reason it runs `wpa_cli -iwlan0 terminate` --
#      it will kill the supplicant instance KOReader talks to over
#      /var/run/wpa_supplicant/wlan0. --nohook below neutralizes that on the
#      fallback path.
#   3. udhcpc's script, /usr/share/udhcpc/default.script, is the stock one and
#      does exactly what is needed and nothing else: ifconfig, default route,
#      and rewriting /etc/resolv.conf (a symlink to ../tmp/resolv.conf, so it
#      lands on tmpfs and is writable despite the read-only rootfs).
#
# NOTE: No -q. `-q` exits as soon as the lease is bound, which leaves nothing to
#       renew it: the address stays configured locally while the server's lease
#       quietly expires, and the AP is free to hand it to someone else. Since
#       this port is expected to hold a connection across a long reading
#       session, udhcpc stays resident and renews. It still daemonizes on its
#       own once bound (that is the default without -f), and -b makes it
#       daemonize and keep retrying rather than give up if the first round of
#       discovers goes unanswered.

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
