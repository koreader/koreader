--[[--
This is a plugin for quick notes with pen input.

@module koplugin.FastNote
--]]--


local Dispatcher = require("dispatcher")  -- luacheck:ignore
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas = require("drawingcanvas")
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
        sorting_hint = "more_tools",
        callback = function()
            self:onOpenFnoteCanvas()
        end,
    }
end

function FastNote:onOpenFnoteCanvas()
    UIManager:show(DrawingCanvas:new{})
end

return FastNote
