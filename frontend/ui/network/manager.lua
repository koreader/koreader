local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local NetworkMgr = {}

function NetworkMgr:readNWSettings()
    self.nw_settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
end

function NetworkMgr:init()
    self.wifi_was_on = G_reader_settings:isTrue("wifi_was_on")
    if self.wifi_was_on and G_reader_settings:nilOrTrue("auto_restore_wifi") then
        self:restoreWifiAsync()
    end
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
-- This function should unblockly call both turnOnWifi() and obtainIP().
function NetworkMgr:restoreWifiAsync() end
-- End of device specific methods

function NetworkMgr:promptWifiOn(complete_callback)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn on Wi-Fi?"),
        ok_text = _("Turn on"),
        ok_callback = function()
            self.wifi_was_on = true
            G_reader_settings:saveSetting("wifi_was_on", true)
            self:turnOnWifi(complete_callback)
        end,
    })
end

function NetworkMgr:promptWifiOff(complete_callback)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn off Wi-Fi?"),
        ok_text = _("Turn off"),
        ok_callback = function()
            self.wifi_was_on = false
            G_reader_settings:saveSetting("wifi_was_on", false)
            self:turnOffWifi(complete_callback)
        end,
    })
end

function NetworkMgr:isOnline()
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
        checked_func = function() return NetworkMgr:isOnline() end,
        callback = function(menu)
            local wifi_status = NetworkMgr:isOnline()
            local complete_callback = function()
                -- notify touch menu to update item check state
                menu:updateItems()
                local Event = require("ui/event")
                -- if wifi was on, this callback will only be executed when the network has been
                -- disconnected.
                if wifi_status then
                    UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
                else
                    UIManager:broadcastEvent(Event:new("NetworkConnected"))
                end
            end
            if wifi_status then
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

function NetworkMgr:getRestoreMenuTable()
    return {
        text = _("Automatically restore Wi-Fi connection after resume"),
        checked_func = function() return G_reader_settings:nilOrTrue("auto_restore_wifi") end,
        enabled_func = function() return Device:isKobo() end,
        callback = function(menu) G_reader_settings:flipNilOrTrue("auto_restore_wifi") end,
    }
end

function NetworkMgr:getInfoMenuTable()
    return {
        text = _("Network info"),
        -- TODO: also show network info when device is authenticated to router but offline
        enabled_func = function() return self:isOnline() end,
        callback = function(menu)
            if Device.retrieveNetworkInfo then
                UIManager:show(InfoMessage:new{
                    text = Device:retrieveNetworkInfo(),
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Could not retrieve network info."),
                    timeout = 3,
                })
            end
        end
    }
end

function NetworkMgr:getMenuTable()
    return {
        self:getWifiMenuTable(),
        self:getProxyMenuTable(),
        self:getRestoreMenuTable(),
        self:getInfoMenuTable(),
    }
end

function NetworkMgr:showNetworkMenu(complete_callback)
    local info = InfoMessage:new{text = _("Scanning…")}
    UIManager:show(info)
    UIManager:nextTick(function()
        local network_list, err = self:getNetworkList()
        UIManager:close(info)
        if network_list == nil then
            UIManager:show(InfoMessage:new{text = err})
            return
        end
        UIManager:show(require("ui/widget/networksetting"):new{
            network_list = network_list,
            connect_callback = complete_callback,
        })
    end)
end

function NetworkMgr:saveNetwork(setting)
    if not self.nw_settings then self:readNWSettings() end

    self.nw_settings:saveSetting(setting.ssid, {
        ssid = setting.ssid,
        password = setting.password,
        psk = setting.psk,
        flags = setting.flags,
    })
    self.nw_settings:flush()
end

function NetworkMgr:deleteNetwork(setting)
    if not self.nw_settings then self:readNWSettings() end
    self.nw_settings:delSetting(setting.ssid)
    self.nw_settings:flush()
end

function NetworkMgr:getAllSavedNetworks()
    if not self.nw_settings then self:readNWSettings() end
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
NetworkMgr:init()

return NetworkMgr
