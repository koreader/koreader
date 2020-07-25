#!/bin/sh

echo "[$(date)] release-ip.sh: begin"

# Release IP and shutdown udhcpc.
killall udhcpc default.script dhcpcd 2>/dev/null
usleep 500000

ifconfig "${INTERFACE}" 0.0.0.0
usleep 500000

echo "[$(date)] release-ip.sh: end"
