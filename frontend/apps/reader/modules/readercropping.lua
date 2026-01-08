local BBoxWidget = require("ui/widget/bboxwidget")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ConfirmBox = require("ui/widget/confirmbox")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")

local ReaderCropping = WidgetContainer:extend{}

function ReaderCropping:onPageCrop(mode)
    self.ui:handleEvent(Event:new("CloseConfigMenu"))

    -- backup original zoom mode as cropping use "page" zoom mode
    self.orig_zoom_mode = self.view.zoom_mode
    if mode == "auto" then
        if self.document.configurable.text_wrap ~= 1 then
            self:setCropZoomMode(true)
        end
        return
    elseif mode == "none" then
        return
    end
    -- backup original view dimen
    self.orig_view_dimen = Geom:new{w = self.view.dimen.w, h = self.view.dimen.h}
    -- backup original view bgcolor
    self.orig_view_bgcolor = self.view.outer_page_color
    self.view.outer_page_color = Blitbuffer.COLOR_DARK_GRAY
    -- backup original footer visibility
    self.orig_view_footer_visibility = self.view.footer_visible
    self.view.footer_visible = false
    -- backup original page scroll
    self.orig_page_scroll = self.view.page_scroll
    self.view.page_scroll = false
    -- backup and disable original hinting state
    self.ui:handleEvent(Event:new("DisableHinting"))
    -- backup original reflow mode as cropping use non-reflow mode
    self.orig_reflow_mode = self.document.configurable.text_wrap
    if self.orig_reflow_mode == 1 then
        self.document.configurable.text_wrap = 0
        -- if we are in reflow mode, then we are already in page
        -- mode, just force readerview to recalculate visible_area
        self.view:recalculate()
    else
        self.ui:handleEvent(Event:new("SetZoomMode", "page"))
    end

    -- prepare bottom buttons so we know the size available for the page above it
    local button_table = ButtonTable:new{
        width = Screen:getWidth(),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() self:onCancelPageCrop() end,
            },
            {
                text = _("Settings"),
                callback = function() self:onShowCropSettings() end,
            },
            {
                text = _("Apply crop"),
                callback = function() self:onConfirmPageCrop() end,
            },
        }},
        zero_sep = true,
        show_parent = self,
    }
    local button_container = FrameContainer:new{
        margin = 0,
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = button_table:getSize().h,
            },
            button_table,
        }
    }
    -- height available for page
    local page_container_h = Screen:getHeight()
    if Device:isTouchDevice() then
        -- non-touch devices do not need cancel and apply buttons
        page_container_h = page_container_h - button_table:getSize().h
    end
    local page_dimen = Geom:new{
        w = Screen:getWidth(),
        h = page_container_h,
    }
    -- resize document view to the available size
    self.ui:handleEvent(Event:new("SetDimensions", page_dimen))

    -- finalize crop dialog
    self.bbox_widget = BBoxWidget:new{
        ui = self.ui,
        view = self.view,
        document = self.document,
        -- allow the widget to callback into this module (keyboard handler will use it)
        parent_module = self,
    }
    self.crop_dialog = VerticalGroup:new{
        align = "left",
        self.bbox_widget,
        (Device:isTouchDevice() and button_container) or nil, -- button bar only available for touch devices
    }
    UIManager:show(self.crop_dialog)
    return true
end

function ReaderCropping:onShowCropSettings()
    -- Prepare current values
    local pageno = self.view.state.page
    local parity = Math.oddEven(pageno)
    -- Use explicit nil checks so saved false values are respected.
    local this_checked = self._apply_tick_this
    if this_checked == nil then this_checked = true end
    local odd_checked = self._apply_tick_odd
    if odd_checked == nil then odd_checked = (parity == "odd") end
    local even_checked = self._apply_tick_even
    if even_checked == nil then even_checked = (parity == "even") end
    local smart_checked = self.smart_crop_enabled or false
    local grid_checked = self.show_grid_enabled or false

    -- Determine if smart crop should be enabled based on zoom mode
    -- Enable for "content", "columns", and "rows" zoom modes
    local zoom_mode = self.orig_zoom_mode or self.view.zoom_mode
    local smart_enabled = zoom_mode and (zoom_mode == "content" or zoom_mode == "columns" or zoom_mode == "rows")

    local cb_this, cb_odd, cb_even, cb_smart, cb_grid
    local confirm = ConfirmBox:new{
        text = _("Crop settings"),
        ok_text = _("Save"),
        ok_callback = function()
            -- read states and store on ReaderCropping instance
            self._apply_tick_this = cb_this.checked
            self._apply_tick_odd = cb_odd.checked
            self._apply_tick_even = cb_even.checked
            self.smart_crop_enabled = cb_smart.checked
            self.show_grid_enabled = cb_grid.checked
            -- If smart crop was enabled, force a recalculation of the crop box
            if self.smart_crop_enabled and self.bbox_widget and type(self.bbox_widget.applySmartCropFull) == "function" then
                self.bbox_widget:applySmartCropFull()
            end
            -- return to crop dialog (ConfirmBox will close itself)
        end,
        flush_events_on_show = true,
    }

    cb_this = CheckButton:new{ text = _("This page"), checked = this_checked, parent = confirm }
    confirm:addWidget(cb_this)
    cb_odd = CheckButton:new{ text = _("Odd pages"), checked = odd_checked, parent = confirm }
    confirm:addWidget(cb_odd)
    cb_even = CheckButton:new{ text = _("Even pages"), checked = even_checked, parent = confirm }
    confirm:addWidget(cb_even)
    cb_smart = CheckButton:new{ 
        text = _("Lock aspect ratio"), 
        checked = smart_checked, 
        enabled = smart_enabled,
        parent = confirm 
    }
    confirm:addWidget(cb_smart)
    cb_grid = CheckButton:new{ text = _("Show grid lines"), checked = grid_checked, parent = confirm }
    confirm:addWidget(cb_grid)

    UIManager:show(confirm)
    return true
end

function ReaderCropping:onConfirmPageCrop()
    --DEBUG("new bbox", new_bbox)
    UIManager:close(self.crop_dialog)
    local new_bbox = self.bbox_widget:getModifiedPageBBox()
    self.ui:handleEvent(Event:new("BBoxUpdate", new_bbox))
    local pageno = self.view.state.page
    -- Apply according to saved scope settings.
    local parity = Math.oddEven(pageno)
    -- If no explicit options are set, default to applying to this page only.
    local apply_this = (self._apply_tick_this == nil) and true or self._apply_tick_this
    local apply_odd = (self._apply_tick_odd == nil) and (parity == "odd") or self._apply_tick_odd
    local apply_even = (self._apply_tick_even == nil) and (parity == "even") or self._apply_tick_even

    if apply_this then
        self.document.bbox[pageno] = new_bbox
    end
    if apply_odd then
        self.document.bbox["odd"] = new_bbox
    end
    if apply_even then
        self.document.bbox["even"] = new_bbox
    end
    self:exitPageCrop(true)
    return true
end

function ReaderCropping:onCancelPageCrop()
    UIManager:close(self.crop_dialog)
    self:exitPageCrop(false)
    return true
end

function ReaderCropping:exitPageCrop(confirmed)
    -- restore hinting state
    self.ui:handleEvent(Event:new("RestoreHinting"))
    -- restore page scroll
    self.view.page_scroll = self.orig_page_scroll
    -- restore footer visibility
    self.view.footer_visible = self.orig_view_footer_visibility
    -- restore view bgcolor
    self.view.outer_page_color = self.orig_view_bgcolor
    -- restore reflow mode
    self.document.configurable.text_wrap = self.orig_reflow_mode
    -- restore view dimens
    self.ui:handleEvent(Event:new("RestoreDimensions", self.orig_view_dimen))
    self.view:recalculate()
    -- Exiting should have the same look and feel with entering.
    if self.orig_reflow_mode == 1 then
        self.ui:handleEvent(Event:new("RestoreZoomMode"))
    else
        self:setCropZoomMode(confirmed)
    end
end

function ReaderCropping:setCropZoomMode(confirmed)
    if confirmed then
        -- if original zoom mode is "page???", set zoom mode to "content???"
        local zoom_mode_type = self.orig_zoom_mode:match("page(.*)")
        self:setZoomMode(zoom_mode_type
                    and "content"..zoom_mode_type
                    or self.orig_zoom_mode)
        self.ui:handleEvent(Event:new("InitScrollPageStates"))
    else
        self:setZoomMode(self.orig_zoom_mode)
    end
end

function ReaderCropping:setZoomMode(mode)
    self.ui:handleEvent(Event:new("SetZoomMode", mode))
end

function ReaderCropping:onReadSettings(config)
    if config:has("bbox") then
        self.document.bbox = config:readSetting("bbox")
    end
end

function ReaderCropping:onSaveSettings()
    self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end

return ReaderCropping
