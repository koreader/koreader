#!/bin/sh
#
# Wi-Fi up/down for Bookeen Cybook devices.

IFACE=wlan0
WLAN_MODULE=/lib/modules/3.0.8+/8188eu.ko
IFCONFIG=/sbin/ifconfig
INSMOD=/sbin/insmod
LSMOD=/sbin/lsmod
RMMOD=/sbin/rmmod
# Use absolute paths because KOReader may inherit a limited PATH.
WPA_SUPPLICANT=/usr/sbin/wpa_supplicant
WPA_CLI=/usr/sbin/wpa_cli
WPA_CTRL_DIR=/var/run/wpa_supplicant

# Disable leisure power save in the Bookeen 8188eu driver. This must be set when
# the module loads because the driver copies the value during initialization.
WLAN_MODULE_PARAMS='rtw_power_mgnt=0'

# shellcheck disable=SC2329
wlan_loaded() {
    "${LSMOD}" | grep -q '^8188eu '
}

# Start wpa_supplicant and wait for the Bookeen control socket.
# shellcheck disable=SC2329
start_supplicant() {
    if [ ! -e "${WPA_CTRL_DIR}/${IFACE}" ]; then
        # Bookeen has no wpa_supplicant.conf; KOReader supplies networks later.
        "${WPA_SUPPLICANT}" -B -D wext -i "${IFACE}" -C "${WPA_CTRL_DIR}"
    fi

    # Wait up to 10 seconds; Bookeen BusyBox sleep has only whole-second waits.
    ctrl_timeout=0
    while [ ! -e "${WPA_CTRL_DIR}/${IFACE}" ]; do
        if [ "${ctrl_timeout}" -ge 40 ]; then
            echo "$0: wpa_supplicant control socket ${WPA_CTRL_DIR}/${IFACE} never appeared" 1>&2
            return 1
        fi
        usleep 250000
        ctrl_timeout=$((ctrl_timeout + 1))
    done

    return 0
}

# shellcheck disable=SC2329
wlan_start() {
    echo "Loading WLAN driver"

    # Check if wlan driver is already up.
    if "${IFCONFIG}" | grep -q "^${IFACE}:"; then
        # The interface may survive suspend while wpa_supplicant does not.
        start_supplicant
        return $?
    fi

    # Reload a leftover module so WLAN_MODULE_PARAMS is applied on Bookeen.
    if wlan_loaded; then
        echo "$0: 8188eu loaded but ${IFACE} is down, reloading for parameters"
        "${RMMOD}" 8188eu
    fi

    if [ ! -f "${WLAN_MODULE}" ]; then
        return 1
    fi

    if MAC_ADDR="$(/sbin/nvram -e)"; then
        MAC_ADDR="${MAC_ADDR#*=}"
    else
        MAC_ADDR="90:D7:4F:42:42:42"
        echo "$0: error reading MAC address from nvram, using ${MAC_ADDR} default" 1>&2
    fi

    # shellcheck disable=SC2086
    "${INSMOD}" "${WLAN_MODULE}" rtw_initmac="${MAC_ADDR}" ${WLAN_MODULE_PARAMS}

    sleep 1

    wlan_loaded || return 2
    "${IFCONFIG}" "${IFACE}" up
    start_supplicant

    return $?
}

# shellcheck disable=SC2329
wlan_suspend() {
    power s 8188eu
}

# shellcheck disable=SC2329
wlan_resume() {
    power 1 8188eu
}

# shellcheck disable=SC2329
wlan_stop() {
    echo "Unloading WLAN driver"
    wlan_loaded || return 1
    # The Bookeen control socket lives under the temporary runtime directory.
    "${WPA_CLI}" -p "${WPA_CTRL_DIR}" -i "${IFACE}" terminate
    "${IFCONFIG}" "${IFACE}" down
    "${RMMOD}" 8188eu
    return 0
}

# shellcheck disable=SC2329
wlan_restart() {
    stop
    start
}

case "$1" in
    start | stop | suspend | resume | restart) "wlan_$1" ;;
    *)
        echo "Usage: $0 {start|stop|suspend|resume|restart}"
        exit 1
        ;;
esac

# Propagate the action's status. The vendor script always exited 0, which hid
# every failure above from NetworkMgr.
exit $?
