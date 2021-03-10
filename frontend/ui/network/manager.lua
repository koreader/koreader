local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = ffiutil.template

local NetworkMgr = {}

function NetworkMgr:readNWSettings()
    self.nw_settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
end

-- Used after restoreWifiAsync() and the turn_on beforeWifiAction to make sure we eventually send a NetworkConnected event,
-- as quite a few things rely on it (KOSync, c.f. #5109; the network activity check, c.f., #6424).
function NetworkMgr:connectivityCheck(iter, callback, widget)
    -- Give up after a while (restoreWifiAsync can take over 45s, so, try to cover that)...
    if iter > 25 then
        logger.info("Failed to restore Wi-Fi (after", iter, "iterations)!")
        self.wifi_was_on = false
        G_reader_settings:makeFalse("wifi_was_on")
        -- If we abort, murder Wi-Fi and the async script first...
        if Device:hasWifiManager() and not Device:isEmulator() then
            os.execute("pkill -TERM restore-wifi-async.sh 2>/dev/null")
        end
        NetworkMgr:turnOffWifi()

        -- Handle the UI warning if it's from a beforeWifiAction...
        if widget then
            UIManager:close(widget)
            UIManager:show(InfoMessage:new{ text = _("Error connecting to the network") })
        end
        return
    end

    if NetworkMgr:isWifiOn() and NetworkMgr:isConnected() then
        self.wifi_was_on = true
        G_reader_settings:makeTrue("wifi_was_on")
        UIManager:broadcastEvent(Event:new("NetworkConnected"))
        logger.info("Wi-Fi successfully restored (after", iter, "iterations)!")

        -- Handle the UI & callback if it's from a beforeWifiAction...
        if widget then
            UIManager:close(widget)
        end
        if callback then
            callback()
        else
            -- If this trickled down from a turn_onbeforeWifiAction and there is no callback,
            -- mention that the action needs to be retried manually.
            if widget then
                UIManager:show(InfoMessage:new{
                    text = _("You can now retry the action that required network access"),
                    timeout = 3,
                })
            end
        end
    else
        UIManager:scheduleIn(2, function() NetworkMgr:connectivityCheck(iter + 1, callback, widget) end)
    end
end

function NetworkMgr:scheduleConnectivityCheck(callback, widget)
    UIManager:scheduleIn(2, function() NetworkMgr:connectivityCheck(1, callback, widget) end)
end

function NetworkMgr:init()
    -- On Kobo, kill Wi-Fi if NetworkMgr:isWifiOn() and NOT NetworkMgr:isConnected()
    -- (i.e., if the launcher left the Wi-Fi in an inconsistent state: modules loaded, but no route to gateway).
    if Device:isKobo() and self:isWifiOn() and not self:isConnected() then
        logger.info("Kobo Wi-Fi: Left in an inconsistent state by launcher!")
        self:turnOffWifi()
    end

    self.wifi_was_on = G_reader_settings:isTrue("wifi_was_on")
    if self.wifi_was_on and G_reader_settings:isTrue("auto_restore_wifi") then
        -- Don't bother if WiFi is already up...
        if not (self:isWifiOn() and self:isConnected()) then
            self:restoreWifiAsync()
        end
        self:scheduleConnectivityCheck()
    else
        -- Trigger an initial NetworkConnected event if WiFi was already up when we were launched
        if NetworkMgr:isWifiOn() and NetworkMgr:isConnected() then
            -- NOTE: This needs to be delayed because NetworkListener is initialized slightly later by the FM/Reader app...
            UIManager:scheduleIn(2, function() UIManager:broadcastEvent(Event:new("NetworkConnected")) end)
        end
    end
end

-- Following methods are Device specific which need to be initialized in
-- Device:initNetworkManager. Some of them can be set by calling
-- NetworkMgr:setWirelessBackend
function NetworkMgr:turnOnWifi() end
function NetworkMgr:turnOffWifi() end
function NetworkMgr:isWifiOn() end
function NetworkMgr:getNetworkInterfaceName() end
function NetworkMgr:getNetworkList() end
function NetworkMgr:getCurrentNetwork() end
function NetworkMgr:authenticateNetwork() end
function NetworkMgr:disconnectNetwork() end
function NetworkMgr:obtainIP() end
function NetworkMgr:releaseIP() end
-- This function should unblockly call both turnOnWifi() and obtainIP().
function NetworkMgr:restoreWifiAsync() end
-- End of device specific methods

function NetworkMgr:toggleWifiOn(complete_callback, long_press)
    self.wifi_was_on = true
    G_reader_settings:makeTrue("wifi_was_on")
    self.wifi_toggle_long_press = long_press
    self:turnOnWifi(complete_callback)
end

function NetworkMgr:toggleWifiOff(complete_callback)
    self.wifi_was_on = false
    G_reader_settings:makeFalse("wifi_was_on")
    self:turnOffWifi(complete_callback)
end

function NetworkMgr:promptWifiOn(complete_callback, long_press)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn on Wi-Fi?"),
        ok_text = _("Turn on"),
        ok_callback = function()
            self:toggleWifiOn(complete_callback, long_press)
        end,
    })
end

function NetworkMgr:promptWifiOff(complete_callback)
    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn off Wi-Fi?"),
        ok_text = _("Turn off"),
        ok_callback = function()
            self:toggleWifiOff(complete_callback)
        end,
    })
end

function NetworkMgr:promptWifi(complete_callback, long_press)
    UIManager:show(MultiConfirmBox:new{
        text = _("Wi-Fi is enabled, but you're currently not connected to a network.\nHow would you like to proceed?"),
        choice1_text = _("Turn Wi-Fi off"),
        choice1_callback = function()
            self:toggleWifiOff(complete_callback)
        end,
        choice2_text = _("Connect"),
        choice2_callback = function()
            self:toggleWifiOn(complete_callback, long_press)
        end,
    })
end

function NetworkMgr:turnOnWifiAndWaitForConnection(callback)
    local info = InfoMessage:new{ text = _("Connecting to Wi-Fi…") }
    UIManager:show(info)
    UIManager:forceRePaint()

    -- Don't bother if WiFi is already up...
    if not (self:isWifiOn() and self:isConnected()) then
        self:turnOnWifi()
    end

    -- This will handle sending the proper Event, manage wifi_was_on, as well as tearing down Wi-Fi in case of failures,
    -- (i.e., much like getWifiToggleMenuTable).
    self:scheduleConnectivityCheck(callback, info)
end

--- This quirky internal flag is used for the rare beforeWifiAction -> afterWifiAction brackets.
function NetworkMgr:clearBeforeActionFlag()
    self._before_action_tripped = nil
end

function NetworkMgr:setBeforeActionFlag()
    self._before_action_tripped = true
end

function NetworkMgr:getBeforeActionFlag()
    return self._before_action_tripped
end

--- @note: The callback will only run *after* a *succesful* network connection.
---        The only guarantee it provides is isConnected (i.e., an IP & a local gateway),
---        *NOT* isOnline (i.e., WAN), se be careful with recursive callbacks!
function NetworkMgr:beforeWifiAction(callback)
    -- Remember that we ran, for afterWifiAction...
    self:setBeforeActionFlag()

    local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action")
    if wifi_enable_action == "turn_on" then
        NetworkMgr:turnOnWifiAndWaitForConnection(callback)
    else
        NetworkMgr:promptWifiOn(callback)
    end
end

-- NOTE: This is actually used very sparingly (newsdownloader/send2ebook),
--       because bracketing a single action in a connect/disconnect session doesn't necessarily make much sense...
function NetworkMgr:afterWifiAction(callback)
    -- Don't do anything if beforeWifiAction never actually ran...
    if not self:getBeforeActionFlag() then
        return
    end
    self:clearBeforeActionFlag()

    local wifi_disable_action = G_reader_settings:readSetting("wifi_disable_action")
    if wifi_disable_action == "leave_on" then
        -- NOP :)
        if callback then
           callback()
        end
    elseif wifi_disable_action == "turn_off" then
        NetworkMgr:turnOffWifi(callback)
    else
        NetworkMgr:promptWifiOff(callback)
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
        G_reader_settings:makeTrue("http_proxy_enabled")
    else
        G_reader_settings:makeFalse("http_proxy_enabled")
    end
end

-- Helper functions to hide the quirks of using beforeWifiAction properly ;).

-- Run callback *now* if you're currently online (ie., isOnline),
-- or attempt to go online and run it *ASAP* without any more user interaction.
-- NOTE: If you're currently connected but without Internet access (i.e., isConnected and not isOnline),
--       it will just attempt to re-connect, *without* running the callback.
-- c.f., ReaderWikipedia:onShowWikipediaLookup @ frontend/apps/reader/modules/readerwikipedia.lua
function NetworkMgr:runWhenOnline(callback)
    if self:isOnline() then
        callback()
    else
        --- @note: Avoid infinite recursion, beforeWifiAction only guarantees isConnected, not isOnline.
        if not self:isConnected() then
            self:beforeWifiAction(callback)
        else
            self:beforeWifiAction()
        end
    end
end

-- This one is for callbacks that only require isConnected, and since that's guaranteed by beforeWifiAction,
-- you also have a guarantee that the callback *will* run.
function NetworkMgr:runWhenConnected(callback)
    if self:isConnected() then
        callback()
    else
        self:beforeWifiAction(callback)
    end
end

-- Mild variants that are used for recursive calls at the beginning of a complex function call.
-- Returns true when not yet online, in which case you should *abort* (i.e., return) the initial call,
-- and otherwise, go-on as planned.
-- NOTE: If you're currently connected but without Internet access (i.e., isConnected and not isOnline),
--       it will just attempt to re-connect, *without* running the callback.
-- c.f., ReaderWikipedia:lookupWikipedia @ frontend/apps/reader/modules/readerwikipedia.lua
function NetworkMgr:willRerunWhenOnline(callback)
    if not self:isOnline() then
        --- @note: Avoid infinite recursion, beforeWifiAction only guarantees isConnected, not isOnline.
        if not self:isConnected() then
            self:beforeWifiAction(callback)
        else
            self:beforeWifiAction()
        end
        return true
    end

    return false
end

-- This one is for callbacks that only require isConnected, and since that's guaranteed by beforeWifiAction,
-- you also have a guarantee that the callback *will* run.
function NetworkMgr:willRerunWhenConnected(callback)
    if not self:isConnected() then
        self:beforeWifiAction(callback)
        return true
    end

    return false
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
    local toggleCallback = function(touchmenu_instance, long_press)
        local is_wifi_on = NetworkMgr:isWifiOn()
        local is_connected = NetworkMgr:isConnected()
        local fully_connected = is_wifi_on and is_connected
        local complete_callback = function()
            -- Notify TouchMenu to update item check state
            touchmenu_instance:updateItems()
            -- If Wi-Fi was on when the menu was shown, this means the tap meant to turn the Wi-Fi *off*,
            -- as such, this callback will only be executed *after* the network has been disconnected.
            if fully_connected then
                UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
            else
                -- On hasWifiManager devices that play with kernel modules directly,
                -- double-check that the connection attempt was actually successful...
                if Device:isKobo() or Device:isCervantes() then
                    if NetworkMgr:isWifiOn() and NetworkMgr:isConnected() then
                        UIManager:broadcastEvent(Event:new("NetworkConnected"))
                    elseif NetworkMgr:isWifiOn() and not NetworkMgr:isConnected() then
                        -- Don't leave Wi-Fi in an inconsistent state if the connection failed.
                        -- NOTE: Keep in mind that NetworkSetting only runs this callback on *successful* connections!
                        --       (It's called connect_callback there).
                        --       This makes this branch somewhat hard to reach, which is why it gets a dedicated prompt below...
                        self.wifi_was_on = false
                        G_reader_settings:makeFalse("wifi_was_on")
                        -- NOTE: We're limiting this to only a few platforms, as it might be actually harmful on some devices.
                        --       The intent being to unload kernel modules, and make a subsequent turnOnWifi behave sanely.
                        --       PB: Relies on netagent, no idea what it does, but it's not using this codepath anyway (!hasWifiToggle)
                        --       Android: Definitely shouldn't do it.
                        --       Sony: Doesn't play with modules, don't do it.
                        --       Kobo: Yes, please.
                        --       Cervantes: Loads/unloads module, probably could use it like Kobo.
                        --       Kindle: Probably could use it, if only because leaving Wireless on is generally a terrible idea on Kindle,
                        --               except that we defer to lipc, which makes Wi-Fi handling asynchronous, and the callback is simply delayed by 1s,
                        --               so we can't be sure the system will actually have finished bringing Wi-Fi up by then...
                        NetworkMgr:turnOffWifi()
                        touchmenu_instance:updateItems()
                    end
                else
                    -- Assume success on other platforms
                    UIManager:broadcastEvent(Event:new("NetworkConnected"))
                end
            end
        end
        if fully_connected then
            NetworkMgr:toggleWifiOff(complete_callback)
        elseif is_wifi_on and not is_connected then
            -- ask whether user wants to connect or turn off wifi
            NetworkMgr:promptWifi(complete_callback, long_press)
        else
            NetworkMgr:toggleWifiOn(complete_callback, long_press)
        end
    end

    return {
        text = _("Wi-Fi connection"),
        enabled_func = function() return Device:hasWifiToggle() end,
        checked_func = function() return NetworkMgr:isWifiOn() end,
        callback = toggleCallback,
        hold_callback = function(touchmenu_instance)
            toggleCallback(touchmenu_instance, true)
        end,
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

function NetworkMgr:getPowersaveMenuTable()
    return {
        text = _("Disable Wi-Fi connection when inactive"),
        help_text = _([[This will automatically turn Wi-Fi off after a generous period of network inactivity, without disrupting workflows that require a network connection, so you can just keep reading without worrying about battery drain.]]),
        checked_func = function() return G_reader_settings:isTrue("auto_disable_wifi") end,
        enabled_func = function() return Device:hasWifiManager() and not Device:isEmulator() end,
        callback = function()
            G_reader_settings:flipNilOrFalse("auto_disable_wifi")
            -- NOTE: Well, not exactly, but the activity check wouldn't be (un)scheduled until the next Network(Dis)Connected event...
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart."),
            })
        end,
    }
end

function NetworkMgr:getRestoreMenuTable()
    return {
        text = _("Restore Wi-Fi connection on resume"),
        help_text = _([[This will attempt to automatically and silently re-connect to Wi-Fi on startup or on resume if Wi-Fi used to be enabled the last time you used KOReader.]]),
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
        turn_on = {_("turn on"), _("Turn on")},
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

function NetworkMgr:getAfterWifiActionMenuTable()
    local wifi_disable_action_setting = G_reader_settings:readSetting("wifi_disable_action") or "prompt"
    local wifi_disable_actions = {
        leave_on = {_("leave on"), _("Leave on")},
        turn_off = {_("turn off"), _("Turn off")},
        prompt = {_("prompt"), _("Prompt")},
    }
    local action_table = function(wifi_disable_action)
    return {
        text = wifi_disable_actions[wifi_disable_action][2],
        checked_func = function()
            return wifi_disable_action_setting == wifi_disable_action
        end,
        callback = function()
            wifi_disable_action_setting = wifi_disable_action
            G_reader_settings:saveSetting("wifi_disable_action", wifi_disable_action)
        end,
    }
    end
    return {
        text_func = function()
            return T(_("Action when done with Wi-Fi: %1"),
                wifi_disable_actions[wifi_disable_action_setting][1]
            )
        end,
        sub_item_table = {
            action_table("leave_on"),
            action_table("turn_off"),
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
        common_settings.network_powersave = self:getPowersaveMenuTable()
        common_settings.network_restore = self:getRestoreMenuTable()
        common_settings.network_dismiss_scan = self:getDismissScanMenuTable()
        common_settings.network_before_wifi_action = self:getBeforeWifiActionMenuTable()
        common_settings.network_after_wifi_action = self:getAfterWifiActionMenuTable()
    end
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
        -- NOTE: Fairly hackish workaround for #4387,
        --       rescan if the first scan appeared to yield an empty list.
        --- @fixme This *might* be an issue better handled in lj-wpaclient...
        if #network_list == 0 then
            network_list, err = self:getNetworkList()
            if network_list == nil then
                UIManager:show(InfoMessage:new{text = err})
                return
            end
        end

        table.sort(network_list,
           function(l, r) return l.signal_quality > r.signal_quality end)

        local success = false
        if self.wifi_toggle_long_press then
            self.wifi_toggle_long_press = nil
        else
            for dummy, network in ipairs(network_list) do
                if network.connected then
                    -- On platforms where we use wpa_supplicant (if we're calling this, we are),
                    -- the invocation will check its global config, and if an AP configured there is reachable,
                    -- it'll already have connected to it on its own.
                    success = true
                elseif network.password then
                    success = NetworkMgr:authenticateNetwork(network)
                end
                if success then
                    NetworkMgr:obtainIP()
                    if complete_callback then
                        complete_callback()
                    end
                    UIManager:show(InfoMessage:new{
                        text = T(_("Connected to network %1"), BD.wrap(network.ssid)),
                        timeout = 3,
                    })
                    break
                end
            end
        end
        if not success then
            -- NOTE: Also supports a disconnect_callback, should we use it for something?
            --       Tearing down Wi-Fi completely when tapping "disconnect" would feel a bit harsh, though...
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
