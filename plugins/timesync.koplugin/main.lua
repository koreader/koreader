local Device = require("device")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
require("ffi/posix_h")

-- We need to be root to be able to set the time (CAP_SYS_TIME)
if C.getuid() ~= 0 then
    return { disabled = true, }
end

local ntp_cmd
-- Check if we have access to ntpd or ntpdate
local ntpd = util.which("ntpd")
if ntpd then
    -- Make sure it's actually busybox's implementation, as the syntax may otherwise differ...
    -- (Of particular note, Kobo ships busybox ntpd, but not ntpdate; and Kindle ships ntpdate and !busybox ntpd).
    local sym = lfs.symlinkattributes(ntpd)
    if sym and sym.mode == "link" and string.sub(sym.target, -7) == "busybox" then
        ntp_cmd = "ntpd -q -n -p pool.ntp.org"
    end
end
if not ntp_cmd and util.which("ntpdate") then
    ntp_cmd = "ntpdate pool.ntp.org"
end
if not ntp_cmd then
    return { disabled = true, }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")

local TimeSync = WidgetContainer:extend{
    name = "timesync",
}

local function currentTime()
    local std_out = io.popen("date")
    if std_out then
        local result = std_out:read("*line")
        std_out:close()
        if result ~= nil then
            return T(_("New time is %1."), result)
        end
    end
    return _("Time synchronized.")
end

local function syncNTP()
    local info = InfoMessage:new{
        text = _("Synchronizing time. This may take several seconds.")
    }
    UIManager:show(info)
    UIManager:forceRePaint()
    local txt
    if os.execute(ntp_cmd) ~= 0 then
        txt = _("Failed to retrieve time from server. Please check your network configuration.")
    else
        txt = currentTime()
        os.execute("hwclock -u -w")

        -- On Kindle, do it the native way, too, to make sure the native UI gets the memo...
        if Device:isKindle() and lfs.attributes("/usr/sbin/setdate", "mode") == "file" then
            os.execute(string.format("/usr/sbin/setdate '%d'", os.time()))
        end
    end
    UIManager:close(info)
    UIManager:show(InfoMessage:new{
        text = txt,
        timeout = 3,
    })
end

local menuItem = {
    text = _("Synchronize time"),
    keep_menu_open = true,
    callback = function()
        NetworkMgr:runWhenOnline(function() syncNTP() end)
    end
}

function TimeSync:init()
    self.ui.menu:registerToMainMenu(self)
end

function TimeSync:addToMainMenu(menu_items)
    menu_items.synchronize_time = menuItem
end

return TimeSync
