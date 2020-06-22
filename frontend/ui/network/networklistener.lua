local BD = require("ui/bidi")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
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
        -- This is specifically the toggle wifi action, so consent is implied.
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

return NetworkListener
