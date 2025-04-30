local Device = require("device")
local DocCache = require("document/doccache")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderZooming = InputContainer:extend{
    zoom = 1.0,
    -- This flag is used to disable/ignore all zooming events and not update
    -- any zoom or zoom mode etc.
    -- The caller is, however, responsible for setting the rigth settings before disabling.
    disabled = false,
    available_zoom_modes = { -- const
        "page",
        "pagewidth",
        "pageheight",
        "content",
        "contentwidth",
        "contentheight",
        "columns",
        "rows",
        "manual",
    },
    zoom_mode_label = { -- const
        page          = _("page") .. " - " .. _("full"),
        pagewidth     = _("page") .. " - " .. _("width"),
        pageheight    = _("page") .. " - " .. _("height"),
        content       = _("content") .. " - " .. _("full"),
        contentwidth  = _("content") .. " - " .. _("width"),
        contentheight = _("content") .. " - " .. _("height"),
        columns       = _("columns"),
        rows          = _("rows"),
        manual        = _("manual"),
    },
    zoom_genus_to_mode = { -- const
        [4] = "page",
        [3] = "content",
        [2] = "columns",
        [1] = "rows",
        [0] = "manual",
    },
    zoom_mode_to_genus = { -- const
        page    = 4,
        content = 3,
        columns = 2,
        rows    = 1,
        manual  = 0,
    },
    zoom_type_to_mode = { -- const
        [2] = "",
        [1] = "width",
        [0] = "height",
    },
    zoom_mode_to_type = { -- const
        [""]   = 2,
        width  = 1,
        height = 0,
    },
    -- default to nil so we can trigger ZoomModeUpdate events on start up
    zoom_mode = nil,
    DEFAULT_ZOOM_MODE = "pagewidth",
    -- for pan mode: fit to width/zoom_factor,
    -- with overlap of zoom_overlap_h % (horizontally)
    -- and zoom_overlap_v % (vertically).
    kopt_zoom_factor = 1.5,
    zoom_overlap_h = 40,
    zoom_overlap_v = 40,
    zoom_bottom_to_top = nil,  -- true for bottom-to-top
    zoom_direction_vertical = nil, -- true for column mode
    zoom_direction_settings = { -- const
        [7] = {right_to_left = false, zoom_bottom_to_top = false, zoom_direction_vertical = false},
        [6] = {right_to_left = false, zoom_bottom_to_top = false, zoom_direction_vertical = true },
        [5] = {right_to_left = false, zoom_bottom_to_top = true,  zoom_direction_vertical = false},
        [4] = {right_to_left = false, zoom_bottom_to_top = true,  zoom_direction_vertical = true },
        [3] = {right_to_left = true,  zoom_bottom_to_top = true,  zoom_direction_vertical = true },
        [2] = {right_to_left = true,  zoom_bottom_to_top = true,  zoom_direction_vertical = false},
        [1] = {right_to_left = true,  zoom_bottom_to_top = false, zoom_direction_vertical = true },
        [0] = {right_to_left = true,  zoom_bottom_to_top = false, zoom_direction_vertical = false},
    },
    current_page = 1,
    rotation = 0,
    paged_modes = { -- const
        page = _("Zoom to fit page works best with page view."),
        pageheight = _("Zoom to fit page height works best with page view."),
        contentheight = _("Zoom to fit content height works best with page view."),
        content = _("Zoom to fit content works best with page view."),
        columns = _("Zoom to fit columns works best with page view."),
    },
}

function ReaderZooming:init()
    self:registerKeyEvents()
end

function ReaderZooming:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events = {
            ZoomIn = {
                { "Shift", Input.group.PgFwd },
                event = "Zoom",
                args = "in",
            },
            ZoomOut = {
                { "Shift", Input.group.PgBack },
                event = "Zoom",
                args = "out",
            },
            ZoomToFitPage = {
                { "A" },
                event = "SetZoomMode",
                args = "page",
            },
            ZoomToFitContent = {
                { "Shift", "A" },
                event = "SetZoomMode",
                args = "content",
            },
            ZoomToFitPageWidth = {
                { "S" },
                event = "SetZoomMode",
                args = "pagewidth",
            },
            ZoomToFitContentWidth = {
                { "Shift", "S" },
                event = "SetZoomMode",
                args = "contentwidth",
            },
            ZoomToFitPageHeight = {
                { "D" },
                event = "SetZoomMode",
                args = "pageheight",
            },
            ZoomToFitContentHeight = {
                { "Shift", "D" },
                event = "SetZoomMode",
                args = "contentheight",
            },
            ZoomManual = {
                { "Shift", "M" },
                event = "SetZoomMode",
                args = "manual",
            },
        }
    end
end

ReaderZooming.onPhysicalKeyboardConnected = ReaderZooming.registerKeyEvents

-- Conversions between genus/type combos and zoom_mode...
function ReaderZooming:mode_to_combo(zoom_mode)
    if not zoom_mode then
        zoom_mode = self.DEFAULT_ZOOM_MODE
    end

    -- Quick'n dirty zoom_mode to genus/type conversion...
    local zgenus, ztype = zoom_mode:match("^(page)(%l*)$")
    if not zgenus then
        zgenus, ztype = zoom_mode:match("^(content)(%l*)$")
    end
    if not zgenus then
        zgenus = zoom_mode
    end
    if not ztype then
        ztype = ""
    end

    local zoom_mode_genus = self.zoom_mode_to_genus[zgenus]
    local zoom_mode_type = self.zoom_mode_to_type[ztype]

    return zoom_mode_genus, zoom_mode_type
end

function ReaderZooming:combo_to_mode(zoom_mode_genus, zoom_mode_type)
    local default_genus, default_type = self:mode_to_combo(self.DEFAULT_ZOOM_MODE)
    if not zoom_mode_genus then
        zoom_mode_genus = default_genus
    end
    if not zoom_mode_type then
        zoom_mode_type = default_type
    end

    local zoom_genus = self.zoom_genus_to_mode[zoom_mode_genus]
    local zoom_type = self.zoom_type_to_mode[zoom_mode_type]

    local zoom_mode
    if zoom_genus == "page" or zoom_genus == "content" then
        zoom_mode = zoom_genus .. zoom_type
    else
        zoom_mode = zoom_genus
    end

    return zoom_mode
end

-- Update the genus/type Configurables given a specific zoom_mode...
function ReaderZooming:_updateConfigurable(zoom_mode)
    -- We may need to poke at the Configurable directly, because ReaderConfig is instantiated before us,
    -- so simply updating the DocSetting doesn't cut it...
    -- Technically ought to be conditional,
    -- because this is an optional engine feature (only if self.document.info.configurable is true).
    -- But the rest of the code (as well as most other modules) assumes this is supported on all paged engines (it is).
    local configurable = self.document.configurable

    local zoom_mode_genus, zoom_mode_type = self:mode_to_combo(zoom_mode)

    -- FIXME(ogkevin): when zoom_mode is "free", zoom_mode_genus is nil
    -- This is because in the mode_to_combo maping, free doesn't exsit.
    -- Manual does, but is free and manual the same thing?
    logger.dbg("ReaderZooming:_updateConfigurable", zoom_mode, zoom_mode_genus, zoom_mode_type)

    -- Configurable keys aren't prefixed, unlike the actual settings...
    -- TODO(ogkevin): hack for nil zoom_mode_genus, needs confirmation if accaptable
    configurable.zoom_mode_genus = zoom_mode_genus and zoom_mode_genus or 0
    configurable.zoom_mode_type = zoom_mode_type

    return zoom_mode_genus, zoom_mode_type
end

function ReaderZooming:onReadSettings(config)
    -- If we have a composite zoom_mode stored, use that
    local zoom_mode = config:readSetting("zoom_mode")

    if zoom_mode then
        -- Validate it first
        zoom_mode = self.zoom_mode_label[zoom_mode] and zoom_mode or self.DEFAULT_ZOOM_MODE

        -- Make sure the split genus & type match, to have an up-to-date ConfigDialog...
        local zoom_mode_genus, zoom_mode_type = self:_updateConfigurable(zoom_mode)
        config:saveSetting("kopt_zoom_mode_genus", zoom_mode_genus)
        config:saveSetting("kopt_zoom_mode_type", zoom_mode_type)
    else
        -- Otherwise, build it from the split genus & type settings
        local zoom_mode_genus = config:readSetting("kopt_zoom_mode_genus")
                             or G_reader_settings:readSetting("kopt_zoom_mode_genus")
                             or 3 -- autocrop is default then pagewidth will be the default as well
        local zoom_mode_type = config:readSetting("kopt_zoom_mode_type")
                            or G_reader_settings:readSetting("kopt_zoom_mode_type")
        zoom_mode = self:combo_to_mode(zoom_mode_genus, zoom_mode_type)

        -- Validate it
        zoom_mode = self.zoom_mode_label[zoom_mode] and zoom_mode or self.DEFAULT_ZOOM_MODE
    end

    -- Import legacy zoom_factor settings
    if config:has("zoom_factor") and config:hasNot("kopt_zoom_factor") then
        config:saveSetting("kopt_zoom_factor", config:readSetting("zoom_factor"))
        self.document.configurable.zoom_factor = config:readSetting("kopt_zoom_factor")
        config:delSetting("zoom_factor")
    elseif config:has("zoom_factor") and config:has("kopt_zoom_factor") then
        config:delSetting("zoom_factor")
    end

    -- Don't stomp on normal_zoom_mode in ReaderKoptListener if we're reflowed...
    local is_reflowed = config:has("kopt_text_wrap") and config:readSetting("kopt_text_wrap") == 1

    self:setZoomMode(zoom_mode, true, is_reflowed) -- avoid informative message on load

    self.kopt_zoom_factor = config:readSetting("kopt_zoom_factor")
                            or G_reader_settings:readSetting("kopt_zoom_factor") or self.kopt_zoom_factor
    self.zoom_overlap_h = config:readSetting("kopt_zoom_overlap_h")
                            or G_reader_settings:readSetting("kopt_zoom_overlap_h") or self.zoom_overlap_h
    self.zoom_overlap_v = config:readSetting("kopt_zoom_overlap_v")
                            or G_reader_settings:readSetting("kopt_zoom_overlap_v") or self.zoom_overlap_v

    -- update zoom direction parameters
    local zoom_direction_setting = self.zoom_direction_settings[self.document.configurable.zoom_direction
                                                                or G_reader_settings:readSetting("kopt_zoom_direction") or 7]
    self.zoom_bottom_to_top = zoom_direction_setting.zoom_bottom_to_top
    self.zoom_direction_vertical = zoom_direction_setting.zoom_direction_vertical
end

function ReaderZooming:onSaveSettings()
    self.ui.doc_settings:saveSetting("zoom_mode", self.orig_zoom_mode or self.zoom_mode)
end

function ReaderZooming:onSpread(arg, ges)
    if self.disabled then
        return
    end

    if ges.direction == "horizontal" then
        self:genSetZoomModeCallBack("contentwidth")()
    elseif ges.direction == "vertical" then
        self:genSetZoomModeCallBack("contentheight")()
    elseif ges.direction == "diagonal" then
        self:genSetZoomModeCallBack("content")()
    end
    return true
end

function ReaderZooming:onPinch(arg, ges)
    if self.disabled then
        return
    end

    if ges.direction == "diagonal" then
        self:genSetZoomModeCallBack("page")()
    elseif ges.direction == "horizontal" then
        self:genSetZoomModeCallBack("pagewidth")()
    elseif ges.direction == "vertical" then
        self:genSetZoomModeCallBack("pageheight")()
    end
    return true
end

function ReaderZooming:onToggleFreeZoom(arg, ges)
    if self.disabled then
        return
    end

    if self.zoom_mode ~= "free" then
        self.orig_zoom = self.zoom
        local xpos, ypos
        self.zoom, xpos, ypos = self:getRegionalZoomCenter(self.current_page, ges.pos)
        logger.info("zoom center", self.zoom, xpos, ypos)
        self.ui:handleEvent(Event:new("SetZoomMode", "free"))
        if xpos == nil or ypos == nil then
            xpos = ges.pos.x * self.zoom / self.orig_zoom
            ypos = ges.pos.y * self.zoom / self.orig_zoom
        end
        self.view:SetZoomCenter(xpos, ypos)
    else
        self.ui:handleEvent(Event:new("SetZoomMode", "page"))
    end
end

-- This event is send on screen size change, therefore self.dimen is the size of the screen
function ReaderZooming:onSetDimensions(dimensions)
    -- we were resized
    self.dimen = dimensions
    self:setZoom()
end

function ReaderZooming:onRestoreDimensions(dimensions)
    -- we were resized
    self.dimen = dimensions
    self:setZoom()
end

--- @note: From ReaderRotation, which was broken, and has been removed in #12658
function ReaderZooming:onRotationUpdate(rotation)
    self.rotation = rotation
    self:setZoom()
end

function ReaderZooming:onZoom(direction)
    logger.dbg("ReaderZooming:onZoom", direction, "enabled", not self.disabled)

    if self.disabled then
        return
    end

    logger.info("zoom", direction)
    if direction == "in" then
        self.zoom = self.zoom * 1.333333
    elseif direction == "out" then
        self.zoom = self.zoom * 0.75
    end
    logger.info("zoom is now at", self.zoom)
    self:onSetZoomMode("free")
    self.view:onZoomUpdate(self.zoom)
    return true
end

function ReaderZooming:onDefineZoom(btn, when_applied_callback)
    if self.disabled then
        return
    end

    local config = self.ui.document.configurable
    local zoom_direction_setting = self.zoom_direction_settings[config.zoom_direction]
    local settings = { -- unpack the table, work on a local copy
        right_to_left = zoom_direction_setting.right_to_left,
        zoom_bottom_to_top = zoom_direction_setting.zoom_bottom_to_top,
        zoom_direction_vertical = zoom_direction_setting.zoom_direction_vertical,
    }
    local zoom_range_number = config.zoom_range_number
    local zoom_factor = config.zoom_factor
    local zoom_mode_genus = self.zoom_genus_to_mode[config.zoom_mode_genus]
    local zoom_mode_type = self.zoom_type_to_mode[config.zoom_mode_type]
    settings.zoom_overlap_h = config.zoom_overlap_h
    settings.zoom_overlap_v = config.zoom_overlap_v
    if btn == "set_zoom_overlap_h" then
        self:_zoomPanChange(_("Set horizontal overlap"), "zoom_overlap_h")
        settings.zoom_overlap_h = self.zoom_overlap_h
    elseif btn == "set_zoom_overlap_v" then
        self:_zoomPanChange(_("Set vertical overlap"), "zoom_overlap_v")
        settings.zoom_overlap_v = self.zoom_overlap_v
    end

    local zoom_mode
    if zoom_mode_genus == "page" or zoom_mode_genus == "content" then
        zoom_mode = zoom_mode_genus .. zoom_mode_type
    else
        zoom_mode = zoom_mode_genus
        self.ui:handleEvent(Event:new("SetScrollMode", false))
    end
    zoom_mode = self.zoom_mode_label[zoom_mode] and zoom_mode or self.DEFAULT_ZOOM_MODE
    settings.zoom_mode = zoom_mode

    if settings.right_to_left then
        if settings.zoom_bottom_to_top then
            config.writing_direction = 2
        else
            config.writing_direction = 1
        end
    else
        config.writing_direction = 0
    end
    settings.right_to_left = nil

    if zoom_mode == "columns" or zoom_mode == "rows" then
        if btn ~= "columns" and btn ~= "rows" then
            self.ui:handleEvent(Event:new("SetZoomPan", settings, true))
            config.zoom_factor = self:setNumberOf(
                zoom_mode,
                zoom_range_number,
                zoom_mode == "columns" and settings.zoom_overlap_h or settings.zoom_overlap_v
            )
            settings.kopt_zoom_factor = config.zoom_factor
        end
    elseif zoom_mode == "manual" then
        if btn == "manual" then
            config.zoom_factor = self:getNumberOf("columns")
            settings.kopt_zoom_factor = config.zoom_factor
            -- We *want* a redraw the first time we swap to manual mode (like any other mode swap)
            self.ui:handleEvent(Event:new("SetZoomPan", settings))
        else
            self:setNumberOf("columns", zoom_factor)
            -- No redraw here, because setNumberOf already took care of it
            self.ui:handleEvent(Event:new("SetZoomPan", settings, true))
        end
    end
    self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode))
    if btn == "columns" or btn == "rows" then
        config.zoom_range_number = self:getNumberOf(
            zoom_mode,
            btn == "columns" and settings.zoom_overlap_h or settings.zoom_overlap_v
        )
    end
    if when_applied_callback then
        -- Provided when hide_on_apply, and ConfigDialog temporarily hidden:
        -- show an InfoMessage with the values, and call when_applied_callback on dismiss
        UIManager:show(InfoMessage:new{
            text = T(_([[Zoom set to:

    mode: %1
    number of columns: %2
    number of rows: %4
    horizontal overlap: %3 %
    vertical overlap: %5 %
    zoom factor: %6]]),
                self.zoom_mode_label[zoom_mode],
                ("%.2f"):format(self:getNumberOf("columns", settings.zoom_overlap_h)),
                settings.zoom_overlap_h,
                ("%.2f"):format(self:getNumberOf("rows", settings.zoom_overlap_v)),
                settings.zoom_overlap_v,
                ("%.2f"):format(config.zoom_factor)),
            dismiss_callback = when_applied_callback,
        })
    end
end

-- In dual page mode, zooming is a tricky concept.
-- Since we're rendering 2 pages next to each other who might not even have the same dimensions,
-- we can't use 1 zooming factor to apply a zoom to both pages.
-- Instead, we need individual factors per page.

-- Next to this, in dual page mode zooming must happen based on pageheight to algin pages,
-- e.g. in commics/manga, so zooming on anything else will misalign the pages.

-- Zooming in and out, happens per page and not for the canvas/visable area.
-- So when the user zooms in, the page is enlarged using a zooming factor, instead of the viewing area being enlarged.
-- On other words, if zooming in worked by taking a tmp screenshot and enlarge that, then this would be fine.
-- But since we're actually re-rendering the page and apply a zoom factor, we run in the same issue discribed above.
-- We can't apply 1 zoom factor to both pages in dual page mode, and calculating zoom on anything other then height
-- will result in misalignment.
--
-- @param enabled bool
-- @param _ number The base page on which dual page mode has been enalbed, we don't care about that for zooming.
function ReaderZooming:onDualPageModeEnabled(enabled, _)
    logger.dbg("ReaderZooming:onDualPageModeEnabled:", enabled)

    if enabled then
        logger.dbg("ReaderZooming:onDualPageModeEnabled: disabling zooming")
        self:onSetZoomMode("page")
        self:_updateConfigurable("page")
        self.disabled = true

        return
    end

    logger.dbg("ReaderZooming:onDualPageModeEnabled: enabling zooming")
    self.disabled = false
    self:onSetZoomMode(self.zoom_mode)
end

function ReaderZooming:onSetZoomMode(new_mode)
    if self.disabled then
        return
    end

    self.view.zoom_mode = new_mode
    if self.zoom_mode ~= new_mode then
        logger.info("setting zoom mode to", new_mode)
        self.ui:handleEvent(Event:new("ZoomModeUpdate", new_mode))
        self.zoom_mode = new_mode
        self:_updateConfigurable(new_mode)
        self:setZoom()
        if new_mode == "manual" then
            self.ui:handleEvent(Event:new("SetScrollMode", false))
        else
            self.ui:handleEvent(Event:new("InitScrollPageStates", new_mode))
        end
    end
end

function ReaderZooming:onPageUpdate(new_page_no)
    self.current_page = new_page_no
    self:setZoom()
end

function ReaderZooming:onReZoom(font_size)
    if self.document.is_reflowable then
        local reflowable_font_size = self.document:convertKoptToReflowableFontSize(font_size)
        self.document:layoutDocument(reflowable_font_size)
    end
    self:setZoom()
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
    return true
end

function ReaderZooming:onEnterFlippingMode(zoom_mode)
    if Device:isTouchDevice() then
        self.ges_events = {
            Spread = {
                GestureRange:new{
                    ges = "spread",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            },
            Pinch = {
                GestureRange:new{
                    ges = "pinch",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            },
            ToggleFreeZoom = {
                GestureRange:new{
                    ges = "double_tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            },
        }
    end

    self.orig_zoom_mode = self.zoom_mode
    if zoom_mode == "free" then
        self.ui:handleEvent(Event:new("SetZoomMode", "page"))
    else
        self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode))
    end
end

function ReaderZooming:onExitFlippingMode(zoom_mode)
    if Device:isTouchDevice() then
        self.ges_events = {}
    end
    self.orig_zoom_mode = nil
    self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode))
end

function ReaderZooming:getZoom(pageno)
    -- check if we're in bbox mode and work on bbox if that's the case
    local zoom
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    if not (self.zoom_mode and self.zoom_mode:match("^page") or self.ui.document.configurable.trim_page == 3) then
        local ubbox_dimen = self.ui.document:getUsedBBoxDimensions(pageno, 1)
        -- if bbox is larger than the native page dimension render the full page
        -- See discussion in koreader/koreader#970.
        if ubbox_dimen.w <= page_size.w and ubbox_dimen.h <= page_size.h then
            page_size = ubbox_dimen
            self.view:onBBoxUpdate(ubbox_dimen)
        else
            self.view:onBBoxUpdate(nil)
        end
    else
        -- otherwise, operate on full page
        self.view:onBBoxUpdate(nil)
    end
    -- calculate zoom value:
    local zoom_w = self.dimen.w
    local zoom_h = self.dimen.h
    if self.ui.view.footer_visible and not self.ui.view.footer.settings.reclaim_height then
        zoom_h = zoom_h - self.ui.view.footer:getHeight()
    end
    if self.rotation % 180 == 0 then
        -- No rotation or rotated by 180 degrees
        zoom_w = zoom_w / page_size.w
        zoom_h = zoom_h / page_size.h
    else
        -- rotated by 90 or 270 degrees
        zoom_w = zoom_w / page_size.h
        zoom_h = zoom_h / page_size.w
    end
    if self.zoom_mode == "content" or self.zoom_mode == "page" then
        if zoom_w < zoom_h then
            zoom = zoom_w
        else
            zoom = zoom_h
        end
    elseif self.zoom_mode == "contentwidth" or self.zoom_mode == "pagewidth" then
        zoom = zoom_w
    elseif self.zoom_mode == "contentheight" or self.zoom_mode == "pageheight" then
        zoom = zoom_h
    elseif self.zoom_mode == "free" then
        zoom = self.zoom
    else
        local zoom_factor = self.ui.doc_settings:readSetting("kopt_zoom_factor")
                         or G_reader_settings:readSetting("kopt_zoom_factor")
                         or self.kopt_zoom_factor
        zoom = zoom_w * zoom_factor
    end
    if zoom and zoom > 10 and not DocCache:willAccept(zoom * (self.dimen.w * self.dimen.h + 512)) then
        logger.dbg("zoom too large, adjusting")
        while not DocCache:willAccept(zoom * (self.dimen.w * self.dimen.h + 512)) do
            if zoom > 100 then
                zoom = zoom - 50
            elseif zoom > 10 then
                zoom = zoom - 5
            elseif zoom > 1 then
                zoom = zoom - 0.5
            elseif zoom > 0.1 then
                zoom = zoom - 0.05
            else
                zoom = zoom - 0.005
            end
            logger.dbg("new zoom: "..zoom)

            if zoom < 0 then return 0 end
        end
    end
    return zoom, zoom_w, zoom_h
end

function ReaderZooming:getRegionalZoomCenter(pageno, pos)
    local p_pos = self.view:getSinglePagePosition(pos)
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    local pos_x = p_pos.x / page_size.w
    local pos_y = p_pos.y / page_size.h
    local block = self.ui.document:getPageBlock(pageno, pos_x, pos_y)
    local margin = self.ui.document.configurable.page_margin * Screen:getDPI()
    if block then
        local zoom = self.dimen.w / page_size.w / (block.x1 - block.x0)
        zoom = zoom/(1 + 3*margin/zoom/page_size.w)
        local xpos = (block.x0 + block.x1)/2 * zoom * page_size.w
        local ypos = p_pos.y / p_pos.zoom * zoom
        return zoom, xpos, ypos
    end
    local zoom = 2*self.dimen.w / page_size.w
    return zoom/(1 + 3*margin/zoom/page_size.w)
end

function ReaderZooming:setZoom()
    if not self.dimen then
        self.dimen = self.ui.dimen
    end
    self.zoom = self:getZoom(self.current_page)
    self.ui:handleEvent(Event:new("ZoomUpdate", self.zoom))
end

function ReaderZooming:genSetZoomModeCallBack(mode)
    return function()
        self:setZoomMode(mode)
    end
end

function ReaderZooming:setZoomMode(mode, no_warning, is_reflowed)
    if self.disabled then
        return
    end

    if not no_warning and self.ui.view.page_scroll then
        local message
        if self.paged_modes[mode] then
            message = T(_([[
%1

In combination with continuous view (scroll mode), this can cause unexpected vertical shifts when turning pages.]]),
                        self.paged_modes[mode])
        elseif self.zoom_mode == "manual" then
            message = _([[
Manual zoom works best with page view.

Please enable page view instead of continuous view (scroll mode).]])
        end
        if message then
            UIManager:show(InfoMessage:new{text = message, timeout = 5})
        end
    end

    -- Dirty hack to prevent ReaderKoptListener from stomping on normal_zoom_mode...
    self.ui:handleEvent(Event:new("SetZoomMode", mode, is_reflowed and "koptlistener"))
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

local function _getOverlapFactorForNum(n, overlap)
    -- Auxiliary function to "distribute" an overlap between tiles
    overlap = overlap * (n - 1) / n
    return (100 / (100 - overlap))
end

function ReaderZooming:getNumberOf(what, overlap)
    -- Number of columns (if what ~= "rows") or rows (if what == "rows")
    local zoom, zoom_w, zoom_h = self:getZoom(self.current_page)
    local zoom_factor = zoom / (what == "rows" and zoom_h or zoom_w)
    if overlap then
        overlap = (what == "rows" and self.zoom_overlap_v or self.zoom_overlap_h)
        zoom_factor = (overlap - 100 * zoom_factor) / (overlap - 100)  -- Thanks Xcas for this one...
    end
    return zoom_factor
end

function ReaderZooming:setNumberOf(what, num, overlap)
    -- Sets number of columns (if what ~= "rows") or rows (if what == "rows")
    local _, zoom_w, zoom_h = self:getZoom(self.current_page)
    local overlap_factor = overlap and _getOverlapFactorForNum(num, overlap) or 1
    local zoom_factor = num / overlap_factor
    if what == "rows" then
        zoom_factor = zoom_factor * zoom_h / zoom_w
    end
    self.ui:handleEvent(Event:new("SetZoomPan", {kopt_zoom_factor = zoom_factor}))
    return zoom_factor
end

function ReaderZooming:_zoomFactorChange(title_text, direction, precision)
    local zoom_factor, overlap = self:getNumberOf(direction)
    UIManager:show(SpinWidget:new{
        value = zoom_factor,
        value_min = 0.1,
        value_max = 10,
        value_step = 0.1,
        value_hold_step = 1,
        precision = "%.1f",
        ok_text = title_text,
        title_text = title_text,
        callback = function(spin)
            zoom_factor = spin.value
            self:setNumberOf(direction, zoom_factor, overlap)
        end
    })
end

function ReaderZooming:_zoomPanChange(text, setting)
    UIManager:show(SpinWidget:new{
        value = self[setting],
        value_min = 0,
        value_max = 90,
        value_step = 1,
        value_hold_step = 10,
        ok_text = _("Set"),
        title_text = text,
        callback = function(spin)
            self.ui:handleEvent(Event:new("SetZoomPan", {[setting] = spin.value}))
        end
    })
end

function ReaderZooming:onZoomFactorChange()
    if self.disabled then
        return
    end

    self:_zoomFactorChange(_("Set Zoom factor"), false, "%.1f")
end

function ReaderZooming:onSetZoomPan(settings, no_redraw)
    if self.disabled then
        return
    end

    self.ui.doc_settings:saveSetting("kopt_zoom_factor", settings.kopt_zoom_factor)
    self.ui.doc_settings:saveSetting("zoom_mode", settings.zoom_mode)
    for k, v in pairs(settings) do
        self[k] = v
        -- Configurable keys aren't prefixed...
        local configurable_key = k:gsub("^kopt_", "")
        if self.ui.document.configurable[configurable_key] then
            self.ui.document.configurable[configurable_key] = v
        end
    end
    if not no_redraw then
        self.ui:handleEvent(Event:new("RedrawCurrentPage"))
    end
end

function ReaderZooming:onBBoxUpdate()
    self:onDefineZoom()
end

function ReaderZooming:getZoomModeActions() -- for Dispatcher
    local action_toggles = {}
    for _, v in ipairs(ReaderZooming.available_zoom_modes) do
        table.insert(action_toggles, ReaderZooming.zoom_mode_label[v])
    end
    return ReaderZooming.available_zoom_modes, action_toggles
end

return ReaderZooming
