local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Device = require("device")
local T = require("ffi/util").template
local _ = require("gettext")


local NetworkMgr = {}

-- Device specific method, needs to be initialized in Device:initNetworkManager
function NetworkMgr:turnOnWifi() end

-- Device specific method, needs to be initialized in Device:initNetworkManager
function NetworkMgr:turnOffWifi() end

function NetworkMgr:promptWifiOn()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn on Wi-Fi?"),
        ok_callback = function()
            self:turnOnWifi()
        end,
    })
end

function NetworkMgr:promptWifiOff()
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn off Wi-Fi?"),
        ok_callback = function()
            self:turnOffWifi()
        end,
    })
end

function NetworkMgr:getWifiStatus()
    local socket = require("socket")
    return socket.dns.toip("www.example.com") ~= nil
end

function NetworkMgr:setHTTPProxy(proxy)
    local http = require("socket.http")
    http.PROXY = proxy
    if proxy then
        G_reader_settings:saveSetting("http_proxy", proxy)
        G_reader_settings:saveSetting("http_proxy_enabled", true)
    else
        G_reader_settings:saveSetting("http_proxy_enabled", false)
    end
end

function NetworkMgr:getWifiMenuTable()
    return {
        text = _("Wi-Fi connection"),
        enabled_func = function() return Device:isKindle() or Device:isKobo() end,
        checked_func = function() return NetworkMgr:getWifiStatus() end,
        callback = function()
            if NetworkMgr:getWifiStatus() then
                NetworkMgr:promptWifiOff()
            else
                NetworkMgr:promptWifiOn()
            end
        end
    }
end

function NetworkMgr:getProxyMenuTable()
    local proxy_enabled = function()
        return G_reader_settings:readSetting("http_proxy_enabled")
    end
    local proxy = function()
        return G_reader_settings:readSetting("http_proxy")
    end
    return {
        text_func = function()
            return T(_("HTTP proxy %1"), (proxy_enabled() and proxy() or ""))
        end,
        checked_func = function() return proxy_enabled() end,
        callback = function()
            if not proxy_enabled() and proxy() then
                NetworkMgr:setHTTPProxy(proxy())
            elseif proxy_enabled() then
                NetworkMgr:setHTTPProxy(nil)
            end
            if not proxy() then
                UIManager:show(InfoMessage:new{
                    text = _("Tip:\nLong press on this menu entry to configure HTTP proxy."),
                })
            end
        end,
        hold_input = {
            title = _("Enter proxy address"),
            type = "text",
            hint = proxy() or "",
            callback = function(input)
                if input ~= "" then
                    NetworkMgr:setHTTPProxy(input)
                end
            end,
        }
    }
end

-- set network proxy if global variable NETWORK_PROXY is defined
if NETWORK_PROXY then
    NetworkMgr:setHTTPProxy(NETWORK_PROXY)
end

Device:initNetworkManager(NetworkMgr)

return NetworkMgr
