local Device = require("device")

local command
-- TODO(hzj-jie): Does pocketbook provide ntpdate?
if Device:isKobo() then
    command = "ntpd -q -n -p pool.ntp.org"
elseif Device:isKindle() or Device:isPocketBook() then
    command = "ntpdate pool.ntp.org"
else
    return { disabled = true, }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")

local TimeSync = WidgetContainer:new{
    name = "timesync",
    fullname = _("Time sync"),
    description = _([[Synchronizes the device time with NTP servers.]]),
}

local function currentTime()
    local std_out = io.popen("date")
    if std_out then
        local result = std_out:read("*all")
        std_out:close()
        if result ~= nil then
            result = result:gsub("\n", "")
            return T(_("New time is %1."), result)
        end
    end
    return _("Time synchronized.")
end

local function execute()
    local info = InfoMessage:new{
        text = _("Synchronizing time. This may take several seconds.")
    }
    UIManager:show(info)
    UIManager:forceRePaint()
    local txt
    if os.execute(command) ~= 0 then
        txt = _("Failed to retrieve time from server. Please check your network configuration.")
    else
        txt = currentTime()
    end
    os.execute("hwclock -u -w")
    UIManager:close(info)
    UIManager:show(InfoMessage:new{
        text = txt,
        timeout = 3,
    })
end

local menuItem = {
    text = _("Synchronize time"),
    callback = function()
        if NetworkMgr:isOnline() then
            execute()
        else
            NetworkMgr:promptWifiOn()
        end
    end
}

function TimeSync:init()
    self.ui.menu:registerToMainMenu(self)
end

function TimeSync:addToMainMenu(menu_items)
    menu_items.synchronize_time = menuItem
end

return TimeSync
