local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local ReaderDogear = WidgetContainer:extend{}

function ReaderDogear:init()
    -- This image could be scaled for DPI (with scale_for_dpi=true, scale_factor=0.7),
    -- but it's as good to scale it to a fraction (1/32) of the screen size.
    -- For CreDocument, we should additionally take care of not exceeding margins
    -- to not overwrite the book text.
    -- For other documents, there is no easy way to know if valuable content
    -- may be hidden by the icon (kopt's page_margin is quite obscure).
    self.dogear_min_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1/40))
    self.dogear_max_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1/32))
    self.dogear_size = nil
    self.icon = nil
    self.dogear_y_offset = 0
    self.top_pad = nil
    self:setupDogear()
    self:resetLayout()
end

function ReaderDogear:setupDogear(new_dogear_size)
    if not new_dogear_size then
        new_dogear_size = self.dogear_max_size
    end
    if new_dogear_size ~= self.dogear_size then
        self.dogear_size = new_dogear_size
        if self[1] then
            self[1]:free()
        end
        self.icon = IconWidget:new{
            icon = "dogear.alpha",
            rotation_angle = BD.mirroredUILayout() and 90 or 0,
            width = self.dogear_size,
            height = self.dogear_size,
            alpha = true, -- Keep the alpha layer intact
        }
        self.top_pad = VerticalSpan:new{width = self.dogear_y_offset}
        self.vgroup = VerticalGroup:new{
            self.top_pad,
            self.icon,
        }
        self[1] = RightContainer:new{
            dimen = Geom:new{w = Screen:getWidth(), h = self.dogear_y_offset + self.dogear_size},
            self.vgroup
        }
    end
end

function ReaderDogear:onReadSettings(config)
    if self.ui.rolling then
        -- Adjust to CreDocument margins (as done in ReaderTypeset)
        local configurable = self.ui.document.configurable
        local margins = { configurable.h_page_margins[1], configurable.t_page_margin,
                          configurable.h_page_margins[2], configurable.b_page_margin }
        self:onSetPageMargins(margins)
    end
end

function ReaderDogear:onSetPageMargins(margins)
    if not self.ui.rolling then
        -- we may get called by readerfooter (when hiding the footer)
        -- on pdf documents and get margins=nil
        return
    end
    local margin_top, margin_right = margins[2], margins[3]
    -- As the icon is squared, we can take the max() instead of the min() of
    -- top & right margins and be sure no text is hidden by the icon
    -- (the provided margins are not scaled, so do as ReaderTypeset)
    local margin = Screen:scaleBySize(math.max(margin_top, margin_right))
    local new_dogear_size = math.min(self.dogear_max_size, math.max(self.dogear_min_size, margin))
    self:setupDogear(new_dogear_size)
end

function ReaderDogear:updateDogearOffset()
    if not self.ui.rolling then
        return
    end
    self.dogear_y_offset = 0
    if self.view.view_mode == "page" then
        self.dogear_y_offset = self.ui.document:getHeaderHeight()
    end
    -- Update components heights and positionnings
    if self[1] then
        self[1].dimen.h = self.dogear_y_offset + self.dogear_size
        self.top_pad.width = self.dogear_y_offset
        self.vgroup:resetLayout()
    end
end

function ReaderDogear:onReaderReady()
    self:updateDogearOffset()
end

function ReaderDogear:onDocumentRerendered()
    -- Catching the top status bar toggling with :onSetStatusLine()
    -- would be too early. But "DocumentRerendered" is sent after
    -- it has been applied
    self:updateDogearOffset()
end

function ReaderDogear:onChangeViewMode()
    -- No top status bar when switching between page and scroll mode
    self:updateDogearOffset()
end

function ReaderDogear:resetLayout()
    -- NOTE: RightContainer aligns to the right of its *own* width...
    self[1].dimen.w = Screen:getWidth()
end

function ReaderDogear:getRefreshRegion()
    -- We can't use self.dimen because of the width/height quirks of Left/RightContainer, so use the IconWidget's...
    return self.icon.dimen
end

function ReaderDogear:onSetDogearVisibility(visible)
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
