local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Device = require("device")
local T = require("ffi/util").template
local _ = require("gettext")


local NetworkMgr = {}

function NetworkMgr:init()
    self.nw_settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
end

-- Following methods are Device specific which need to be initialized in
-- Device:initNetworkManager. Some of them can be set by calling
-- NetworkMgr:setWirelessBackend
function NetworkMgr:turnOnWifi() end
function NetworkMgr:turnOffWifi() end
function NetworkMgr:getNetworkList() end
function NetworkMgr:getCurrentNetwork() end
function NetworkMgr:authenticateNetwork() end
function NetworkMgr:disconnectNetwork() end
function NetworkMgr:obtainIP() end
function NetworkMgr:releaseIP() end
-- End of device specific methods

function NetworkMgr:promptWifiOn(complete_callback)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn on Wi-Fi?"),
        ok_callback = function()
            self:turnOnWifi(complete_callback)
        end,
    })
end

function NetworkMgr:promptWifiOff(complete_callback)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn off Wi-Fi?"),
        ok_callback = function()
            self:turnOffWifi(complete_callback)
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
        callback = function(menu)
            local complete_callback = function()
                -- notify touch menu to update item check state
                menu:updateItems()
            end
            if NetworkMgr:getWifiStatus() then
                NetworkMgr:promptWifiOff(complete_callback)
            else
                NetworkMgr:promptWifiOn(complete_callback)
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

function NetworkMgr:getInfoMenuTable()
    return {
        text = _("Retrieve network info"),
        callback = function(menu)
            if Device.retrieveNetworkInfo then
                UIManager:show(KeyValuePage:new{
                    title = _("Network Info"),
                    kv_pairs = Device:retrieveNetworkInfo(),
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Cannot retrieve network info"),
                    timeout = 3,
                })
            end
        end
    }
end

function NetworkMgr:showNetworkMenu(complete_callback)
    local info = InfoMessage:new{text = _("Scanning…")}
    UIManager:show(info)
    UIManager:nextTick(function()
        local network_list = self:getNetworkList()
        UIManager:close(info)
        UIManager:show(require("ui/widget/networksetting"):new{
            network_list = network_list,
            connect_callback = complete_callback,
        })
    end)
end

function NetworkMgr:saveNetwork(setting)
    if not self.nw_settings then self:init() end
    self.nw_settings:saveSetting(setting.ssid, {
        ssid = setting.ssid,
        password = setting.password,
        flags = setting.flags,
    })
    self.nw_settings:flush()
end

function NetworkMgr:deleteNetwork(setting)
    if not self.nw_settings then self:init() end
    self.nw_settings:delSetting(setting.ssid)
    self.nw_settings:flush()
end

function NetworkMgr:getAllSavedNetworks()
    if not self.nw_settings then self:init() end
    return self.nw_settings
end

function NetworkMgr:setWirelessBackend(name, options)
    require("ui/network/"..name).init(self, options)
end

-- set network proxy if global variable NETWORK_PROXY is defined
if NETWORK_PROXY then
    NetworkMgr:setHTTPProxy(NETWORK_PROXY)
end

Device:initNetworkManager(NetworkMgr)

return NetworkMgr
