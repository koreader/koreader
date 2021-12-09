#!/bin/sh

./release-ip.sh

hostname=$(hostname -s)

# Use udhcpc to obtain IP.
udhcpc -S -i eth0 -s /etc/udhcpc/default.script -t15 -T10 -A3 -b -q -F "${hostname}"
