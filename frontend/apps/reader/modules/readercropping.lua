local BBoxWidget = require("ui/widget/bboxwidget")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = require("device").screen
local _ = require("gettext")

local ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
    self.ui:handleEvent(Event:new("CloseConfigMenu"))

    -- backup original zoom mode as cropping use "page" zoom mode
    self.orig_zoom_mode = self.view.zoom_mode
    if mode == "auto" then
        --- @fixme: This is weird. "auto" crop happens to be the default, yet the default zoom mode/genus is "page", not "content".
        ---         This effectively yields different results whether auto is enabled by default, or toggled at runtime...
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
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() self:onCancelPageCrop() end,
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
    local page_container_h = Screen:getHeight() - button_table:getSize().h
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
    }
    self.crop_dialog = VerticalGroup:new{
        align = "left",
        self.bbox_widget,
        button_container,
    }

    UIManager:show(self.crop_dialog)
    return true
end

function ReaderCropping:onConfirmPageCrop()
    --DEBUG("new bbox", new_bbox)
    UIManager:close(self.crop_dialog)
    local new_bbox = self.bbox_widget:getModifiedPageBBox()
    self.ui:handleEvent(Event:new("BBoxUpdate", new_bbox))
    local pageno = self.view.state.page
    self.document.bbox[pageno] = new_bbox
    self.document.bbox[Math.oddEven(pageno)] = new_bbox
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
    self.document.bbox = config:readSetting("bbox")
end

function ReaderCropping:onSaveSettings()
    self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end

return ReaderCropping
