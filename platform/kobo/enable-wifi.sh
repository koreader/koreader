#!/bin/sh

# NOTE: Close any non-standard fds, so that it doesn't come back to bite us in the ass with USBMS later...
for fd in $(ls /proc/$$/fd); do
    if [ "${fd}" -gt 2 ]; then
        # NOTE: dash (meaning, in turn, busybox's ash, may also have fd 10 open to /dev/tty)
        fd_path="$(readlink -f /proc/$$/fd/10)"
        if [ "${fd_path}" != "/dev/tty" ]; then
            eval "exec ${fd}>&-"
            echo "[enable-wifi.sh] Closed fd ${fd} -> ${fd_path}"
        fi
    fi
done

# Load wifi modules and enable wifi.
lsmod | grep -q sdio_wifi_pwr || insmod "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko"
# Moar sleep!
usleep 250000
# NOTE: Used to be exported in WIFI_MODULE_PATH before FW 4.23
lsmod | grep -q "${WIFI_MODULE}" || insmod "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko"
# Race-y as hell, don't try to optimize this!
sleep 1

ifconfig "${INTERFACE}" up
[ "${WIFI_MODULE}" != "8189fs" ] && [ "${WIFI_MODULE}" != "8192es" ] && wlarm_le -i "${INTERFACE}" up

pkill -0 wpa_supplicant ||
    env -u LD_LIBRARY_PATH \
        wpa_supplicant -D wext -s -i "${INTERFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf -O /var/run/wpa_supplicant -B
