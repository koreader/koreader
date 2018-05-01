#!/bin/sh

./release-ip.sh

# Use udhcpc to obtain IP.
env -u LD_LIBRARY_PATH udhcpc -S -i "${INTERFACE}" -s /etc/udhcpc.d/default.script -t15 -T10 -A3 -b -q
