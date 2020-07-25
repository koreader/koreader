#!/bin/sh

# Release IP and shutdown udhcpc.
killall udhcpc default.script dhcpcd 2>/dev/null
ifconfig "${INTERFACE}" 0.0.0.0
