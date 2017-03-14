
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local ReadTimer = WidgetContainer:new{
    name = "readtimer",
    time = 0,  -- The expected time of alarm if enabled, or 0.
}

function ReadTimer:init()
    self.alarm_callback = function()
        if self.time == 0 then return end -- How could this happen?
        UIManager:show(InfoMessage:new{
            text = T(_("Time's up\nIt's %1 now."), os.date("%c", self.time)),
            timeout = 10,
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Read timer"),
        callback = function()
            if self.time ~= 0 then
            else
            end
        end,
    })
end
