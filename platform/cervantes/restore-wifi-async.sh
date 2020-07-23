#!/bin/sh

RunWpaCli() {
    ./luajit <<EOF
    require("setupkoenv")
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")

    local settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
    local cli = io.popen("wpa_cli -g /var/run/wpa_supplicant/eth0 > /dev/null", "w")
    local idx = 0
    for ssid, network in pairs(settings.data) do
        cli:write("add_network\n")
        cli:write("set_network " .. tostring(idx) .. " ssid \"" .. ssid .. "\"\n")
        cli:write("set_network " .. tostring(idx) .. " psk \"" .. network["password"] .. "\"\n")
        cli:write("enable_network " .. tostring(idx) .. "\n")
        idx = idx + 1
    end
    cli:close()
EOF
}

RestoreWifi() {
    echo "[$(date)] restore-wifi-async.sh: Restarting Wi-Fi"
    ./enable-wifi.sh
    RunWpaCli
    ./obtain-ip.sh
    echo "[$(date)] restore-wifi-async.sh: Restarted Wi-Fi"
}

RestoreWifi &
