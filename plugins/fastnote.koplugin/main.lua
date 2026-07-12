--[[--
FastNote entry point.

Routing on open (Stage 9):
  • 0 notebooks  → create "My Notebook", open canvas directly (first launch)
  • 1 notebook   → open canvas directly (skip browser)
  • 2+ notebooks → show notebook browser
--]]--

local Dispatcher      = require("dispatcher")  -- luacheck:ignore
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas   = require("drawingcanvas")
local _               = require("gettext")

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
-- Internal: open a canvas for a specific notebook + page
-- ---------------------------------------------------------------------------

function FastNote:_openCanvas(lib, state, nb, page_idx)
    local load_path = nb:pagePath(page_idx)

    -- Load user config (lib/config.lua): finger_draw / rotation_mode /
    -- tighten_delay / tighten_enabled / live_color_refresh / eraser_button /
    -- live_ink_style / debug_input_log.
    -- Missing file or keys fall back to Config.DEFAULTS -- see
    -- .agents/notes/tech-debt.md.
    local Config      = require("lib/config")
    local DataStorage = require("datastorage")
    local conf_path   = DataStorage:getDataDir() .. "/settings/fastnote.conf"
    local cfg         = Config.load(conf_path)

    UIManager:show(DrawingCanvas:new{
        load_path      = load_path,
        page_index     = page_idx,
        page_count     = nb:pageCount(),
        dark_mode      = state.dark_mode == 1,
        current_color  = state.current_color,
        pressure_floor = state.pressure_floor,

        finger_draw         = cfg.finger_draw,
        init_rotation_mode  = cfg.rotation_mode,
        tighten_delay       = cfg.tighten_delay,
        tighten_enabled     = cfg.tighten_enabled,
        live_color_refresh  = cfg.live_color_refresh,
        eraser_button       = cfg.eraser_button,
        live_ink_style      = cfg.live_ink_style,
        debug_input_log     = cfg.debug_input_log,

        on_save_callback = function(path)
            nb.last_edited           = os.time()
            nb:save()
            state.last_notebook_uuid = nb.uuid
            state.last_page_index    = page_idx
            lib:writeState(state)
        end,

        on_dark_mode_change = function(dm)
            state.dark_mode = dm and 1 or 0
            lib:writeState(state)
        end,

        on_color_change = function(hex)
            state.current_color = hex
            lib:writeState(state)
        end,

        on_pressure_change = function(val)
            state.pressure_floor = val
            lib:writeState(state)
        end,

        on_show_browser = function()
            self:_showBrowser(lib, state)
        end,

        on_page_forward = function()
            page_idx = page_idx + 1
            if page_idx > nb:pageCount() then
                nb:addPage()
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

-- ---------------------------------------------------------------------------
-- Internal: show the notebook browser
-- ---------------------------------------------------------------------------

function FastNote:_showBrowser(lib, state)
    local Browser = require("ui/browser")
    Browser.show(lib, function(nb)
        local page_idx = 1
        if state.last_notebook_uuid == nb.uuid then
            page_idx = state.last_page_index or 1
        end
        page_idx = math.max(1, math.min(page_idx, nb:pageCount()))
        self:_openCanvas(lib, state, nb, page_idx)
    end)
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

function FastNote:onOpenFnoteCanvas()
    local DataStorage = require("datastorage")
    local base_dir    = DataStorage:getDataDir() .. "/fastnote"

    local logger = require("logger")
    logger.info("FastNote: data directory =", base_dir)

    local Library = require("model/library")
    local lib     = Library.new(base_dir)
    local state   = lib:readState()

    local count = lib:notebookCount()

    if count == 0 then
        -- First launch: create a default notebook and go straight to canvas.
        local nb = lib:createNotebook("My Notebook")
        self:_openCanvas(lib, state, nb, 1)

    elseif count == 1 then
        -- Single notebook: skip browser.
        local nb       = lib:byIndex(1)
        local page_idx = 1
        if state.last_notebook_uuid == nb.uuid then
            page_idx = state.last_page_index or 1
        end
        page_idx = math.max(1, math.min(page_idx, nb:pageCount()))
        self:_openCanvas(lib, state, nb, page_idx)

    else
        -- Multiple notebooks: show browser.
        self:_showBrowser(lib, state)
    end
end

return FastNote
