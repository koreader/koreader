#!/bin/sh

# Release IP and shutdown udhcpc.
if [ -x "/sbin/dhcpcd" ]; then
    env -u LD_LIBRARY_PATH dhcpcd -d -k "${INTERFACE}"
    killall udhcpc default.script dhcpcd 2>/dev/null
else
    killall udhcpc default.script dhcpcd 2>/dev/null
    ifconfig "${INTERFACE}" 0.0.0.0
fi
