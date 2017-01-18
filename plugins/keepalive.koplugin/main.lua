
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local menuItem = {
    text = _("Keep alive"),
    checked = false,
}

local disable
local enable

local function showConfirmBox()
    UIManager:show(ConfirmBox:new{
        text = _("The system won't sleep when this message is showing.\nPress \"Stay alive\" if you prefer to keep system on even after closing this notification. *It will drain the battery.*\n\nIf for any reasons KOReader died before \"Close\" is pressed, please start and close KeepAlive plugin again to ensure settings are reset."),
        ok_text = _("Close"),
        ok_callback = function()
            disable()
            menuItem.checked =false
        end,
        cancel_text = _("Stay alive"),
        cancel_callback = function()
            menuItem.checked = true
        end,
    })
end

if Device:isKobo() then
    disable = function() UIManager:_startAutoSuspend() end
    enable = function() UIManager:_stopAutoSuspend() end
elseif Device:isKindle() then
    disable = function()
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    end
    enable = function()
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
    end
elseif Device:isSDL() then
    local InfoMessage = require("ui/widget/infomessage")
    disable = function()
        UIManager:show(InfoMessage:new{
            text = _("This is a dummy implementation of 'disable' function.")
        })
    end
    enable = function()
        UIManager:show(InfoMessage:new{
            text = _("This is a dummy implementation of 'enable' function.")
        })
    end
else
    return { disabled = true, }
end

menuItem.callback = function()
    enable()
    showConfirmBox()
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
