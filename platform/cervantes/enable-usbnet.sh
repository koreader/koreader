#!/bin/sh

# start usbnet using BQ scripts (192.168.4.1/24 w/ hardcoded MAC addr)
/usr/bin/usbup.sh

# start telnet if isn't running
if ! pkill -0 inetd; then
    /usr/sbin/inetd
fi

