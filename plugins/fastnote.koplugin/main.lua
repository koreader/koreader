--[[--
This is a plugin for quick notes with pen input.

@module koplugin.FastNote
--]]--


local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas = require("plugins/fastnote.koplugin/drawingcanvas")
local _ = require("gettext")

local FastNote = WidgetContainer:extend{
    name = "fastnote",
    is_doc_only = false,
}

function FastNote:onDispatcherRegisterActions()
    Dispatcher:registerAction("open_fnote_canvas", {category="none", event="OpenFnoteCanvas", title=_("Open Fast Note Canvas"), general=true,})
end

function FastNote:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function FastNote:addToMainMenu(menu_items)
    menu_items.fast_note = {
        text = _("Fast Note"),
        -- in which menu this should be appended
        sorting_hint = "more_tools",
        -- a callback when tapping
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Hello, plugin world -FastNote"),
            })
        end,
    }
end

function FastNote:onOpenFnoteCanvas()
    local popup = InfoMessage:new{
        text = _("Fast Note Canvas first message confirmed!"),
    }
    UIManager:show(popup)
end

return FastNote
