local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local menuItem = {
    text = _("Keep alive"),
    checked_func = function() return PluginShare.keepalive end,
}

local disable
local enable

local function showConfirmBox(touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = _("The system won't sleep while this message is showing.\n\nPress \"Stay alive\" if you prefer to keep the system on even after closing this notification. *This will drain the battery*.\n\nIf KOReader terminates before \"Close\" is pressed, please start and close the KeepAlive plugin again to ensure settings are reset."),
        cancel_text = _("Close"),
        cancel_callback = function()
            disable()
            PluginShare.keepalive = false
            touchmenu_instance:updateItems()
        end,
        ok_text = _("Stay alive"),
        ok_callback = function()
            PluginShare.keepalive = true
            touchmenu_instance:updateItems()
        end,
    })
end

if Device:isCervantes() or Device:isKobo() then
    enable = function() PluginShare.pause_auto_suspend = true end
    disable = function() PluginShare.pause_auto_suspend = false end
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

menuItem.callback = function(touchmenu_instance)
    enable()
    showConfirmBox(touchmenu_instance)
end

local KeepAlive = WidgetContainer:extend{
    name = "keepalive",
}

function KeepAlive:init()
    self.ui.menu:registerToMainMenu(self)
end

function KeepAlive:addToMainMenu(menu_items)
    menu_items.keep_alive = menuItem
end

return KeepAlive
