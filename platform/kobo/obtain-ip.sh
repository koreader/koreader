#!/bin/sh

echo "[$(date)] obtain-ip.sh: begin"

./release-ip.sh

# Use udhcpc to obtain IP.
#env -u LD_LIBRARY_PATH udhcpc -S -i "${INTERFACE}" -s /etc/udhcpc.d/default.script -t15 -T10 -A3 -b -q
env -u LD_LIBRARY_PATH dhcpcd -d -t 30 -w "${INTERFACE}"
usleep 500000

echo "[$(date)] obtain-ip.sh: end"
