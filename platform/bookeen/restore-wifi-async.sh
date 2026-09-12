#!/bin/sh
#
# Bring Wi-Fi back up in the background, re-teaching wpa_supplicant the networks
# KOReader knows about, then re-DHCP.
#
# WHY THIS FILE HAD TO EXIST
#
# frontend/device/bookeen/device.lua has always overridden
# NetworkMgr:restoreWifiAsync() with `os.execute("./restore-wifi-async.sh")` --
# but the script was never written, so the call was a silent no-op returning
# exit 127. It went unnoticed because Device:hasWifiRestore() was left at the
# generic `no`, which gates every caller (NetworkMgr:init, NetworkListener's
# onResume, and the "restore Wi-Fi on startup" menu entry). Now that the script
# exists, device.lua sets hasWifiRestore = yes and the override is real.
#
# WHY THE wpa_cli DANCE
#
# wlan.sh starts wpa_supplicant with no -c, i.e. with no configuration file at
# all (there is no /etc/wpa_supplicant.conf on the stock rootfs), so a fresh
# supplicant knows zero networks and will never associate on its own. KOReader's
# saved networks live in its own settings/network.lua, not in the supplicant, and
# the code path that normally feeds them across -- authenticateNetwork() in
# frontend/ui/network/wpa_supplicant.lua -- runs in Lua and is exactly what we
# are trying to avoid blocking on. So this script pushes them in over wpa_cli
# from a throwaway luajit, the same trick platform/cervantes/restore-wifi-async.sh
# uses.
#
# Note this uses `psk` when KOReader has cached one (a 64-hex PMK computed by
# calculatePsk) and falls back to the quoted passphrase otherwise; wpa_supplicant
# accepts both spellings of `psk`, and passing an unquoted 64-hex string is what
# lets us skip a 4096-iteration PBKDF2 on a 1 GHz A8.
#
# The SSID is sent hex-encoded, not quoted -- which is what authenticateNetwork()
# does too (`wcli:setNetwork(nw_id, "ssid", bin_to_hex(network.ssid))`). An SSID is
# 32 arbitrary bytes, so it may legitimately contain a double quote, a backslash or
# a non-UTF-8 sequence, all of which would corrupt or truncate a quoted form.
# Cervantes' version quotes it and is simply wrong for those networks.
#
# NOTE: This whole thing is detached. NetworkMgr:scheduleConnectivityCheck()
#       waits up to 45 s for isConnected(), and that budget was sized for
#       exactly this script on other ports.
#
# CANCELLING IT ("stop")
#
# NetworkMgr:disableWifi() and NetworkMgr:_abortWifiConnection() both try to kill
# a running restore with `pkill -TERM restore-wifi-async.sh` (manager.lua:54 and
# manager.lua:420) -- and neither can work here. BusyBox 1.18.3 on this rootfs has
# no pkill at all, and even `killall restore-wifi-async.sh` would miss: the name is
# 21 characters, so /proc/PID/comm holds the truncated "restore-wifi-as", and
# BusyBox's comm_match() then falls back to comparing argv[1] against the *full*
# name, which does not match the "./restore-wifi-async.sh" a relative invocation
# produces. So without this, tearing down Wi-Fi during a restore would leave the
# script alive to bring it straight back up a moment later.
#
# Hence `restore-wifi-async.sh stop`, called from turnOffWifi() in
# frontend/device/bookeen/device.lua: it kills by pidfile instead of by name.

INTERFACE="${INTERFACE:-wlan0}"
WPA_CTRL_DIR="/var/run/wpa_supplicant"
# Absolute path: /usr/sbin is the directory most likely to be missing from an
# inherited PATH (see the note in wlan.sh).
WPA_CLI="/usr/sbin/wpa_cli"
# /var/run is a symlink to ../tmp, i.e. tmpfs, so this is writable despite the
# read-only rootfs.
PIDFILE="/var/run/restore-wifi-async.pid"

if [ "$1" = "stop" ]; then
    if [ -r "${PIDFILE}" ]; then
        pid="$(cat "${PIDFILE}")"
        # Confirm the pid is still *this* script before signalling it. The
        # pidfile outlives a completed run, and pids are recycled; without this
        # a stale file would eventually get some unrelated process TERMed.
        #
        # /proc/PID/comm rather than /proc/PID/cmdline: comm is plain text with a
        # trailing newline, whereas cmdline is NUL-separated, and BusyBox grep has
        # no -a. The name is compared truncated to 15 characters because that is
        # all comm holds (TASK_COMM_LEN 16).
        if grep -q "^restore-wifi-as" "/proc/${pid}/comm" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null
        fi
        rm -f "${PIDFILE}"
    fi
    # Killing the shell does not reap whatever child it was blocked on, and a
    # surviving `wlan.sh start` would insmod the module back in behind the
    # caller's `wlan.sh stop`. Both of these have short enough names that their
    # comm is not truncated, so BusyBox killall does match them by name.
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
    -- No command arguments: wpa_cli drops into interactive mode and reads
    -- commands from stdin with fgets(), which is what makes piping work.
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
            -- Precomputed 32-byte PMK, passed unquoted.
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

    # wlan.sh insmods 8188eu, brings the interface up and starts wpa_supplicant.
    # It returns 0 early if the interface is already up, which is what we want on
    # a resume where the module survived.
    ./wlan.sh start

    # wpa_supplicant -B forks before its control socket exists, so wait for the
    # socket rather than sleeping a fixed amount. 10s at 250ms.
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

    # Association takes a moment; obtain-ip.sh backgrounds itself and udhcpc
    # retries, so there is no need to poll wpa_state here -- and NetworkMgr's
    # connectivity check is watching operstate/getifaddrs anyway.
    ./obtain-ip.sh

    echo "[$(date)] restore-wifi-async.sh: Wi-Fi restart requested"
}

RestoreWifi </dev/null &
echo $! >"${PIDFILE}"

exit 0
