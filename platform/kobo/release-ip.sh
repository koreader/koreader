#!/bin/sh

# Release IP and shutdown udhcpc.

pkill -9 -f '/bin/sh /etc/udhcpc.d/default.script'
ifconfig eth0 0.0.0.0
