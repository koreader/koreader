#!/bin/sh

# Release IP and shutdown udhcpc.
# NOTE: Trying to do this nicely with 'dhcpcd -d -k "${INTERFACE}"' trips mysterious buggy corner-cases... (#6424)
killall udhcpc default.script dhcpcd 2>/dev/null
ifconfig "${INTERFACE}" 0.0.0.0
