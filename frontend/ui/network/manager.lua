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
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local C = ffi.C
local T = ffiutil.template

-- We'll need a bunch of stuff for getifaddrs in NetworkMgr:ifHasAnAddress
require("ffi/posix_h")

-- We unfortunately don't have that one in ffi/posix_h :/
local EBUSY = 16

local NetworkMgr = {
    is_wifi_on = false,
    is_connected = false,
    interface = nil,

    pending_connectivity_check = false,
    pending_connection = false,
    _before_action_tripped = nil,
}

function NetworkMgr:readNWSettings()
    self.nw_settings = LuaSettings:open(DataStorage:getSettingsDir().."/network.lua")
end

-- Common chunk of stuff we have to do when aborting a connection attempt
function NetworkMgr:_abortWifiConnection()
    -- Cancel any pending connectivity check, because it wouldn't achieve anything
    self:unscheduleConnectivityCheck()

    self.wifi_was_on = false
    G_reader_settings:makeFalse("wifi_was_on")
    -- Murder Wi-Fi and the async script (if any) first...
    if Device:hasWifiRestore() and not Device:isKindle() then
        os.execute("pkill -TERM restore-wifi-async.sh 2>/dev/null")
    end
    -- We were never connected to begin with, so, no disconnecting broadcast required
    if Device:hasSeamlessWifiToggle() then
        -- We only want to actually kill the WiFi on platforms where we can do that seamlessly.
        self:turnOffWifi()
    end
    -- We're obviously done with this connection attempt
    self.pending_connection = false
end

-- Attempt to deal with platforms that don't guarantee isConnected when turnOnWifi returns,
-- so that we only attempt to connect to WiFi *once* when using the beforeWifiAction framework...
function NetworkMgr:requestToTurnOnWifi(wifi_cb, interactive)
    if self.pending_connection then
        -- We've already enabled WiFi, don't try again until the earlier attempt succeeds or fails...
        return EBUSY
    end

    -- Connecting will take a few seconds, broadcast that information so affected modules/plugins can react.
    UIManager:broadcastEvent(Event:new("NetworkConnecting"))
    self.pending_connection = true

    return self:turnOnWifi(wifi_cb, interactive)
end

-- Used after restoreWifiAsync() and the turn_on beforeWifiAction to make sure we eventually send a NetworkConnected event,
-- as quite a few things rely on it (KOSync, c.f. #5109; the network activity check, c.f., #6424).
function NetworkMgr:connectivityCheck(iter, callback, widget)
    -- Give up after a while (restoreWifiAsync can take over 45s, so, try to cover that)...
    if iter >= 180 then
        logger.info("Failed to restore Wi-Fi (after", iter * 0.25, "seconds)!")
        self:_abortWifiConnection()

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
        logger.info("Wi-Fi successfully restored (after", iter * 0.25, "seconds)!")
        UIManager:broadcastEvent(Event:new("NetworkConnected"))

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
        self.pending_connectivity_check = false
        -- We're done, so we can stop blocking concurrent connection attempts
        self.pending_connection = false
    else
        UIManager:scheduleIn(0.25, self.connectivityCheck, self, iter + 1, callback, widget)
    end
end

function NetworkMgr:scheduleConnectivityCheck(callback, widget)
    self.pending_connectivity_check = true
    UIManager:scheduleIn(0.25, self.connectivityCheck, self, 1, callback, widget)
end

function NetworkMgr:unscheduleConnectivityCheck()
    UIManager:unschedule(self.connectivityCheck)
    self.pending_connectivity_check = false
end

function NetworkMgr:init()
    Device:initNetworkManager(self)
    self.interface = self:getNetworkInterfaceName()

    self:queryNetworkState()
    self.wifi_was_on = G_reader_settings:isTrue("wifi_was_on")
    -- Trigger an initial NetworkConnected event if WiFi was already up when we were launched
    if self.is_connected then
        -- NOTE: This needs to be delayed because we run on require, while NetworkListener gets spun up sliiightly later on FM/ReaderUI init...
        UIManager:nextTick(UIManager.broadcastEvent, UIManager, Event:new("NetworkConnected"))
    else
        -- Attempt to restore wifi in the background if necessary
        if Device:hasWifiRestore() and self.wifi_was_on and G_reader_settings:isTrue("auto_restore_wifi") then
            logger.dbg("NetworkMgr: init will restore Wi-Fi in the background")
            self:restoreWifiAsync()
            self:scheduleConnectivityCheck()
        end
    end

    return self
end

-- The following methods are Device specific, and need to be initialized in Device:initNetworkManager.
-- Some of them can be set by calling NetworkMgr:setWirelessBackend
-- NOTE: The interactive flag is set by callers when the toggle was a *direct* user prompt (i.e., Menu or Gesture),
--       as opposed to an indirect one (like the beforeWifiAction framework).
--       It allows the backend to skip UI prompts for non-interactive use-cases.
-- NOTE: May optionally return a boolean, e.g., return false if the backend can guarantee the connection failed.
-- NOTE: These *must* run or appropriately forward complete_callback (e.g., to reconnectOrShowNetworkMenu),
--       as said callback is responsible for schedulig the connectivity check,
--       which, in turn, is responsible for the Event signaling!
function NetworkMgr:turnOnWifi(complete_callback, interactive) end
function NetworkMgr:turnOffWifi(complete_callback) end
-- This function returns the current status of the WiFi radio
-- NOTE: On !hasWifiToggle platforms, we assume networking is always available,
--       so as not to confuse the whole beforeWifiAction framework
--       (and let it fail with network errors when offline, instead of looping on unimplemented stuff...).
function NetworkMgr:isWifiOn()
    if not Device:hasWifiToggle() then
        return true
    end
end
function NetworkMgr:isConnected()
    if not Device:hasWifiToggle() then
        return true
    end
end
function NetworkMgr:getNetworkInterfaceName() end
function NetworkMgr:getConfiguredNetworks() end -- From the *backend*, e.g., wpa_cli list_networks (as opposed to `getAllSavedNetworks`)
function NetworkMgr:getNetworkList() end
function NetworkMgr:getCurrentNetwork() end
function NetworkMgr:authenticateNetwork(network) end
function NetworkMgr:disconnectNetwork(network) end
-- NOTE: This is currently only called on hasWifiManager platforms!
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

-- The socket API equivalent of "ip route get 203.0.113.1 || ip route get 2001:db8::1".
--
-- These addresses are from special ranges reserved for documentation
-- (RFC 5737, RFC 3849) and therefore likely to just use the default route.
function NetworkMgr:hasDefaultRoute()
    local socket = require("socket")

    local s, ret, err
    s, err = socket.udp()
    if s == nil then
        logger.err("NetworkMgr: socket.udp:", err)
        return nil
    end

    ret, err = s:setpeername("203.0.113.1", "53")
    if ret == nil then
        -- Most likely "Network is unreachable", meaning there's no route to that address.
        logger.dbg("NetworkMgr: socket.udp.setpeername:", err)

        -- Try IPv6, may still succeed if this is an IPv6-only network.
        ret, err = s:setpeername("2001:db8::1", "53")
        if ret == nil then
            -- Most likely "Network is unreachable", meaning there's no route to that address.
            logger.dbg("NetworkMgr: socket.udp.setpeername:", err)
        end
    end

    s:close()

    -- If setpeername succeeded, we have a default route.
    return ret ~= nil
end

function NetworkMgr:canResolveHostnames()
    local socket = require("socket")
    -- Microsoft uses `dns.msftncsi.com` for Windows, see
    -- <https://technet.microsoft.com/en-us/library/ee126135#BKMK_How> for
    -- more information. They also check whether <http://www.msftncsi.com/ncsi.txt>
    -- returns `Microsoft NCSI`.
    return socket.dns.toip("dns.msftncsi.com") ~= nil
end

-- Wrappers around turnOnWifi & turnOffWifi with proper Event signaling
function NetworkMgr:enableWifi(wifi_cb, interactive)
    -- NOTE: Let the backend run the wifi_cb via a connectivity check once it's *actually* attempted a connection,
    --       as it knows best when that actually happens (especially reconnectOrShowNetworkMenu), unlike us.
    local connectivity_cb = function()
        -- NOTE: We *could* arguably have multiple connectivity checks running concurrently,
        --       but only having a single one running makes things somewhat easier to follow...
        if self.pending_connectivity_check then
            self:unscheduleConnectivityCheck()
        end

        -- This will handle sending the proper Event, manage wifi_was_on, as well as tearing down Wi-Fi in case of failures.
        self:scheduleConnectivityCheck(wifi_cb)
    end

    -- Some implementations (usually, hasWifiManager) can report whether they were successful
    local status = self:requestToTurnOnWifi(connectivity_cb, interactive)
    -- If turnOnWifi failed, abort early
    if status == false then
        logger.warn("NetworkMgr:enableWifi: Connection failed!")
        self:_abortWifiConnection()
        return false
    elseif status == EBUSY then
        -- NOTE: This means turnOnWifi was *not* called (this time).
        logger.warn("NetworkMgr:enableWifi: A previous connection attempt is still ongoing!")
        -- We don't really have a great way of dealing with the wifi_cb in this case,
        -- so, much like in turnOnWifiAndWaitForConnection, we'll just drop it...
        -- We don't want to run multiple concurrent connectivity checks,
        -- which means we'd need to unschedule the pending one, which would effectively rewind the timer,
        -- which we don't want, especially if we're non-interactive,
        -- as that would risk rescheduling the same thing over and over again...
        if wifi_cb then
            logger.warn("NetworkMgr:enableWifi: We've had to drop wifi_cb:", wifi_cb)
        end
        -- Make it more obvious to the user when interactive...
        if interactive then
            UIManager:show(InfoMessage:new{
                text = _("A previous connection attempt is still ongoing, this one will be ignored!"),
                timeout = 3,
            })
        end
        return
    end

    return true
end

function NetworkMgr:disableWifi(cb, interactive)
    local complete_callback = function()
        UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
        if cb then
            cb()
        end
    end
    UIManager:broadcastEvent(Event:new("NetworkDisconnecting"))

    -- NOTE: This is a subset of _abortWifiConnection, in case we disable wifi during a connection attempt.
    -- Cancel any pending connectivity check, because it wouldn't achieve anything
    self:unscheduleConnectivityCheck()
    -- Make sure we don't have an async script running...
    if Device:hasWifiRestore() and not Device:isKindle() then
        os.execute("pkill -TERM restore-wifi-async.sh 2>/dev/null")
    end
    -- Can't be connecting since we're killing Wi-Fi ;)
    self.pending_connection = false

    self:turnOffWifi(complete_callback)

    if interactive then
        self.wifi_was_on = false
        G_reader_settings:makeFalse("wifi_was_on")
    end
end

function NetworkMgr:toggleWifiOn(complete_callback, long_press, interactive)
    local toggle_im = InfoMessage:new{
        text = _("Turning on Wi-Fi…"),
    }
    UIManager:show(toggle_im)
    UIManager:forceRePaint()

    self.wifi_toggle_long_press = long_press

    self:enableWifi(complete_callback, interactive)

    UIManager:close(toggle_im)
end

function NetworkMgr:toggleWifiOff(complete_callback, interactive)
    local toggle_im = InfoMessage:new{
        text = _("Turning off Wi-Fi…"),
    }
    UIManager:show(toggle_im)
    UIManager:forceRePaint()

    self:disableWifi(complete_callback, interactive)

    UIManager:close(toggle_im)
end

-- NOTE: Only used by the beforeWifiAction framework, so, can never be flagged as "interactive" ;).
function NetworkMgr:promptWifiOn(complete_callback)
    -- If there's already an ongoing connection attempt, don't even display the ConfirmBox,
    -- as that's just confusing, especially on Android, because you might have seen the one you tapped "Turn on" on disappear,
    -- and be surprised by new ones that popped up out of focus while the system settings were opened...
    if self.pending_connection then
        -- Like other beforeWifiAction backends, the callback is forfeit anyway
        logger.warn("NetworkMgr:promptWifiOn: A previous connection attempt is still ongoing!")
        return
    end

    UIManager:show(ConfirmBox:new{
        text = _("Do you want to turn on Wi-Fi?"),
        ok_text = _("Turn on"),
        ok_callback = function()
            self:toggleWifiOn(complete_callback)
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

-- NOTE: Currently only has a single caller, the Menu entry, so it's always flagged as interactive
function NetworkMgr:promptWifi(complete_callback, long_press, interactive)
    local text = _("Wi-Fi is enabled, but you're currently not connected to a network.")
    -- Detail whether there's an attempt and/or a connectivity check in progress.
    if self.pending_connection then
        -- NOTE: Incidentally, this means that tapping Connect would yield EBUSY, so we gray it out...
        text = text .. "\n" .. _("Please note that a connection attempt is currently in progress!")
    end
    if self.pending_connectivity_check then
        text = text .. "\n" .. _("KOReader is currently waiting for connectivity. This may take up to 45s, so you may just want to try again later.")
    end
    text = text .. "\n" .. _("How would you like to proceed?")
    UIManager:show(MultiConfirmBox:new{
        text = text,
        -- "Cancel" could be construed as "cancel the current attempt", which is not what this does ;p.
        cancel_text = _("Dismiss"),
        choice1_text = _("Turn Wi-Fi off"),
        choice1_callback = function()
            self:toggleWifiOff(complete_callback, interactive)
        end,
        choice2_text = _("Connect"),
        choice2_enabled = not self.pending_connection,
        choice2_callback = function()
            self:toggleWifiOn(complete_callback, long_press, interactive)
        end,
    })
end

function NetworkMgr:turnOnWifiAndWaitForConnection(callback)
    -- Just run the callback if WiFi is already up...
    if self:isWifiOn() and self:isConnected() then
        --- @note: beforeWifiAction only guarantees isConnected, not isOnline.
        --         In the rare cases we're isConnected but !isOnline, if we're called via a *runWhenOnline wrapper,
        --         we don't get a callback at all to avoid infinite recursion, so we need to check it.
        if callback then
            callback()
        end
        return
    end

    local info = InfoMessage:new{ text = _("Connecting to Wi-Fi…") }
    UIManager:show(info)
    UIManager:forceRePaint()

    -- NOTE: This is a slightly tweaked variant of enableWifi, in order to handle our info widget...
    local connectivity_cb = function()
        if self.pending_connectivity_check then
            self:unscheduleConnectivityCheck()
        end

        self:scheduleConnectivityCheck(callback, info)
    end
    local status = self:requestToTurnOnWifi(connectivity_cb)
    if status == false then
        logger.warn("NetworkMgr:turnOnWifiAndWaitForConnection: Connection failed!")
        self:_abortWifiConnection()
        UIManager:close(info)
        return false
    elseif status == EBUSY then
        logger.warn("NetworkMgr:turnOnWifiAndWaitForConnection: A previous connection attempt is still ongoing!")
        -- We might lose a callback in case the previous attempt wasn't from the same action,
        -- but it's just plain saner to just abort here, as we'd risk calling the same thing over and over...
        UIManager:close(info)
        return
    end

    return info
end

-- This is only used on Android, the intent being we assume the system will eventually turn on WiFi on its own in the background...
function NetworkMgr:doNothingAndWaitForConnection(callback)
    if self:isWifiOn() and self:isConnected() then
        if callback then
            callback()
        end
        return
    end

    self:scheduleConnectivityCheck(callback)
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

--- @note: The callback will only run *after* a *successful* network connection.
---        The only guarantee it provides is isConnected (i.e., an IP & a local gateway),
---        *NOT* isOnline (i.e., WAN), se be careful with recursive callbacks!
---        Should only return false on *explicit* failures,
---        in which case the backend will already have called _abortWifiConnection
function NetworkMgr:beforeWifiAction(callback)
    -- Remember that we ran, for afterWifiAction...
    self:setBeforeActionFlag()

    local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action")
    if wifi_enable_action == "turn_on" then
        return self:turnOnWifiAndWaitForConnection(callback)
    elseif wifi_enable_action == "ignore" then
        return self:doNothingAndWaitForConnection(callback)
    else
        return self:promptWifiOn(callback)
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
        self:disableWifi(callback)
    else
        self:promptWifiOff(callback)
    end
end

function NetworkMgr:isOnline()
    -- For the same reasons as isWifiOn and isConnected above, bypass this on !hasWifiToggle platforms.
    if not Device:hasWifiToggle() then
        return true
    end

    return self:canResolveHostnames()
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

-- And this one is for when you absolutely *need* to block until we're online to run something (e.g., because it runs in a finalizer).
function NetworkMgr:goOnlineToRun(callback)
    if self:isOnline() then
        callback()
        return true
    end

    -- If beforeWifiAction isn't turn_on, we're done.
    -- We don't want to go behind the user's back by enforcing "turn_on" behavior,
    -- and we *cannot* use prompt, as we'll block before handling the popup input...
    -- NOTE: Ignore *technically* works, but unlike doNothingAndWaitForConnection, we *would* be displaying an InfoMessage
    --       (and block/wait for input as usual). The only difference with turn_on would be the fact that we wouldn't *ever* even try to call turnOnWifi.
    --       Given that "ignore" is supposed to be silent, and that you wouldn't actually be able to enable WiFi yourself at that point
    --       (because that requires user input, which would cancel the whole thing), there's probably not much to gain by allowing "ignore" here...
    if G_reader_settings:readSetting("wifi_enable_action") ~= "turn_on" then
        logger.warn("NetworkMgr:goOnlineToRun: Cannot run callback because device is offline and wifi_enable_action is not turn_on")
        return false
    end

    -- We'll do terrible things with this later...
    local Input = Device.input

    -- In case we abort before the beforeWifiAction, we won't pass it the callback, but run it ourselves,
    -- to avoid it firing too late (or at the very least being pinned for too long).
    local info = self:beforeWifiAction()
    -- NOTE: Unlike turnOnWifiAndWaitForConnection, we're not reentrant,
    --       so if there's already a connection attempt pending,
    --       we can afford to *try* to wait for its success,
    --       especially since we can be cancelled.
    --       The following call *will* murder any and all pending callbacks though,
    --       which is a *slightly* different behavior than turnOnWifiAndWaitForConnection,
    --       but a necessity to ensure sane lifecycles...

    -- We'll basically do the same but in a blocking manner...
    -- NOTE: Since UIManager won't tick, they wouldn't really have a chance to run anyway...
    --       Given the constraints of our callers, they would very likely affect dead/dying objects anyway,
    --       so it's much saner to just drop them.
    self:unscheduleConnectivityCheck()

    -- If connecting just plain failed, we're done
    if info == false then
        return false
    end

    -- Throw in a connectivity check now, for the sake of hasWifiManager platforms,
    -- where we manage Wi-Fi ourselves, meaning turnOnWifi, and as such beforeWifiAction,
    -- is *blocking*, so if all went well, we'll already have blocked a while,
    -- but the connection will be up already.
    self:queryNetworkState()

    local iter = 0
    local success = true
    while not self.is_connected do
        if iter == 0 then
            -- Display a slightly more accurate IM while we wait...
            if info then
                UIManager:close(info)
            end
            info = InfoMessage:new{ text = _("Waiting for network connectivity…") }
            UIManager:show(info)
            UIManager:forceRePaint()
        end

        iter = iter + 1
        if iter >= 120 then
            logger.warn("NetworkMgr:goOnlineToRun: Timed out!")
            success = false
            break
        end

        -- NOTE: Here be dragons! We want to be able to abort on user input, so,
        --       handle the 250ms chunks of waiting via our actual input polling...
        -- We don't actually let the actual UI loop tick, so `now` will never change,
        -- which is good, we don't want to disturb the task queue handling.
        -- (And we actually want a fixed 250ms select anyway).
        -- NOTE: This *does* mean that multiple bursts of input events *will*
        --       make this loop run for less than 120 * 250ms, as select could return early.
        --       Assuming we don't actually abort *because* of said input (e.g., not taps) ;).
        local now = UIManager:getTime()
        local input_events = Input:waitEvent(now, now + time.ms(250))
        if input_events then
            for __, ev in ipairs(input_events) do
                -- We'll want to abort on actual single taps only, in case there's extra noise from stuff like a gyro or something...
                if ev.handler == "onGesture" then
                    local args = unpack(ev.args, 1, ev.args.n)
                    if args.ges == "tap" then
                        logger.warn("NetworkMgr:goOnlineToRun: Aborted by user input!")
                        success = false
                        -- No need to check further args
                        break
                    end
                end
            end
            -- Break out of the actual loop on abort
            if not success then
                break
            end
        end

        self:queryNetworkState()
    end

    -- To make our previous input shenanigans slightly less crazy, reset the whole input state.
    Input:resetState()

    -- Close the initial "Connecting..." InfoMessage from turnOnWifiAndWaitForConnection via beforeWifiAction,
    -- or our own "Waiting for network connectivity" one.
    if info then
        UIManager:close(info)
    end

    -- Check whether we connected successfully...
    if success then
        -- We're finally connected!
        logger.info("Successfully connected to Wi-Fi (after", iter * 0.25, "seconds)!")
        self.wifi_was_on = true
        G_reader_settings:makeTrue("wifi_was_on")
        callback()
        -- Delay this so it won't fire for dead/dying instances in case we're called by a finalizer...
        UIManager:scheduleIn(2, function()
            UIManager:broadcastEvent(Event:new("NetworkConnected"))
        end)
    else
        -- We're not connected :(
        logger.info("Failed to connect to Wi-Fi after", iter * 0.25, "seconds, giving up!")
        self:_abortWifiConnection()
        UIManager:show(InfoMessage:new{ text = _("Error connecting to the network") })
    end
    -- We're done, reset the pending connection flag, as we don't have any scheduled connectivity check to do it for us.
    self.pending_connection = false

    return success
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
            -- Notify TouchMenu to update item check state
            touchmenu_instance:updateItems()
        end -- complete_callback()
        if fully_connected then
            self:toggleWifiOff(complete_callback, true)
        elseif self.is_wifi_on and not self.is_connected then
            -- ask whether user wants to connect or turn off wifi
            self:promptWifi(complete_callback, long_press, true)
        else -- if not connected at all
            self:toggleWifiOn(complete_callback, long_press, true)
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
            hint = proxy(),
            callback = function(input)
                local url = require("socket.url")
                local parsed = url.parse(input)
                if not parsed or not parsed.scheme or not parsed.host or not parsed.port then
                    UIManager:show(InfoMessage:new{
                        text = _("Invalid proxy address"),
                    })
                    return false
                end
                self:setHTTPProxy(input)
            end,
        },
    }
end

function NetworkMgr:getPowersaveMenuTable()
    return {
        text = _("Disable Wi-Fi connection when inactive"),
        help_text = Device:isKindle() and _([[This is unlikely to function properly on a stock Kindle, given how much network activity the framework generates.]]) or
                    _([[This will automatically turn Wi-Fi off after a generous period of network inactivity, without disrupting workflows that require a network connection, so you can just keep reading without worrying about battery drain.]]),
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
        -- i.e., *everything* flips wifi_was_on true, but only direct user interaction (i.e., Menu & Gestures) will flip it off.
        help_text = _([[This will attempt to automatically and silently re-connect to Wi-Fi on startup or on resume if Wi-Fi used to be enabled the last time you used KOReader, and you did not explicitly disable it.]]),
        checked_func = function() return G_reader_settings:isTrue("auto_restore_wifi") end,
        enabled_func = function() return Device:hasWifiRestore() end,
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
    if Device:isAndroid() then
        wifi_enable_actions.ignore = {_("ignore"), _("Ignore")}
    end
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

    local t = {
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
    if Device:isAndroid() then
        table.insert(t.sub_item_table, action_table("ignore"))
    end

    return t
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
        enabled_func = function() return Device:hasWifiManager() or Device:isEmulator() end,
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

    if Device:hasWifiRestore() or Device:isEmulator() then
        common_settings.network_restore = self:getRestoreMenuTable()
    end
    if Device:hasWifiManager() or Device:isEmulator() then
        common_settings.network_dismiss_scan = self:getDismissScanMenuTable()
    end
    if Device:hasWifiToggle() then
        common_settings.network_before_wifi_action = self:getBeforeWifiActionMenuTable()
        common_settings.network_after_wifi_action = self:getAfterWifiActionMenuTable()
    end
end

function NetworkMgr:reconnectOrShowNetworkMenu(complete_callback, interactive)
    local info = InfoMessage:new{text = _("Scanning for networks…")}
    UIManager:show(info)
    UIManager:forceRePaint()

    local network_list, err = self:getNetworkList()
    UIManager:close(info)
    if network_list == nil then
        UIManager:show(InfoMessage:new{text = err})
        return false
    end
    -- NOTE: Fairly hackish workaround for #4387,
    --       rescan if the first scan appeared to yield an empty list.
    --- @fixme This *might* be an issue better handled in lj-wpaclient...
    if #network_list == 0 then
        logger.warn("Initial Wi-Fi scan yielded no results, rescanning")
        network_list, err = self:getNetworkList()
        if network_list == nil then
            UIManager:show(InfoMessage:new{text = err})
            return false
        end
    end

    table.sort(network_list,
        function(l, r) return l.signal_quality > r.signal_quality end)

    -- true: we're connected; false: things went kablooey; nil: we don't know yet (e.g., interactive)
    -- NOTE: false *will* lead enableWifi to kill Wi-Fi via _abortWifiConnection!
    local success
    local ssid
    -- We need to do two passes, as we may have *both* an already connected network (from the global wpa config),
    -- *and* preferred networks, and if the preferred networks have a better signal quality,
    -- they'll be sorted *earlier*, which would cause us to try to associate to a different AP than
    -- what wpa_supplicant is already trying to do...
    -- NOTE: We can't really skip this, even when we force showing the scan list,
    --       as the backend *will* connect in the background regardless of what we do,
    --       and we *need* our complete_callback to run,
    --       which would not be the case if we were to just dismiss the scan list,
    --       especially since it wouldn't show as "connected" in this case...
    for dummy, network in ipairs(network_list) do
        if network.connected then
            -- On platforms where we use wpa_supplicant (if we're calling this, we probably are),
            -- the invocation will check its global config, and if an AP configured there is reachable,
            -- it'll already have connected to it on its own.
            success = true
            ssid = network.ssid
            break
        end
    end

    -- Next, look for our own preferred networks...
    local err_msg = _("Connection failed")
    if not success then
        for dummy, network in ipairs(network_list) do
            if network.password then
                -- If we hit a preferred network and we're not already connected,
                -- attempt to connect to said preferred network....
                logger.dbg("NetworkMgr: Attempting to authenticate on preferred network", util.fixUtf8(network.ssid, "�"))
                success, err_msg = self:authenticateNetwork(network)
                if success then
                    ssid = network.ssid
                    network.connected = true
                    break
                else
                    logger.dbg("NetworkMgr: authentication failed:", err_msg)
                end
            end
        end
    end

    -- If we haven't even seen any of our preferred networks, wait a bit to see if wpa_supplicant manages to connect in the background anyway...
    -- This happens when we break too early from re-scans triggered by wpa_supplicant itself,
    -- which shouldn't really ever happen since https://github.com/koreader/lj-wpaclient/pull/11
    -- c.f., WpaClient:scanThenGetResults in lj-wpaclient for more details.
    if Device:hasWifiManager() and not success and not ssid then
        -- Don't bother if wpa_supplicant doesn't actually have any configured networks...
        local configured_networks = self:getConfiguredNetworks()
        local has_preferred_networks = configured_networks and #configured_networks > 0

        local iter = has_preferred_networks and 0 or 60
        -- We wait 15s at most (like the restore-wifi-async script)
        while not success and iter < 60 do
            -- Check every 250ms
            iter = iter + 1
            ffiutil.usleep(250 * 1e+3)

            local nw = self:getCurrentNetwork()
            if nw then
                success = true
                ssid = nw.ssid
                -- Flag it as connected in the list
                for dummy, network in ipairs(network_list) do
                    if ssid == network.ssid then
                        network.connected = true
                    end
                end
                logger.dbg("NetworkMgr: wpa_supplicant automatically connected to network", util.fixUtf8(ssid, "�"), "(after", iter * 0.25, "seconds)")
            end
        end
    end

    if success then
        self:obtainIP()
        if complete_callback then
            complete_callback()
        end
        -- NOTE: On Kindle, we don't have an explicit obtainIP implementation,
        --       and authenticateNetwork is async,
        --       so we don't *actually* have a full connection yet,
        --       we've just *started* connecting to the requested network...
        UIManager:show(InfoMessage:new{
            tag = "NetworkMgr", -- for crazy KOSync purposes
            text = T(_(Device:isKindle() and "Connecting to network %1…" or "Connected to network %1"), BD.wrap(util.fixUtf8(ssid, "�"))),
            timeout = 3,
        })
        logger.dbg("NetworkMgr: Connected to network", util.fixUtf8(ssid, "�"))
    else
        UIManager:show(InfoMessage:new{
            text = err_msg,
            timeout = 3,
        })
        logger.dbg("NetworkMgr: Failed to connect:", err_msg, "; last attempt on ssid:", ssid and util.fixUtf8(ssid, "�") or "<none>")
    end

    if not success then
        -- NOTE: Also supports a disconnect_callback, should we use it for something?
        --       Tearing down Wi-Fi completely when tapping "disconnect" would feel a bit harsh, though...
        if interactive then
            -- We don't want to display the AP list for non-interactive callers (e.g., beforeWifiAction framework)...
            UIManager:show(require("ui/widget/networksetting"):new{
                network_list = network_list,
                connect_callback = complete_callback,
            })
        else
            -- Let enableWifi tear it all down when we're non-interactive
            success = false
        end
    elseif self.wifi_toggle_long_press then
        -- Success, but we asked for the list, show it w/o any callbacks.
        -- (We *could* potentially setup a pair of callbacks that just send Network* events, but it's probably not worth it).
        UIManager:show(require("ui/widget/networksetting"):new{
            network_list = network_list,
        })
    end

    self.wifi_toggle_long_press = nil
    return success
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

if G_reader_settings:readSetting("http_proxy_enabled") and G_reader_settings:readSetting("http_proxy") then
    NetworkMgr:setHTTPProxy(G_reader_settings:readSetting("http_proxy"))
elseif G_defaults:readSetting("NETWORK_PROXY") then
    NetworkMgr:setHTTPProxy(G_defaults:readSetting("NETWORK_PROXY"))
end

return NetworkMgr:init()
