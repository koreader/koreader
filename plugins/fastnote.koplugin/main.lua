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

-- ---------------------------------------------------------------------------
-- State persistence: remember the last saved page across sessions.
-- ---------------------------------------------------------------------------

local function _statePath()
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir() .. "/fastnote/state.lua"
end

local function _readState()
    local path = _statePath()
    local chunk, err = loadfile(path)
    if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

local function _writeState(t)
    local DataStorage = require("datastorage")
    local dir = DataStorage:getDataDir() .. "/fastnote/"
    os.execute("mkdir -p " .. dir)
    local f = io.open(_statePath(), "w")
    if not f then return end
    f:write("return {\n")
    for k, v in pairs(t) do
        if type(v) == "string" then
            f:write(string.format("  %s = %q,\n", k, v))
        end
    end
    f:write("}\n")
    f:close()
end

-- ---------------------------------------------------------------------------

function FastNote:onOpenFnoteCanvas()
    -- Restore the last page, if it still exists on disk.
    local state     = _readState()
    local load_path = state.last_page_path
    if load_path then
        local chk = io.open(load_path, "r")
        if chk then chk:close() else load_path = nil end
    end

    UIManager:show(DrawingCanvas:new{
        load_path = load_path,
        on_save_callback = function(path)
            local s = _readState()
            s.last_page_path = path
            _writeState(s)
        end,
    })
end

return FastNote
