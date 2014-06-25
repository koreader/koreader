#!/bin/sh
export LC_ALL="en_US.UTF-8"

# we're always starting from our working directory
cd /mnt/onboard/.kobo/koreader/

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# accept input ports for zsync plugin
iptables -A INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

# exit from nickel
killall nickel
killall hindenburg

# finally call the launcher
./reader.lua /mnt/onboard 2> crash.log

# restore firewall rules
iptables -D INPUT -i wlan0 -p udp --dport 5670 -j ACCEPT
iptables -D INPUT -i wlan0 -p tcp --dport 49152:49162 -j ACCEPT

# back to nickel again :)
( usleep 400000; /etc/init.d/on-animator.sh ) &
(
/usr/local/Kobo/pickel disable.rtc.alarm
if [ ! -e /etc/wpa_supplicant/wpa_supplicant.conf ]; then
  cp /etc/wpa_supplicant/wpa_supplicant.conf.template /etc/wpa_supplicant/wpa_supplicant.conf
fi

echo 1 > /sys/devices/platform/mxc_dvfs_core.0/enable
/sbin/hwclock -s -u
) &

export QWS_MOUSE_PROTO="tslib_nocal:/dev/input/event1"
export QWS_KEYBOARD=imx508kbd:/dev/input/event0
export QWS_DISPLAY=Transformed:imx508:Rot90
export NICKEL_HOME=/mnt/onboard/.kobo
export LD_LIBRARY_PATH=/usr/local/Kobo

/usr/local/Kobo/hindenburg &
/usr/local/Kobo/nickel -qws -skipFontLoad

