#!/bin/sh

# PATH export is only needed if you run this script manually from a shell
export PATH="${PATH}:/sbin"

# Release IP and shutdown udhcpc.
killall udhcpc default.script 2>/dev/null
ifconfig "${INTERFACE}" 0.0.0.0
