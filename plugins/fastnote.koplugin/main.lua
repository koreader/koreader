--[[--
This is a plugin for quick notes with pen input.

@module koplugin.FastNote
--]]--


local Dispatcher = require("dispatcher")  -- luacheck:ignore
local DrawingCanvas = require("drawingcanvas")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
    local canvas = DrawingCanvas:new{
        on_close_callback = function()
            -- Canvas closed; nothing to do at Stage 1
        end,
    }
    UIManager:show(canvas)
end

return FastNote
