#!/bin/sh

RestoreWifi() {
    ./enable-wifi.sh
    ./obtain-ip.sh
    echo "[$(date)] Kobo Suspend: Restarted WiFi"
}

RestoreWifi &
