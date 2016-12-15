local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Hello = WidgetContainer:new{
    name = 'Hello',
    docless = true,
    disabled = true,  -- This is a debug plugin
}

function Hello:init()
    self.ui.menu:registerToMainMenu(self)
end

function Hello:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Hello World"),
        callback_func = function()
            UIManager:show(InfoMessage:new{
                text = _("Hello, docless plugin world"),
            })
        end,
    })
end

return Hello
