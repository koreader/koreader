#!/bin/sh
#
# Bookeen resume helper: restore saved networks and request DHCP in the background.

INTERFACE="${INTERFACE:-wlan0}"
WPA_CTRL_DIR="/var/run/wpa_supplicant"
# Use an absolute path because inherited PATH values may omit /usr/sbin.
WPA_CLI="/usr/sbin/wpa_cli"
# /var/run is tmpfs on Bookeen firmware, despite the read-only root filesystem.
PIDFILE="/var/run/restore-wifi-async.pid"

if [ "$1" = "stop" ]; then
    if [ -r "${PIDFILE}" ]; then
        pid="$(cat "${PIDFILE}")"
        # Avoid signalling a recycled PID from a stale pidfile.
        #
        # comm is plain text on the Bookeen BusyBox userspace and is limited to
        # 15 visible characters, hence the truncated process name.
        if grep -q "^restore-wifi-as" "/proc/${pid}/comm" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null
        fi
        rm -f "${PIDFILE}"
    fi
    # Stop helpers that may otherwise bring the Bookeen Wi-Fi module back.
    killall -TERM wlan.sh 2>/dev/null
    killall -TERM wpa_cli 2>/dev/null
    exit 0
fi

RunWpaCli() {
    ./luajit <<EOF
    require("setupkoenv")
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")
    local bin_to_hex = require("ffi/sha2").bin_to_hex

    local settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
    -- Interactive mode accepts the network commands through stdin.
    local cli = io.popen("${WPA_CLI} -p ${WPA_CTRL_DIR} -i ${INTERFACE} > /dev/null", "w")
    if not cli then
        os.exit(1)
    end
    local idx = 0
    for key, network in pairs(settings.data) do
        local ssid = network.ssid or key
        cli:write("add_network\n")
        cli:write("set_network " .. tostring(idx) .. " ssid " .. bin_to_hex(ssid) .. "\n")
        if network.psk then
            -- A saved PMK is already in wpa_supplicant's required format.
            cli:write("set_network " .. tostring(idx) .. " psk " .. network.psk .. "\n")
        elseif network.password and #network.password > 0 then
            cli:write("set_network " .. tostring(idx) .. " psk \"" .. network.password .. "\"\n")
        else
            cli:write("set_network " .. tostring(idx) .. " key_mgmt NONE\n")
        end
        cli:write("enable_network " .. tostring(idx) .. "\n")
        idx = idx + 1
    end
    cli:close()
EOF
}

RestoreWifi() {
    echo "[$(date)] restore-wifi-async.sh: restarting Wi-Fi"

    # On resume the module may still be loaded, so wlan.sh handles both cases.
    ./wlan.sh start

    # wpa_supplicant creates its socket after forking; wait up to 10 seconds.
    ctrl_timeout=0
    while [ ! -e "${WPA_CTRL_DIR}/${INTERFACE}" ]; do
        if [ ${ctrl_timeout} -ge 40 ]; then
            echo "[$(date)] restore-wifi-async.sh: wpa_supplicant control socket never appeared, giving up"
            return 1
        fi
        usleep 250000
        ctrl_timeout=$((ctrl_timeout + 1))
    done

    RunWpaCli

    # obtain-ip.sh starts udhcpc and handles association retries asynchronously.
    ./obtain-ip.sh

    echo "[$(date)] restore-wifi-async.sh: Wi-Fi restart requested"
}

RestoreWifi </dev/null &
echo $! >"${PIDFILE}"

exit 0
