#!/bin/sh

# turn down network interface
ifconfig usb0 down

# disable telnet if running
pkill -0 inetd && kill -9 "$(pidof inetd)"

# unload usbnet modules
modprobe -r g_ether
sleep 1
