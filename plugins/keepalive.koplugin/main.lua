
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local function showConfirmBox(disable)
    UIManager:show(ConfirmBox:new{
        text = _("The system won't sleep when this message is showing.\nPress \"Stay Alive\" if you prefer to keep system on even after closing this notification. *It will drain the battery.*\n\nIf for any reasons KOReader died before \"Close\" is pressed, please start and close KeepAlive plugin again to ensure settings are reset."),
        ok_text = _("Close"),
        ok_callback = disable,
        cancel_text = _("Stay Alive"),
    })
end

local menuItem = {
    text = _("Keep Alive"),
}

if Device:isKobo() then
    disable = function() UIManager:_startAutoSuspend() end
    menuItem.callback = function()
        UIManager:_stopAutoSuspend()
        showConfirmBox(disable)
    end
elseif Device:isKindle() then
    disable = function()
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    end
    menuItem.callback = function()
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
        showConfirmBox(disable)
    end
else
    return { disabled = true, }
end

local KeepAlive = WidgetContainer:new{
    name = "keepalive",
}

function KeepAlive:init()
    self.ui.menu:registerToMainMenu(self)
end

function KeepAlive:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, menuItem)
end

return KeepAlive
