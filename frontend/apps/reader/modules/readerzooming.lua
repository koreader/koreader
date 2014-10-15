local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Input = require("ui/input")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderZooming = InputContainer:new{
    zoom = 1.0,
    -- default to nil so we can trigger ZoomModeUpdate events on start up
    zoom_mode = nil,
    DEFAULT_ZOOM_MODE = "page",
    current_page = 1,
    rotation = 0
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
        }
    end
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
    self.ui.menu:registerToMainMenu(self)
end

function ReaderZooming:onReadSettings(config)
    -- @TODO config file from old code base uses globalzoom_mode
    -- instead of zoom_mode, we need to handle this imcompatibility
    -- 04.12 2012 (houqp)
    local zoom_mode = config:readSetting("zoom_mode") or
                    G_reader_settings:readSetting("zoom_mode") or
                    self.DEFAULT_ZOOM_MODE
    self:setZoomMode(zoom_mode)
end

function ReaderZooming:onSaveSettings()
    self.ui.doc_settings:saveSetting("zoom_mode", self.zoom_mode)
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
        self.orig_zoom_mode = self.zoom_mode
        local xpos, ypos
        self.zoom, xpos, ypos = self:getRegionalZoomCenter(self.current_page, ges.pos)
        DEBUG("zoom center", self.zoom, xpos, ypos)
        self.ui:handleEvent(Event:new("SetZoomMode", "free"))
        if xpos == nil or ypos == nil then
            xpos = ges.pos.x * self.zoom / self.orig_zoom
            ypos = ges.pos.y * self.zoom / self.orig_zoom
        end
        self.view:SetZoomCenter(xpos, ypos)
    else
        self.ui:handleEvent(Event:new("SetZoomMode", self.orig_zoom_mode or "page"))
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
    DEBUG("zoom", direction)
    if direction == "in" then
        self.zoom = self.zoom * 1.333333
    elseif direction == "out" then
        self.zoom = self.zoom * 0.75
    end
    DEBUG("zoom is now at", self.zoom)
    self:onSetZoomMode("free")
    self.view:onZoomUpdate(self.zoom)
    return true
end

function ReaderZooming:onSetZoomMode(new_mode)
    self.view.zoom_mode = new_mode
    if self.zoom_mode ~= new_mode then
        DEBUG("setting zoom mode to", new_mode)
        self.ui:handleEvent(Event:new("ZoomModeUpdate", new_mode))
        self.zoom_mode = new_mode
        self:setZoom()
    end
end

function ReaderZooming:onPageUpdate(new_page_no)
    self.current_page = new_page_no
    self:setZoom()
end

function ReaderZooming:onReZoom()
    self:setZoom()
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
    return true
end

function ReaderZooming:getZoom(pageno)
    -- check if we're in bbox mode and work on bbox if that's the case
    local zoom = nil
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    if self.zoom_mode == "content"
    or self.zoom_mode == "contentwidth"
    or self.zoom_mode == "contentheight" then
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
    local zoom_w = self.dimen.w / page_size.w
    local zoom_h = self.dimen.h / page_size.h
    if self.rotation % 180 ~= 0 then
        -- rotated by 90 or 270 degrees
        zoom_w = self.dimen.w / page_size.h
        zoom_h = self.dimen.h / page_size.w
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
    end
    return zoom
end

function ReaderZooming:getRegionalZoomCenter(pageno, pos)
    local p_pos = self.view:getSinglePagePosition(pos)
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    local pos_x = p_pos.x / page_size.w / p_pos.zoom
    local pos_y = p_pos.y / page_size.h / p_pos.zoom
    local regions = self.ui.document:getPageRegions(pageno)
    DEBUG("get page regions", regions)
    local margin = self.ui.document.configurable.page_margin * Screen:getDPI()
    for i = 1, #regions do
        if regions[i].x0 <= pos_x and pos_x <= regions[i].x1
            and regions[i].y0 <= pos_y and pos_y <= regions[i].y1 then
            local zoom = 1/(regions[i].x1 - regions[i].x0)
            zoom = zoom/(1 + 3*margin/zoom/page_size.w)
            local xpos = (regions[i].x0 + regions[i].x1)/2 * zoom * page_size.w
            local ypos = p_pos.y / p_pos.zoom * zoom
            return zoom, xpos, ypos
        end
    end
    return 2
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

function ReaderZooming:setZoomMode(mode)
    self.ui:handleEvent(Event:new("SetZoomMode", mode))
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

function ReaderZooming:addToMainMenu(tab_item_table)
    if self.ui.document.info.has_pages then
        table.insert(tab_item_table.typeset, {
            text = _("Switch zoom mode"),
            sub_item_table = {
                {
                    text = _("Zoom to fit content width"),
                    checked_func = function() return self.zoom_mode == "contentwidth" end,
                    callback = self:genSetZoomModeCallBack("contentwidth"),
                    hold_callback = function() self:makeDefault("contentwidth") end,
                },
                {
                    text = _("Zoom to fit content height"),
                    checked_func = function() return self.zoom_mode == "contentheight" end,
                    callback = self:genSetZoomModeCallBack("contentheight"),
                    hold_callback = function() self:makeDefault("contentheight") end,
                },
                {
                    text = _("Zoom to fit page width"),
                    checked_func = function() return self.zoom_mode == "pagewidth" end,
                    callback = self:genSetZoomModeCallBack("pagewidth"),
                    hold_callback = function() self:makeDefault("pagewidth") end,
                },
                {
                    text = _("Zoom to fit page height"),
                    checked_func = function() return self.zoom_mode == "pageheight" end,
                    callback = self:genSetZoomModeCallBack("pageheight"),
                    hold_callback = function() self:makeDefault("pageheight") end,
                },
                {
                    text = _("Zoom to fit content"),
                    checked_func = function() return self.zoom_mode == "content" end,
                    callback = self:genSetZoomModeCallBack("content"),
                    hold_callback = function() self:makeDefault("content") end,
                },
                {
                    text = _("Zoom to fit page"),
                    checked_func = function() return self.zoom_mode == "page" end,
                    callback = self:genSetZoomModeCallBack("page"),
                    hold_callback = function() self:makeDefault("page") end,
                },
            }
        })
    end
end

function ReaderZooming:makeDefault(zoom_mode)
    UIManager:show(ConfirmBox:new{
        text = _("Set default zoom mode to ")..zoom_mode.."?",
        ok_callback = function()
            G_reader_settings:saveSetting("zoom_mode", zoom_mode)
        end,
    })
end

return ReaderZooming
