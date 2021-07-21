#!/bin/sh

# NOTE: Close any non-standard fds, so that it doesn't come back to bite us in the ass with USBMS later...
for fd in /proc/"$$"/fd/*; do
    fd_id="$(basename "${fd}")"
    if [ -e "${fd}" ] && [ "${fd_id}" -gt 2 ]; then
        # NOTE: dash (meaning, in turn, busybox's ash, uses fd 10+ open to /dev/tty or $0 (w/ CLOEXEC))
        fd_path="$(readlink -f "${fd}")"
        if [ "${fd_path}" != "/dev/tty" ] && [ "${fd_path}" != "$(readlink -f "${0}")" ] && [ "${fd}" != "${fd_path}" ]; then
            eval "exec ${fd_id}>&-"
            echo "[enable-wifi.sh] Closed fd ${fd_id} -> ${fd_path}"
        fi
    fi
done

# Load wifi modules and enable wifi.
if ! grep -q "sdio_wifi_pwr" "/proc/modules"; then
    if [ -e "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko" ]; then
        # Handle the shitty DVFS switcheroo...
        if [ -n "${CPUFREQ_DVFS}" ]; then
            echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
            echo "1" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
        fi

        insmod "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko"
    fi
fi
# Moar sleep!
usleep 250000
# NOTE: Used to be exported in WIFI_MODULE_PATH before FW 4.23
if ! grep -q "${WIFI_MODULE}" "/proc/modules"; then
    if [ -e "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko" ]; then
        insmod "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko"
    elif [ -e "/drivers/${PLATFORM}/${WIFI_MODULE}.ko" ]; then
        # NOTE: Modules are unsorted on Mk. 8
        insmod "/drivers/${PLATFORM}/${WIFI_MODULE}.ko"
    fi
fi
# Race-y as hell, don't try to optimize this!
sleep 1

ifconfig "${INTERFACE}" up
[ "${WIFI_MODULE}" = "dhd" ] && wlarm_le -i "${INTERFACE}" up

pkill -0 wpa_supplicant ||
    env -u LD_LIBRARY_PATH \
        wpa_supplicant -D wext -s -i "${INTERFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf -O /var/run/wpa_supplicant -B
