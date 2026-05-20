--[[--
FastNote entry point.

Routing on open:
  • No notebooks yet   → create "My Notebook", open page 1
  • state.lua present  → open last notebook at last page (if still on disk)
  • Otherwise          → open the first notebook at page 1

Stage 9 will replace this with a full notebook browser.
--]]--

local Dispatcher    = require("dispatcher")  -- luacheck:ignore
local UIManager     = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas = require("drawingcanvas")
local _             = require("gettext")

local FastNote = WidgetContainer:extend{
    name        = "fastnote",
    is_doc_only = false,
}

function FastNote:onDispatcherRegisterActions()
    Dispatcher:registerAction("open_fnote_canvas", {
        category = "none",
        event    = "OpenFnoteCanvas",
        title    = _("Open Fast Note Canvas"),
        general  = true,
    })
end

function FastNote:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function FastNote:addToMainMenu(menu_items)
    menu_items.fast_note = {
        text         = _("Fast Note"),
        sorting_hint = "more_tools",
        callback     = function() self:onOpenFnoteCanvas() end,
    }
end

-- ---------------------------------------------------------------------------

function FastNote:onOpenFnoteCanvas()
    local DataStorage = require("datastorage")
    local base_dir    = DataStorage:getDataDir() .. "/fastnote"

    local Library  = require("model/library")
    local lib      = Library.new(base_dir)
    local state    = lib:readState()

    -- Find the notebook and page to open.
    local nb        = nil
    local page_idx  = 1

    if state.last_notebook_uuid then
        nb        = lib:byUUID(state.last_notebook_uuid)
        page_idx  = state.last_page_index or 1
    end

    if not nb then
        nb = lib:byIndex(1)  -- first notebook if any
    end

    if not nb then
        nb = lib:createNotebook("My Notebook")  -- first launch
    end

    -- Clamp page index to valid range.
    page_idx = math.max(1, math.min(page_idx, nb:pageCount()))

    local load_path = nb:pagePath(page_idx)

    UIManager:show(DrawingCanvas:new{
        load_path  = load_path,
        page_index = page_idx,
        page_count = nb:pageCount(),

        on_save_callback = function(path)
            state.last_notebook_uuid = nb.uuid
            state.last_page_index    = page_idx
            lib:writeState(state)
        end,

        -- Stage 8: hardware page-button navigation.
        -- Each callback mutates the page_idx upvalue and returns the new state.

        on_page_forward = function()
            page_idx = page_idx + 1
            if page_idx > nb:pageCount() then
                nb:addPage()  -- creates the new page file slot
            end
            page_idx = math.min(page_idx, nb:pageCount())
            local path = nb:pagePath(page_idx)
            state.last_notebook_uuid = nb.uuid
            state.last_page_index    = page_idx
            lib:writeState(state)
            return page_idx, nb:pageCount(), path
        end,

        on_page_back = function()
            if page_idx <= 1 then return nil end
            page_idx = page_idx - 1
            local path = nb:pagePath(page_idx)
            state.last_notebook_uuid = nb.uuid
            state.last_page_index    = page_idx
            lib:writeState(state)
            return page_idx, nb:pageCount(), path
        end,
    })
end

return FastNote
