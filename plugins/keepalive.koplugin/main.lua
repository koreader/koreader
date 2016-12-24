
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KeepAlive = WidgetContainer:new{
    name = "keepalive",
}

function KeepAlive:init()
    if Device:isKobo() then
        self.enable = function() UIManager:_stopAutoSuspend() end
    elseif Device:isKindle() then
        self.enable = function()
            os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
        end
    else
        self.enable = nil
    end

    if Device:isKobo() then
        self.disable = function() UIManager:_startAutoSuspend() end
    elseif Device:isKindle() then
        self.disable = function()
            os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
        end
    else
        self.disable = nil
    end

    self.ui.menu:registerToMainMenu(self)
end

function KeepAlive:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Keep Alive"),
        callback = function()
            if self.enable ~= nil and self.disable ~= nil then
                self.enable()
                UIManager:show(ConfirmBox:new{
                    text = _("The system won't sleep when this message is showing.\nPress \"Stay Alive\" if you prefer to keep system on even after closing this notification. *It will drain the battery.*\n\nIf for any reasons KOReader died before \"Close\" is pressed, please start and close KeepAlive plugin again to ensure settings are reset."),
                    ok_text = _("Close"),
                    ok_callback = self.disable,
                    cancel_text = _("Stay Alive"),
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("KeepAlive plugin does not support your system."),
                    timeout = 3,
                })
            end
        end
    })
end

return KeepAlive
