local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C = ffi.C
local T = ffiutil.template

-- We'll need a bunch of stuff for getifaddrs in NetworkMgr:ifHasAnAddress
require("ffi/posix_h")

local NetworkMgr = {
    is_wifi_on = false,
    is_connected = false,
    interface = nil,
}

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
        if Device:hasWifiManager() then
            os.execute("pkill -TERM restore-wifi-async.sh 2>/dev/null")
        end
        self:turnOffWifi()

        -- Handle the UI warning if it's from a beforeWifiAction...
        if widget then
            UIManager:close(widget)
            UIManager:show(InfoMessage:new{ text = _("Error connecting to the network") })
        end
        return
    end

    self:queryNetworkState()
    if self.is_wifi_on and self.is_connected then
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
        UIManager:scheduleIn(2, self.connectivityCheck, self, iter + 1, callback, widget)
    end
end

function NetworkMgr:scheduleConnectivityCheck(callback, widget)
    UIManager:scheduleIn(2, self.connectivityCheck, self, 1, callback, widget)
end

function NetworkMgr:init()
    Device:initNetworkManager(self)
    self.interface = self:getNetworkInterfaceName()

    self:queryNetworkState()
    self.wifi_was_on = G_reader_settings:isTrue("wifi_was_on")
    if self.wifi_was_on and G_reader_settings:isTrue("auto_restore_wifi") then
        -- Don't bother if WiFi is already up...
        if not self.is_connected then
            self:restoreWifiAsync()
        end
        self:scheduleConnectivityCheck()
    else
        -- Trigger an initial NetworkConnected event if WiFi was already up when we were launched
        if self.is_connected then
            -- NOTE: This needs to be delayed because NetworkListener is initialized slightly later by the FM/Reader app...
            UIManager:scheduleIn(2, UIManager.broadcastEvent, UIManager, Event:new("NetworkConnected"))
        end
    end

    return self
end

-- Following methods are Device specific which need to be initialized in
-- Device:initNetworkManager. Some of them can be set by calling
-- NetworkMgr:setWirelessBackend
function NetworkMgr:turnOnWifi() end
function NetworkMgr:turnOffWifi() end
-- This function returns status of the WiFi radio
function NetworkMgr:isWifiOn() end
function NetworkMgr:isConnected() end
function NetworkMgr:getNetworkInterfaceName() end
function NetworkMgr:getNetworkList() end
function NetworkMgr:getCurrentNetwork() end
function NetworkMgr:authenticateNetwork() end
function NetworkMgr:disconnectNetwork() end
function NetworkMgr:obtainIP() end
function NetworkMgr:releaseIP() end
-- This function should call both turnOnWifi() and obtainIP() in a non-blocking manner.
function NetworkMgr:restoreWifiAsync() end
-- End of device specific methods

-- Helper functions for devices that use sysfs entries to check connectivity.
function NetworkMgr:sysfsWifiOn()
    -- Network interface directory only exists as long as the Wi-Fi module is loaded
    return util.pathExists("/sys/class/net/".. self.interface)
end

function NetworkMgr:sysfsCarrierConnected()
    -- Read carrier state from sysfs.
    -- NOTE: We can afford to use CLOEXEC, as devices too old for it don't support Wi-Fi anyway ;)
    local out
    local file = io.open("/sys/class/net/" .. self.interface .. "/carrier", "re")

    -- File only exists while the Wi-Fi module is loaded, but may fail to read until the interface is brought up.
    if file then
        -- 0 means the interface is down, 1 that it's up
        -- (technically, it reflects the state of the physical link (e.g., plugged in or not for Ethernet))
        -- This does *NOT* represent network association state for Wi-Fi (it'll return 1 as soon as ifup)!
        out = file:read("*number")
        file:close()
    end

    return out == 1
end

function NetworkMgr:sysfsInterfaceOperational()
    -- Reads the interface's RFC2863 operational state from sysfs, and wait for it to be up
    -- (For Wi-Fi, that means associated & successfully authenticated)
    local out
    local file = io.open("/sys/class/net/" .. self.interface .. "/operstate", "re")

    -- Possible values: "unknown", "notpresent", "down", "lowerlayerdown", "testing", "dormant", "up"
    -- (c.f., Linux's <Documentation/ABI/testing/sysfs-class-net>)
    -- We're *assuming* all the drivers we care about implement this properly, so we can just rely on checking for "up".
    -- On unsupported drivers, this would be stuck on "unknown" (c.f., Linux's <Documentation/networking/operstates.rst>)
    -- NOTE: This does *NOT* mean the interface has been assigned an IP!
    if file then
        out = file:read("*l")
        file:close()
    end

    return out == "up"
end

-- This relies on the BSD API instead of the Linux ioctls (netdevice(7)), because handling IPv6 is slightly less painful this way...
function NetworkMgr:ifHasAnAddress()
    -- If the interface isn't operationally up, no need to go any further
    if not self:sysfsInterfaceOperational() then
        logger.dbg("NetworkMgr: interface is not operational yet")
        return false
    end

    -- It's up, do the getifaddrs dance to see if it was assigned an IP yet...
    -- c.f., getifaddrs(3)
    local ifaddr = ffi.new("struct ifaddrs *[1]")
    if C.getifaddrs(ifaddr) == -1 then
        local errno = ffi.errno()
        logger.err("NetworkMgr: getifaddrs:", ffi.string(C.strerror(errno)))
        return false
    end

    local ok
    local ifa = ifaddr[0]
    while ifa ~= nil do
        if ifa.ifa_addr ~= nil and C.strcmp(ifa.ifa_name, self.interface) == 0 then
            local family = ifa.ifa_addr.sa_family
            if family == C.AF_INET or family == C.AF_INET6 then
                local host = ffi.new("char[?]", C.NI_MAXHOST)
                local s = C.getnameinfo(ifa.ifa_addr,
                                        family == C.AF_INET and ffi.sizeof("struct sockaddr_in") or ffi.sizeof("struct sockaddr_in6"),
                                        host, C.NI_MAXHOST,
                                        nil, 0,
                                        C.NI_NUMERICHOST)
                if s ~= 0 then
                    logger.err("NetworkMgr: getnameinfo:", ffi.string(C.gai_strerror(s)))
                    ok = false
                else
                    logger.dbg("NetworkMgr: interface", self.interface, "is up @", ffi.string(host))
                    ok = true
                end
                -- Regardless of failure, we only check a single if, so we're done
                break
            end
        end
        ifa = ifa.ifa_next
    end
    C.freeifaddrs(ifaddr[0])

    return ok
end

function NetworkMgr:toggleWifiOn(complete_callback, long_press)
    local toggle_im = InfoMessage:new{
        text = _("Turning on Wi-Fi…"),
    }
    UIManager:show(toggle_im)
    UIManager:forceRePaint()

    self.wifi_was_on = true
    G_reader_settings:makeTrue("wifi_was_on")
    self.wifi_toggle_long_press = long_press

    -- Connecting might take a few seconds (hello standby).
    -- Broadcast the information, that network is changing, so affected modules/plugins can react.
    UIManager:broadcastEvent(Event:new("NetworkConnecting"))
    self:turnOnWifi(complete_callback)

    UIManager:close(toggle_im)
end

function NetworkMgr:toggleWifiOff(complete_callback)
    local toggle_im = InfoMessage:new{
        text = _("Turning off Wi-Fi…"),
    }
    UIManager:show(toggle_im)
    UIManager:forceRePaint()

    self.wifi_was_on = false
    G_reader_settings:makeFalse("wifi_was_on")

    -- Disconnecting might take some time, but less than connecting (hello standby).
    -- Broadcast the information, that network is changing, so affected modules/plugins can react.
    UIManager:broadcastEvent(Event:new("NetworkDisconnecting"))
    self:turnOffWifi(complete_callback)

    UIManager:close(toggle_im)
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
        self:turnOnWifiAndWaitForConnection(callback)
    else
        self:promptWifiOn(callback)
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
        self:turnOffWifi(callback)
    else
        self:promptWifiOff(callback)
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

-- Update our cached network status
function NetworkMgr:queryNetworkState()
    self.is_wifi_on = self:isWifiOn()
    self.is_connected = self.is_wifi_on and self:isConnected()
end

-- These do not call the actual Device methods, but what we, NetworkMgr, think the state is based on our own behavior.
function NetworkMgr:getWifiState()
    return self.is_wifi_on
end
function NetworkMgr:setWifiState(bool)
    self.is_wifi_on = bool
end
function NetworkMgr:getConnectionState()
    return self.is_connected
end
function NetworkMgr:setConnectionState(bool)
    self.is_connected = bool
end


function NetworkMgr:isNetworkInfoAvailable()
    if Device:isAndroid() then
        -- always available
        return true
    else
        return self:isConnected()
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
            callback = function() self:openSettings() end,
        }
    else
        return self:getWifiToggleMenuTable()
    end
end

function NetworkMgr:getWifiToggleMenuTable()
    local toggleCallback = function(touchmenu_instance, long_press)
        self:queryNetworkState()
        local fully_connected = self.is_wifi_on and self.is_connected
        local complete_callback = function()
            -- Check the connection status again
            self:queryNetworkState()
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
                    if self.is_wifi_on and self.is_connected then
                        UIManager:broadcastEvent(Event:new("NetworkConnected"))
                    elseif self.is_wifi_on and not self.is_connected then
                        -- If we can't ping the gateway, despite a successful authentication w/ the AP, display a warning,
                        -- because this means that Wi-Fi is technically still enabled (e.g., modules are loaded).
                        -- We can't really enforce a turnOffWifi right now, because the user might want to try another AP or something.
                        -- (c.f., #5912, #4616).
                        -- NOTE: Keep in mind that NetworkSetting only runs this callback on *successful* connections!
                        --       (It's called connect_callback there).
                        --       This makes this branch somewhat hard to reach, which is why it gets a dedicated prompt below...
                        UIManager:show(InfoMessage:new{
                            icon = "notice-warning",
                            text = _("Gateway is unreachable, but Wi-Fi is still on!"),
                            timeout = 3,
                        })
                    end
                else
                    -- Assume success on other platforms
                    UIManager:broadcastEvent(Event:new("NetworkConnected"))
                end
            end
        end -- complete_callback()
        if fully_connected then
            self:toggleWifiOff(complete_callback)
        elseif self.is_wifi_on and not self.is_connected then
            -- ask whether user wants to connect or turn off wifi
            self:promptWifi(complete_callback, long_press)
        else -- if not connected at all
            self:toggleWifiOn(complete_callback, long_press)
        end
    end -- toggleCallback()

    return {
        text = _("Wi-Fi connection"),
        enabled_func = function() return Device:hasWifiToggle() end,
        checked_func = function() return self:isWifiOn() end,
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
                self:setHTTPProxy(proxy())
            elseif proxy_enabled() then
                self:setHTTPProxy(nil)
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
                    self:setHTTPProxy(input)
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
        callback = function()
            G_reader_settings:flipNilOrFalse("auto_disable_wifi")
            -- NOTE: Well, not exactly, but the activity check wouldn't be (un)scheduled until the next Network(Dis)Connected event...
            UIManager:askForRestart()
        end,
    }
end

function NetworkMgr:getRestoreMenuTable()
    return {
        text = _("Restore Wi-Fi connection on resume"),
        help_text = _([[This will attempt to automatically and silently re-connect to Wi-Fi on startup or on resume if Wi-Fi used to be enabled the last time you used KOReader.]]),
        checked_func = function() return G_reader_settings:isTrue("auto_restore_wifi") end,
        enabled_func = function() return Device:hasWifiManager() end,
        callback = function() G_reader_settings:flipNilOrFalse("auto_restore_wifi") end,
    }
end

function NetworkMgr:getInfoMenuTable()
    return {
        text = _("Network info"),
        keep_menu_open = true,
        enabled_func = function() return self:isNetworkInfoAvailable() end,
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowNetworkInfo"))
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

    -- Allow auto_disable_wifi on devices where the net sysfs entry is exposed.
    if self:getNetworkInterfaceName() then
        common_settings.network_powersave = self:getPowersaveMenuTable()
    end

    if Device:hasWifiManager() or Device:isEmulator() then
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
            logger.warn("Initial Wi-Fi scan yielded no results, rescanning")
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
            local ssid
            -- We need to do two passes, as we may have *both* an already connected network (from the global wpa config),
            -- *and* preferred networks, and if the prferred networks have a better signal quality,
            -- they'll be sorted *earlier*, which would cause us to try to associate to a different AP than
            -- what wpa_supplicant is already trying to do...
            for dummy, network in ipairs(network_list) do
                if network.connected then
                    -- On platforms where we use wpa_supplicant (if we're calling this, we are),
                    -- the invocation will check its global config, and if an AP configured there is reachable,
                    -- it'll already have connected to it on its own.
                    success = true
                    ssid = network.ssid
                    break
                end
            end

            -- Next, look for our own prferred networks...
            local err_msg = _("Connection failed")
            if not success then
                for dummy, network in ipairs(network_list) do
                    if network.password then
                        -- If we hit a preferred network and we're not already connected,
                        -- attempt to connect to said preferred network....
                        success, err_msg = self:authenticateNetwork(network)
                        if success then
                            ssid = network.ssid
                            break
                        end
                    end
                end
            end

            if success then
                self:obtainIP()
                if complete_callback then
                    complete_callback()
                end
                UIManager:show(InfoMessage:new{
                    text = T(_("Connected to network %1"), BD.wrap(ssid)),
                    timeout = 3,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = err_msg,
                    timeout = 3,
                })
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

-- set network proxy if global variable G_defaults:readSetting("NETWORK_PROXY") is defined
if G_defaults:readSetting("NETWORK_PROXY") then
    NetworkMgr:setHTTPProxy(G_defaults:readSetting("NETWORK_PROXY"))
end

return NetworkMgr:init()
