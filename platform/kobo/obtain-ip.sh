#!/bin/sh

# NOTE: Close any non-standard fds, so that it doesn't come back to bite us in the ass with USBMS (or sockets) later...
for fd in /proc/"$$"/fd/*; do
    close_me="false"
    fd_id="$(basename "${fd}")"
    fd_path="$(readlink -f "${fd}")"

    if [ -e "${fd}" ] && [ "${fd_id}" -gt 2 ]; then
        if [ -S "${fd}" ]; then
            # Close any and all sockets
            # NOTE: Old busybox builds do something stupid when attempting to canonicalize pipes/sockets...
            #       (i.e., they'll spit out ${fd} as-is, losing any and all mention of a socket/pipe).
            fd_path="$(readlink "${fd}")"
            close_me="true"
        elif [ -p "${fd}" ]; then
            # We *might* be catching temporary pipes created by this very test, se we have to leave pipes alone...
            # Although it would take extremely unlucky timing, as by the time we go through the top-level -e test,
            # said temporary pipe is already gone, and as such we *should* never really enter this branch for temporary pipes ;).
            fd_path="$(readlink "${fd}")"
            close_me="false"
        else
            # NOTE: dash (meaning, in turn, busybox's ash) uses fd 10+ open to /dev/tty or $0 (w/ CLOEXEC)
            # NOTE: The last fd != fd_path check is there to (potentially) whitelist non-regular files we might have failed to handle,
            #       it's designed to match the unhelpful result from old buysbox's readlink -f on non-regular files (c.f., previous notes).
            if [ "${fd_path}" != "/dev/tty" ] && [ "${fd_path}" != "$(readlink -f "${0}")" ] && [ "${fd}" != "${fd_path}" ]; then
                close_me="true"
            else
                close_me="false"
            fi
        fi
    fi

    if [ "${fd_id}" -gt 2 ]; then
        if [ "${close_me}" = "true" ]; then
            eval "exec ${fd_id}>&-"
            echo "[obtain-ip.sh] Closed fd ${fd_id} -> ${fd_path}"
        else
            # Try to log something more helpful when old busybox's readlink -f mangled it...
            if [ "${fd}" = "${fd_path}" ]; then
                fd_path="${fd_path} => $(readlink "${fd}")"
                if [ ! -e "${fd}" ]; then
                    # Flag (potentially?) temporary items as such
                    fd_path="${fd_path} (temporary?)"
                fi
            fi
            echo "[obtain-ip.sh] Left fd ${fd_id} -> ${fd_path} open"
        fi
    fi
done

./release-ip.sh

# NOTE: Prefer dhcpcd over udhcpc if available. That's what Nickel uses,
#       and udhcpc appears to trip some insanely wonky corner cases on current FW (#6421)
if [ -x "/sbin/dhcpcd" ]; then
    dhcpcd -d -t 30 -w "${INTERFACE}"
else
    udhcpc -S -i "${INTERFACE}" -s /etc/udhcpc.d/default.script -b -q
fi
