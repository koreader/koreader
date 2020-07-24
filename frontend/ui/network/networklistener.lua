local BD = require("ui/bidi")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local NetworkListener = InputContainer:new{}

function NetworkListener:onToggleWifi()
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("Turning on Wi-Fi…"),
            timeout = 1,
        })

        -- NB Normal widgets should use NetworkMgr:promptWifiOn()
        -- This is specifically the toggle Wi-Fi action, so consent is implied.
        NetworkMgr:turnOnWifi()
    else
        NetworkMgr:turnOffWifi()

        UIManager:show(InfoMessage:new{
            text = _("Wi-Fi off."),
            timeout = 1,
        })
    end
end

function NetworkListener:onInfoWifiOff()
    -- can't hurt
    NetworkMgr:turnOffWifi()

    UIManager:show(InfoMessage:new{
        text = _("Wi-Fi off."),
        timeout = 1,
    })
end

function NetworkListener:onInfoWifiOn()
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("Enabling wifi…"),
            timeout = 1,
        })

        -- NB Normal widgets should use NetworkMgr:promptWifiOn()
        -- This is specifically the toggle Wi-Fi action, so consent is implied.
        NetworkMgr:turnOnWifi()
    else
        local info_text
        local current_network = NetworkMgr:getCurrentNetwork()
        -- this method is only available for some implementations
        if current_network and current_network.ssid then
            info_text = T(_("Already connected to network %1."), BD.wrap(current_network.ssid))
        else
            info_text = _("Already connected.")
        end
        UIManager:show(InfoMessage:new{
            text = info_text,
            timeout = 1,
        })
    end
end

-- Everything below is to handle auto_disable_wifi ;).
local default_network_timeout_seconds = 5*60
local max_network_timeout_seconds = 30*60
-- This should be more than enough to catch actual activity vs. noise spread over half an hour.
local network_activity_noise_margin = 64

-- Read the statistics/tx_packets sysfs entry for the current network interface.
-- It *should* be the least noisy entry on an idle network...
-- The fact that auto_disable_wifi is only available on (Device:hasWifiManager() and not Device:isEmulator())
-- allows us to get away with a Linux-only solution.
function NetworkListener:_getTxPackets()
    -- read tx_packets stats from sysfs (for the right network if)
    local file = io.open("/sys/class/net/" .. NetworkMgr:getNetworkInterfaceName() .. "/statistics/tx_packets", "rb")

    -- file exists only when Wi-Fi module is loaded.
    if not file then return nil end

    local out = file:read("*all")
    file:close()

    -- strip NaN from file read (i.e.,: line endings, error messages)
    local tx_packets
    if type(out) ~= "number" then
        tx_packets = tonumber(out)
    else
        tx_packets = out
    end

    -- finally return it
    if type(tx_packets) == "number" then
        return tx_packets
    else
        return nil
    end
end

function NetworkListener:_unscheduleActivityCheck()
    logger.dbg("NetworkListener: unschedule network activity check")
    UIManager:unschedule(self._scheduleActivityCheck)
    self._activity_check_scheduled = nil
end

function NetworkListener:_scheduleActivityCheck()
    logger.dbg("NetworkListener: schedule network activity check")
    local keep_checking = true

    local tx_packets = NetworkListener:_getTxPackets()
    if self._last_tx_packets then
        -- If there was no meaningful activity (+/- a couple packets), kill the Wi-Fi
        if math.max(0, tx_packets - network_activity_noise_margin) <= self._last_tx_packets then
            logger.dbg("NetworkListener: No meaningful network activity ( then:", self._last_tx_packets, "vs. now:", tx_packets, "), disabling Wi-Fi")
            keep_checking = false
            local complete_callback = function()
                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
            end
            NetworkMgr:turnOffWifi(complete_callback)
            -- NOTE: We leave wifi_was_on as-is on purpose, we wouldn't want to break auto_restore_wifi workflows on the next start...
        end
    end
    -- Update tracker for next iter
    self._last_tx_packets = tx_packets

    -- If we've just killed Wi-Fi, onNetworkDisconnected will take care of unscheuling us
    if keep_checking then
        -- If it's already been scheduled, double the delay until we hit the ceiling
        if self._activity_check_delay then
            self._activity_check_delay = self._activity_check_delay * 2

            if self._activity_check_delay > max_network_timeout_seconds then
                self._activity_check_delay = max_network_timeout_seconds
            end
        else
            self._activity_check_delay = default_network_timeout_seconds
        end

        UIManager:scheduleIn(self._activity_check_delay, self._scheduleActivityCheck, self)
        self._activity_check_scheduled = true
    end
end


function NetworkListener:onNetworkConnected()
    if not (Device:hasWifiManager() and not Device:isEmulator()) then
        return
    end

    if not G_reader_settings:isTrue("auto_disable_wifi") then
        return
    end

    print("NetworkListener:onNetworkConnected")
    print("NetworkMgr:getNetworkInterfaceName:", NetworkMgr:getNetworkInterfaceName())
    print("NetworkListener:_getTxPackets:", NetworkListener:_getTxPackets())

    -- If the activity check has already been scheduled for some reason, unschedule it.
    if self._activity_check_scheduled then
        NetworkListener:_unscheduleActivityCheck()
    end

    NetworkListener:_scheduleActivityCheck()
end

function NetworkListener:onNetworkDisconnected()
    if not (Device:hasWifiManager() and not Device:isEmulator()) then
        return
    end

    if not G_reader_settings:isTrue("auto_disable_wifi") then
        return
    end

    print("NetworkListener:onNetworkDisconnected")
    NetworkListener:_unscheduleActivityCheck()
end

-- Also unschedule on suspend
function NetworkListener:onSuspend()
    self:onNetworkDisconnected()
end


return NetworkListener
