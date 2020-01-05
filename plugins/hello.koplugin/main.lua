-- This is a debug plugin, remove the following if block to enable it
if true then
    return { disabled = true, }
end

local InfoMessage = require("ui/widget/infomessage")  -- luacheck:ignore
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Hello = WidgetContainer:new{
    name = 'hello',
    is_doc_only = false,
}

function Hello:init()
    self.ui.menu:registerToMainMenu(self)
end

function Hello:addToMainMenu(menu_items)
    menu_items.hello_world = {
        text = _("Hello World"),
        -- in which menu this should be appended
        sorting_hint = "more_plugins",
        -- a callback when tapping
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Hello, plugin world"),
            })
        end,
    }
end

return Hello
