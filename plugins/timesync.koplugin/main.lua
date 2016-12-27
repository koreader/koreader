
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

if not (Device:isKobo() or Device:isKindle() or Device:isPocketbook()) then
    return { disabled = true, }
end

local TimeSync = WidgetContainer:new{
    name = "timesync",
}

local function currentTime()
    local std_out = io.popen("date")
    if std_out then
        local result = std_out:read("*all")
        std_out:close()
        return T(_("New Time is %1"), result)
    else
        return _("Time synchronized")
    end
end

local function execute()
    local txt
    if os.execute("date -u +\"YYYY-MM-DD hh:mm:ss\" \"" ..
                  "`wget -q -O - \"http://www.timeapi.org/utc/now\" | " ..
                  "sed 's/T/ /g' | sed 's/+00:00//g'`\"") ~= 0 then
        txt = _("Failed to retrieve time")
    else
        txt = currentTime()
    end
    UIManager:show(InfoMessage:new{
        text = txt,
        timeout = 3,
    })
    os.execute("if [ -f \"/sbin/hwclock\" ]; then /sbin/hwclock -w; fi")
end

local menuItem = {
    text = _("Synchronize time"),
    callback = execute,
}

function TimeSync:init()
    self.ui.menu:registerToMainMenu(self)
end

function TimeSync:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, menuItem)
end

return TimeSync
