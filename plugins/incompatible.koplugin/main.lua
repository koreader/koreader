--[[--
This is a debug plugin to test Plugin functionality.

@module koplugin.Incompatible
--]]
--

-- TODO: it would be nice to auto load this if an env variable is set
-- This is a debug plugin, remove the following if block to enable it
if false then
    return { disabled = true }
end

local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Incompatible = WidgetContainer:extend({
    name = "Incompatible",
    is_doc_only = false,
})

function Incompatible:onDispatcherRegisterActions()
    Dispatcher:registerAction(
        "incompatible_action",
        { category = "none", event = "Incompatible", title = _("Incompatible"), general = true }
    )
end

function Incompatible:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Incompatible:addToMainMenu(menu_items)
    menu_items.incompatible_plugin = {
        text = _("Incompatible Plugin"),
        -- in which menu this should be appended
        sorting_hint = "more_tools",
        -- a callback when tapping
        callback = function()
            UIManager:show(InfoMessage:new({
                text = _("Incompatible Plugin activated"),
            }))
        end,
    }
end

function Incompatible:onIncompatiblePlugin()
    local popup = InfoMessage:new({
        text = _("Incompatible Plugin activated"),
    })
    UIManager:show(popup)
end

return Incompatible
