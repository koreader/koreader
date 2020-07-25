#!/bin/sh

RestoreWifi() {
    echo "[$(date)] restore-wifi-async.sh: Restarting Wi-Fi"

    ./enable-wifi.sh

    # Much like we do in the UI, ensure wpa_supplicant did its job properly, first.
    # Pilfered from https://github.com/shermp/Kobo-UNCaGED/pull/21 ;)
    wpac_timeout=0
    while ! wpa_cli status | grep -q "wpa_state=COMPLETED"; do
        # If wpa_supplicant hasn't connected within 15 seconds, assume it never will, and tear down Wi-Fi
        if [ ${wpac_timeout} -ge 60 ]; then
            echo "[$(date)] restore-wifi-async.sh: Failed to connect to preferred AP!"
            ./disable-wifi.sh
            return 1
        fi
        usleep 250000
        wpac_timeout=$((wpac_timeout + 1))
    done

    ./obtain-ip.sh

    echo "[$(date)] restore-wifi-async.sh: Restarted Wi-Fi"
}

RestoreWifi &
