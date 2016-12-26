#!/bin/sh

# PATH export is only needed if you run this script manually from a shell
export PATH="${PATH}:/sbin"

# Release IP and shutdown udhcpc.
pkill -9 -f '/bin/sh /etc/udhcpc.d/default.script'
ifconfig "${INTERFACE}" 0.0.0.0
