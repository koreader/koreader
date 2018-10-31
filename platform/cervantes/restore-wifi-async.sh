#!/bin/sh

RestoreWifi() {
    echo "[$(date)] restore-wifi-async.sh: Restarting WiFi"
    ./enable-wifi.sh
    ./obtain-ip.sh
    echo "[$(date)] restore-wifi-async.sh: Restarted WiFi"
}

RestoreWifi &
