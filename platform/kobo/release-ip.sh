#!/bin/sh

# Release IP and shutdown udhcpc.
# NOTE: Save our resolv.conf to avoid ending up with an empty one, in case the DHCP client wipes it on release (#6424).
cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
if [ -x "/sbin/dhcpcd" ]; then
    env -u LD_LIBRARY_PATH dhcpcd -d -k "${INTERFACE}"
    killall -q -TERM udhcpc default.script
else
    killall -q -TERM udhcpc default.script dhcpcd
    ifconfig "${INTERFACE}" 0.0.0.0
fi
mv -f "/tmp/resolv.ko" "/etc/resolv.conf"
