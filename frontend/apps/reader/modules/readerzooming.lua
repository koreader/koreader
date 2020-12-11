local Cache = require("cache")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderZooming = InputContainer:new{
    zoom = 1.0,
    available_zoom_modes = {
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
    -- default to nil so we can trigger ZoomModeUpdate events on start up
    zoom_mode = nil,
    DEFAULT_ZOOM_MODE = "pagewidth",
    -- for pan mode: fit to width/zoom_factor,
    -- with overlap of zoom_overlap_h % (horizontally)
    -- and zoom_overlap_v % (vertically).
    zoom_factor = 2,
    zoom_pan_settings = {
        "zoom_factor",
        "zoom_overlap_h",
        "zoom_overlap_v",
        "zoom_bottom_to_top",
        "zoom_direction_vertical",
    },
    zoom_overlap_h = 40,
    zoom_overlap_v = 40,
    zoom_bottom_to_top = nil,  -- true for bottom-to-top
    zoom_direction_vertical = nil, -- true for column mode
    current_page = 1,
    rotation = 0,
    paged_modes = {
        page = _("Zoom to fit page works best with page view."),
        pageheight = _("Zoom to fit page height works best with page view."),
        contentheight = _("Zoom to fit content height works best with page view."),
        content = _("Zoom to fit content works best with page view."),
        columns = _("Zoom to fit columns works best with page view."),
    },
}

function ReaderZooming:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ZoomIn = {
                { "Shift", Input.group.PgFwd },
                doc = "zoom in",
                event = "Zoom", args = "in"
            },
            ZoomOut = {
                { "Shift", Input.group.PgBack },
                doc = "zoom out",
                event = "Zoom", args = "out"
            },
            ZoomToFitPage = {
                { "A" },
                doc = "zoom to fit page",
                event = "SetZoomMode", args = "page"
            },
            ZoomToFitContent = {
                { "Shift", "A" },
                doc = "zoom to fit content",
                event = "SetZoomMode", args = "content"
            },
            ZoomToFitPageWidth = {
                { "S" },
                doc = "zoom to fit page width",
                event = "SetZoomMode", args = "pagewidth"
            },
            ZoomToFitContentWidth = {
                { "Shift", "S" },
                doc = "zoom to fit content width",
                event = "SetZoomMode", args = "contentwidth"
            },
            ZoomToFitPageHeight = {
                { "D" },
                doc = "zoom to fit page height",
                event = "SetZoomMode", args = "pageheight"
            },
            ZoomToFitContentHeight = {
                { "Shift", "D" },
                doc = "zoom to fit content height",
                event = "SetZoomMode", args = "contentheight"
            },
            ZoomManual = {
                { "Shift", "M" },
                doc = "manual zoom mode",
                event = "SetZoomMode", args = "manual"
            },
        }
    end
end

function ReaderZooming:onReadSettings(config)
    local zoom_mode = config:readSetting("zoom_mode")
                    or G_reader_settings:readSetting("zoom_mode")
                    or self.DEFAULT_ZOOM_MODE
    zoom_mode = util.arrayContains(self.available_zoom_modes, zoom_mode)
                                and zoom_mode
                                or self.DEFAULT_ZOOM_MODE
    self:setZoomMode(zoom_mode, true) -- avoid informative message on load
    for _, setting in ipairs(self.zoom_pan_settings) do
        self[setting] = config:readSetting(setting) or
                    G_reader_settings:readSetting(setting) or
                    self[setting]
    end
end

function ReaderZooming:onSaveSettings()
    self.ui.doc_settings:saveSetting("zoom_mode", self.orig_zoom_mode or self.zoom_mode)
    for _, setting in ipairs(self.zoom_pan_settings) do
        self.ui.doc_settings:saveSetting(setting, self[setting])
    end
end

function ReaderZooming:onSpread(arg, ges)
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

function ReaderZooming:onRotationUpdate(rotation)
    self.rotation = rotation
    self:setZoom()
end

function ReaderZooming:onZoom(direction)
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

function ReaderZooming:onDefineZoom(btn)
    local config = self.ui.document.configurable
    local settings = ({
        [7] = {right_to_left = false, zoom_bottom_to_top = false, zoom_direction_vertical = false},
        [6] = {right_to_left = false, zoom_bottom_to_top = false, zoom_direction_vertical = true },
        [5] = {right_to_left = false, zoom_bottom_to_top = true,  zoom_direction_vertical = false},
        [4] = {right_to_left = false, zoom_bottom_to_top = true,  zoom_direction_vertical = true },
        [3] = {right_to_left = true,  zoom_bottom_to_top = true,  zoom_direction_vertical = true },
        [2] = {right_to_left = true,  zoom_bottom_to_top = true,  zoom_direction_vertical = false},
        [1] = {right_to_left = true,  zoom_bottom_to_top = false, zoom_direction_vertical = true },
        [0] = {right_to_left = true,  zoom_bottom_to_top = false, zoom_direction_vertical = false},
    })[config.zoom_direction]
    local zoom_range_number = config.zoom_range_number
    local zoom_factor = config.zoom_factor
    local zoom_mode_genus = ({
        [4] = "page",
        [3] = "content",
        [2] = "columns",
        [1] = "rows",
        [0] = "manual",
    })[config.zoom_mode_genus]
    local zoom_mode_type = ({
        [2] = "",
        [1] = "width",
        [0] = "height",
    })[config.zoom_mode_type]
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
        zoom_mode = zoom_mode_genus..zoom_mode_type
    else
        zoom_mode = zoom_mode_genus
        self.ui:handleEvent(Event:new("SetScrollMode", false))
    end
    zoom_mode = util.arrayContains(self.available_zoom_modes, zoom_mode) and zoom_mode or self.DEFAULT_ZOOM_MODE
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
            settings.zoom_factor = self:setNumberOf(
                zoom_mode,
                zoom_range_number,
                zoom_mode == "columns" and settings.zoom_overlap_h or settings.zoom_overlap_v
            )
        end
    elseif zoom_mode == "manual" then
        if btn == "manual" then
            config.zoom_factor = self:getNumberOf("columns")
        else
            self:setNumberOf("columns", zoom_factor)
        end
        self.ui:handleEvent(Event:new("SetZoomPan", settings, true))
    end
    self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode))
    if btn == "columns" or btn == "rows" then
        config.zoom_range_number = self:getNumberOf(
            zoom_mode,
            btn == "columns" and settings.zoom_overlap_h or settings.zoom_overlap_v
        )
    end
    if tonumber(btn) then
        UIManager:show(InfoMessage:new{
            timeout = 2,
            text = T(_([[Zoom set to:

    mode: %1
    number of columns: %2
    number of rows: %4
    horizontal overlap: %3 %
    vertical overlap: %5 %
    zoom factor: %6]]),
                zoom_mode,
                ("%.2f"):format(self:getNumberOf("columns", settings.zoom_overlap_h)),
                settings.zoom_overlap_h,
                ("%.2f"):format(self:getNumberOf("rows", settings.zoom_overlap_v)),
                settings.zoom_overlap_v,
                ("%.2f"):format(self:getNumberOf("columns"))),
        })
    end
end

function ReaderZooming:onSetZoomMode(new_mode)
    self.view.zoom_mode = new_mode
    if self.zoom_mode ~= new_mode then
        logger.info("setting zoom mode to", new_mode)
        self.ui:handleEvent(Event:new("ZoomModeUpdate", new_mode))
        self.zoom_mode = new_mode
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
        local zoom_factor = self.ui.doc_settings:readSetting("zoom_factor")
                            or G_reader_settings:readSetting("zoom_factor")
                            or self.zoom_factor
        zoom = zoom_w * zoom_factor
    end
    if zoom and zoom > 10 and not Cache:willAccept(zoom * (self.dimen.w * self.dimen.h + 64)) then
        logger.dbg("zoom too large, adjusting")
        while not Cache:willAccept(zoom * (self.dimen.w * self.dimen.h + 64)) do
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

function ReaderZooming:setZoomMode(mode, no_warning)
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

    self.ui:handleEvent(Event:new("SetZoomMode", mode))
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
    self.ui:handleEvent(Event:new("SetZoomPan", {zoom_factor = zoom_factor}))
    self.ui:handleEvent(Event:new("RedrawCurrentPage"))
end

function ReaderZooming:_zoomFactorChange(title_text, direction, precision)
    local zoom_factor, overlap = self:getNumberOf(direction)
    UIManager:show(SpinWidget:new{
        width = math.floor(Screen:getWidth() * 0.6),
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
        width = math.floor(Screen:getWidth() * 0.6),
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
    self:_zoomFactorChange(_("Set Zoom factor"), false, "%.1f")
end

function ReaderZooming:onSetZoomPan(settings, no_redraw)
    for k, v in pairs(settings) do
        self[k] = v
        self.ui.doc_settings:saveSetting(k, v)
    end
    if not no_redraw then
        self.ui:handleEvent(Event:new("RedrawCurrentPage"))
    end
end

function ReaderZooming:onBBoxUpdate()
    self:onDefineZoom()
end

function ReaderZooming:makeDefault(zoom_mode, touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default zoom mode to %1?"),
            zoom_mode
        ),
        ok_callback = function()
            G_reader_settings:saveSetting("zoom_mode", zoom_mode)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

return ReaderZooming
