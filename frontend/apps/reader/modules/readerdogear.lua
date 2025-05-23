local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local logger = require("logger")

local ReaderDogear = WidgetContainer:extend{
    -- These constants are used to instruct ReaderDogear on which corner to paint the dogear
    -- This is mainly used in Dual Page mode
    -- Default is right top corner
    SIDE_LEFT = 1,
    SIDE_RIGHT = 2,
    SIDE_BOTH = 3,
}

function ReaderDogear:init()
    -- This image could be scaled for DPI (with scale_for_dpi=true, scale_factor=0.7),
    -- but it's as good to scale it to a fraction (1/32) of the screen size.
    -- For CreDocument, we should additionally take care of not exceeding margins
    -- to not overwrite the book text.
    -- For other documents, there is no easy way to know if valuable content
    -- may be hidden by the icon (kopt's page_margin is quite obscure).
    self.dogear_min_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1 / 40))
    self.dogear_max_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1 / 32))
    self.dogear_size = nil

    self.icon_right = nil
    self.icon_left = nil
    self.vgroup_right = nil
    self.vgroup_left = nil
    self.top_pad = nil

    self.right_ear = nil
    self.left_ear = nil

    self.dogear_y_offset = 0
    self.dimen = nil
    self.sides = self.SIDE_RIGHT
    self:setupDogear()
    self:resetLayout()
end

function ReaderDogear:setupDogear(new_dogear_size)
    if not new_dogear_size then
        new_dogear_size = self.dogear_max_size
    end
    if new_dogear_size ~= self.dogear_size then
        self.dogear_size = new_dogear_size
        if self.right_ear then
            self.right_ear:free()
        end
        if self.left_ear then
            self.left_ear:free()
        end
        self.top_pad = VerticalSpan:new{ width = self.dogear_y_offset }
        self.icon_right = IconWidget:new{
            icon = "dogear.alpha",
            rotation_angle = BD.mirroredUILayout() and 90 or 0,
            width = self.dogear_size,
            height = self.dogear_size,
            alpha = true, -- Keep the alpha layer intact
        }
        self.vgroup_right = VerticalGroup:new{
            self.top_pad,
            self.icon_right,
        }
        self.right_ear = RightContainer:new{
            dimen = Geom:new({ w = Screen:getWidth(), h = self.dogear_y_offset + self.dogear_size }),
            self.vgroup_right,
        }
        self.icon_left = IconWidget:new{
            icon = "dogear.alpha",
            rotation_angle = self.icon_right.rotation_angle + 90,
            width = self.dogear_size,
            height = self.dogear_size,
            alpha = true, -- Keep the alpha layer intact
        }
        self.vgroup_left = VerticalGroup:new{
            self.top_pad,
            self.icon_left,
        }
        self.left_ear = LeftContainer:new{
            dimen = Geom:new({ w = Screen:getWidth(), h = self.dogear_y_offset + self.dogear_size }),
            self.vgroup_left,
        }
    end
end

function ReaderDogear:paintTo(bb, x, y)
    logger.dbg("ReaderDogear:paintTo with sides", self.sides)

    if self.sides == self.SIDE_RIGHT or self.sides == self.SIDE_BOTH then
        self.right_ear:paintTo(bb, x, y)
    end

    -- Exit early if we don't need to paint left side.
    if self.sides ~= self.SIDE_LEFT and self.sides ~= self.SIDE_BOTH then
        return
    end

    self.left_ear:paintTo(bb, x, y)
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

    if self.right_ear or self.left_ear then
        self.top_pad.width = self.dogear_y_offset
    end

    if self.right_ear then
        self.right_ear.dimen.h = self.dogear_y_offset + self.dogear_size
        self.vgroup_right:resetLayout()
    end

    if self.left_ear then
        self.left_ear.dimen.h = self.dogear_y_offset + self.dogear_size
        self.vgroup_left:resetLayout()
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
    self.right_ear.dimen.w = Screen:getWidth()
    self.left_ear.dimen.w = Screen:getWidth()
end

function ReaderDogear:getRefreshRegion()
    -- We can't use self.dimen because of the width/height quirks of Left/RightContainer, so use the IconWidget's...
    return self.icon_right.dimen:combine(self.icon_left.dimen)
end

-- @param visible boolean
-- @param side number 1 only left, 2 only right, if 3 both sides, nil == 2
function ReaderDogear:onSetDogearVisibility(visible, sides)
    logger.dbg("ReaderDogear:onSetDogearVisibility", visible, sides)
    self.sides = sides or self.SIDE_RIGHT
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
