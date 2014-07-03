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

# back to nickel
./nickel.sh
