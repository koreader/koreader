local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = ffiutil.template

local NetworkMgr = {}

function NetworkMgr:readNWSettings()
    self.nw_settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
end

-- Used after restoreWifiAsync() to make sure we eventually send a NetworkConnected event, as a few things rely on it (KOSync, c.f. #5109).
function NetworkMgr:connectivityCheck(iter)
    -- Give up after a while...
    if iter > 6 then
        return
    end

    if NetworkMgr:isWifiOn() and NetworkMgr:isConnected() then
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("NetworkConnected"))
        logger.info("WiFi successfully restored!")
    else
        UIManager:scheduleIn(2, function() NetworkMgr:connectivityCheck(iter + 1) end)
    end
end

function NetworkMgr:scheduleConnectivityCheck()
    UIManager:scheduleIn(2, function() NetworkMgr:connectivityCheck(1) end)
end

function NetworkMgr:init()
    -- On Kobo, kill WiFi if NetworkMgr:isWifiOn() and NOT NetworkMgr:isConnected()
    -- (i.e., if the launcher left the WiFi in an inconsistent state: modules loaded, but no route to gateway).
    if Device:isKobo() and self:isWifiOn() and not self:isConnected() then
        logger.info("Kobo WiFi: Left in an inconsistent state by launcher!")
        self:turnOffWifi()
    end

    self.wifi_was_on = G_reader_settings:isTrue("wifi_was_on")
    if self.wifi_was_on and G_reader_settings:isTrue("auto_restore_wifi") then
        self:restoreWifiAsync()
        self:scheduleConnectivityCheck()
    end
end

-- Following methods are Device specific which need to be initialized in
-- Device:initNetworkManager. Some of them can be set by calling
-- NetworkMgr:setWirelessBackend
function NetworkMgr:turnOnWifi() end
function NetworkMgr:turnOffWifi() end
function NetworkMgr:isWifiOn() end
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

function NetworkMgr:turnOnWifiAndWaitForConnection(callback)
    NetworkMgr:turnOnWifi()
    local timeout = 30
    local retry_count = 0
    local info = InfoMessage:new{ text = T(_("Enabling Wi-Fi. Waiting for Internet connection…\nTimeout %1 seconds."), timeout)}
    UIManager:show(info)
    UIManager:forceRePaint()
    while not NetworkMgr:isOnline() and retry_count < timeout do
        ffiutil.sleep(1)
        retry_count = retry_count + 1
    end
    UIManager:close(info)
    if retry_count == timeout then
        UIManager:show(InfoMessage:new{ text = _("Error connecting to the network") })
        return
    end
    if callback then callback() end
end

function NetworkMgr:beforeWifiAction(callback)
    local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action")
    if wifi_enable_action == "turn_on" then
        NetworkMgr:turnOnWifiAndWaitForConnection(callback)
    else
        NetworkMgr:promptWifiOn(callback)
    end
 end

function NetworkMgr:isConnected()
    if Device:isAndroid() or Device:isCervantes() or Device:isPocketBook() or Device:isEmulator() then
        return self:isWifiOn()
    else
        -- Pull the default gateway first, so we don't even try to ping anything if there isn't one...
        local default_gw
        local std_out = io.popen([[/sbin/route -n | awk '$4 == "UG" {print $2}' | tail -n 1]], "r")
        if std_out then
            default_gw = std_out:read("*all")
            std_out:close()
            if not default_gw or default_gw == "" then
                return false
            end
        end

        -- `-c1` try only once; `-w2` wait 2 seconds
        -- NOTE: No -w flag available in the old busybox build used on Legacy Kindles...
        if Device:isKindle() and Device:hasKeyboard() then
            return 0 == os.execute("ping -c1 " .. default_gw)
        else
            return 0 == os.execute("ping -c1 -w2 " .. default_gw)
        end
    end
end

function NetworkMgr:isOnline()
    local socket = require("socket")
    -- Microsoft uses `dns.msftncsi.com` for Windows, see
    -- <https://technet.microsoft.com/en-us/library/ee126135#BKMK_How> for
    -- more information. They also check whether <http://www.msftncsi.com/ncsi.txt>
    -- returns `Microsoft NCSI`.
    return socket.dns.toip("dns.msftncsi.com") ~= nil
end

function NetworkMgr:isNetworkInfoAvailable()
    if Device:isAndroid() then
        -- always available
        return true
    else
        --- @todo also show network info when device is authenticated to router but offline
        return self:isWifiOn()
    end
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
    if Device:isAndroid() then
        return {
            text = _("Wi-Fi settings"),
            enabled_func = function() return true end,
            callback = function() NetworkMgr:openSettings() end,
        }
    else
        return self:getWifiToggleMenuTable()
    end
end

function NetworkMgr:getWifiToggleMenuTable()
    return {
        text = _("Wi-Fi connection"),
        enabled_func = function() return Device:hasWifiToggle() end,
        checked_func = function() return NetworkMgr:isWifiOn() end,
        callback = function(touchmenu_instance)
            local wifi_status = NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
            local complete_callback = function()
                -- notify touch menu to update item check state
                touchmenu_instance:updateItems()
                local Event = require("ui/event")
                -- if wifi was on, this callback will only be executed when the network has been
                -- disconnected.
                if wifi_status then
                    UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
                else
                    -- On hasWifiManager devices that play with kernel modules directly,
                    -- double-check that the connection attempt was actually successful...
                    if Device:isKobo() or Device:isCervantes() then
                        if NetworkMgr:isWifiOn() and NetworkMgr:isConnected() then
                            UIManager:broadcastEvent(Event:new("NetworkConnected"))
                        elseif NetworkMgr:isWifiOn() and not NetworkMgr:isConnected() then
                            -- Don't leave WiFi in an inconsistent state if the connection failed.
                            self.wifi_was_on = false
                            G_reader_settings:saveSetting("wifi_was_on", false)
                            -- NOTE: We're limiting this to only a few platforms, as it might be actually harmful on some devices.
                            --       The intent being to unload kernel modules, and make a subsequent turnOnWifi behave sanely.
                            --       PB: Relies on netagent, no idea what it does, but it's not using this codepath anyway (!hasWifiToggle)
                            --       Android: Definitely shouldn't do it.
                            --       Sony: Doesn't play with modules, don't do it.
                            --       Kobo: Yes, please.
                            --       Cervantes: Loads/unloads module, probably could use it like Kobo.
                            --       Kindle: Probably could use it, if only because leaving Wireless on is generally a terrible idea on Kindle,
                            --               except that we defer to lipc, which makes WiFi handling asynchronous, and the callback is simply delayed by 1s,
                            --               so we can't be sure the system will actually have finished bringing WiFi up by then...
                            NetworkMgr:turnOffWifi()
                            touchmenu_instance:updateItems()
                        end
                    else
                        -- Assume success on other platforms
                        UIManager:broadcastEvent(Event:new("NetworkConnected"))
                    end
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
            return T(_("HTTP proxy %1"), (proxy_enabled() and BD.url(proxy()) or ""))
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
        checked_func = function() return G_reader_settings:isTrue("auto_restore_wifi") end,
        enabled_func = function() return Device:hasWifiManager() and not Device:isEmulator() end,
        callback = function() G_reader_settings:flipNilOrFalse("auto_restore_wifi") end,
    }
end

function NetworkMgr:getInfoMenuTable()
    return {
        text = _("Network info"),
        keep_menu_open = true,
        enabled_func = function() return self:isNetworkInfoAvailable() end,
        callback = function()
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

function NetworkMgr:getBeforeWifiActionMenuTable()
   local wifi_enable_action_setting = G_reader_settings:readSetting("wifi_enable_action") or "prompt"
   local wifi_enable_actions = {
       turn_on = {_("turn on"), _("Turn on (experimental)")},
       prompt = {_("prompt"), _("Prompt")},
   }
   local action_table = function(wifi_enable_action)
       return {
           text = wifi_enable_actions[wifi_enable_action][2],
           checked_func = function()
               return wifi_enable_action_setting == wifi_enable_action
           end,
           callback = function()
               wifi_enable_action_setting = wifi_enable_action
               G_reader_settings:saveSetting("wifi_enable_action", wifi_enable_action)
           end,
       }
   end
   return {
       text_func = function()
           return T(_("Action when Wi-Fi is off: %1"),
               wifi_enable_actions[wifi_enable_action_setting][1]
           )
       end,
       sub_item_table = {
           action_table("turn_on"),
           action_table("prompt"),
       }
   }
end

function NetworkMgr:getDismissScanMenuTable()
    return {
        text = _("Dismiss Wi-Fi scan popup after connection"),
        checked_func = function() return G_reader_settings:nilOrTrue("auto_dismiss_wifi_scan") end,
        enabled_func = function() return Device:hasWifiManager() and not Device:isEmulator() end,
        callback = function() G_reader_settings:flipNilOrTrue("auto_dismiss_wifi_scan") end,
    }
end

function NetworkMgr:getMenuTable(common_settings)
    if Device:hasWifiToggle() then
        common_settings.network_wifi = self:getWifiMenuTable()
    end

    common_settings.network_proxy = self:getProxyMenuTable()
    common_settings.network_info = self:getInfoMenuTable()

    if Device:hasWifiManager() then
        common_settings.network_restore = self:getRestoreMenuTable()
        common_settings.network_dismiss_scan = self:getDismissScanMenuTable()
        common_settings.network_before_wifi_action = self:getBeforeWifiActionMenuTable()
    end
end

function NetworkMgr:showNetworkMenu(complete_callback)
    local info = InfoMessage:new{text = _("Scanning for networks…")}
    UIManager:show(info)
    UIManager:nextTick(function()
        local network_list, err = self:getNetworkList()
        UIManager:close(info)
        if network_list == nil then
            UIManager:show(InfoMessage:new{text = err})
            return
        end
        -- NOTE: Fairly hackish workaround for #4387,
        --       rescan if the first scan appeared to yield an empty list.
        --- @fixme This *might* be an issue better handled in lj-wpaclient...
        if (table.getn(network_list) == 0) then
            network_list, err = self:getNetworkList()
            if network_list == nil then
                UIManager:show(InfoMessage:new{text = err})
                return
            end
        end
        UIManager:show(require("ui/widget/networksetting"):new{
            network_list = network_list,
            connect_callback = complete_callback,
        })
    end)
end

function NetworkMgr:reconnectOrShowNetworkMenu(complete_callback)
    local info = InfoMessage:new{text = _("Scanning for networks…")}
    UIManager:show(info)
    UIManager:nextTick(function()
        local network_list, err = self:getNetworkList()
        UIManager:close(info)
        if network_list == nil then
            UIManager:show(InfoMessage:new{text = err})
            return
        end
        table.sort(network_list,
           function(l, r) return l.signal_quality > r.signal_quality end)
        local success = false
        table.foreach(network_list,
           function(idx, network)
               if network.password then
                   success = NetworkMgr:authenticateNetwork(network)
                   if success then
                       NetworkMgr:obtainIP()
                       if complete_callback then
                           complete_callback()
                       end
                       UIManager:show(InfoMessage:new{
                           text = T(_("Connected to network %1"), BD.wrap(network.ssid)),
                           timeout = 3,
                       })
                       return
                   end
               end
           end)
        if not success then
            UIManager:show(require("ui/widget/networksetting"):new{
                network_list = network_list,
                connect_callback = complete_callback,
            })
        end
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
