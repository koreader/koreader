#!/bin/sh

./release-ip.sh

# NOTE: Prefer dhcpcd over udhcpc if available. That's what Nickel uses,
#       and udhcpc appears to trip some insanely wonky corner cases on current FW (#6421)
if [ -x "/sbin/dhcpcd" ]; then
    env -u LD_LIBRARY_PATH dhcpcd -d -t 30 -w "${INTERFACE}"
else
    env -u LD_LIBRARY_PATH udhcpc -S -i "${INTERFACE}" -s /etc/udhcpc.d/default.script -b -q
fi
