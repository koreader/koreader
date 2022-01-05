local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local TitleBar = OverlapGroup:extend{
    width = nil, -- default to screen width
    fullscreen = false, -- larger font and small adjustments if fullscreen
    align = "center",
    with_bottom_line = false,

    title = "",
    subtitle = nil,
    title_face = nil, -- if not provided, one of these will be used:
    title_face_fullscreen = Font:getFace("smalltfont"),
    title_face_not_fullscreen = Font:getFace("x_smalltfont"),
    subtitle_face = Font:getFace("xx_smallinfofont"),

    title_top_padding = nil, -- computed if none provided
    title_h_padding = Size.padding.large, -- horizontal padding (this replaces button_padding on the inner/title side)
    title_subtitle_v_padding = Screen:scaleBySize(3),
    bottom_v_padding = nil, -- hardcoded default values, different whether with_bottom_line true or false

    button_padding = Screen:scaleBySize(11), -- fine to keep exit/cross icon diagonally aligned with screen corners
    left_icon = nil,
    left_icon_size_ratio = 0.6,
    left_icon_tap_callback = function() end,
    left_icon_hold_callback = function() end,
    left_icon_allow_flash = true,
    right_icon = nil,
    right_icon_size_ratio = 0.6,
    right_icon_tap_callback = function() end,
    right_icon_hold_callback = function() end,
    right_icon_allow_flash = true,

    -- If provided, use right_icon="exit" and use this as right_icon_tap_callback
    close_callback = nil,
    hold_close_callback = nil,
}

function TitleBar:init()
    if self.close_callback then
        self.right_icon = "exit"
        self.right_icon_tap_callback = self.close_callback
        self.right_icon_allow_flash = false
        if self.close_hold_callback then
            self.right_icon_hold_callback = function() self.close_hold_callback() end
        end
    end

    if not self.width then
        self.width = Screen:getWidth()
    end
    local title_max_width = self.width - 2 * self.title_h_padding

    local left_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * self.left_icon_size_ratio)
    local right_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * self.right_icon_size_ratio)
    self.has_left_icon = false
    self.has_right_icon = false

    -- No button on non-touch device
    if Device:isTouchDevice() then
        if self.left_icon then
            title_max_width = title_max_width - left_icon_size - self.button_padding
            self.has_left_icon = true
        end
        if self.right_icon then
            title_max_width = title_max_width - right_icon_size - self.button_padding
            self.has_right_icon = true
        end
    end

    -- Title, subtitle, and their alignment
    if not self.title_face then
        self.title_face = self.fullscreen and self.title_face_fullscreen or self.title_face_not_fullscreen
    end
    if not self.title_top_padding then
        -- Compute it so baselines of the text and of the icons align.
        -- Our icons' baselines looks like they could be at 83% to 90% of their height.
        local face_height, face_baseline = self.title_face.ftface:getHeightAndAscender() -- luacheck: no unused
        local icon_height = math.max(left_icon_size, right_icon_size)
        local icon_baseline = icon_height * 0.85 + self.button_padding
        self.title_top_padding = Math.round(math.max(0,  icon_baseline - face_baseline))
    end
    self.title_widget = TextWidget:new{
        text = self.title,
        face = self.title_face,
        max_width = title_max_width,
        padding = 0,
    }
    self.subtitle_widget = nil
    if self.subtitle then
        self.subtitle_widget = TextWidget:new{
            text = self.subtitle,
            face = self.subtitle_face,
            max_width = title_max_width,
            padding = 0,
        }
    end
    -- To debug vertical positionning:
    -- local FrameContainer = require("ui/widget/container/framecontainer")
    -- self.title_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, self.title_widget}
    -- self.subtitle_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, self.subtitle_widget}

    self.title_group = VerticalGroup:new{
        align = self.align,
        VerticalSpan:new{width = self.title_top_padding},
        self.title_widget,
        self.subtitle_widget and VerticalSpan:new{width = self.title_subtitle_v_padding},
        self.subtitle_widget,
    }
    if self.align == "left" then
        local padding = self.title_h_padding
        if self.has_left_icon then
            padding = padding + self.button_padding + left_icon_size
        end
        self.inner_title_group = self.title_group -- we need to :resetLayout() both in :setTitle()
        self.title_group = HorizontalGroup:new{
            HorizontalSpan:new{ width = padding },
            self.title_group,
        }
    end
    self.title_group.overlap_align = self.align
    table.insert(self, self.title_group)

    -- This TitleBar widget is an OverlapGroup: all sub elements overlap,
    -- and can overflow or underflow. Its height for its containers is
    -- the one we set as self.dimen.h.

    self.titlebar_height = self.title_group:getSize().h
    if self.with_bottom_line then
        -- Be sure we add between the text and the line at least as much padding
        -- as above the text, to keep it vertically centered.
        local title_bottom_padding = math.max(self.title_top_padding, Size.padding.default)
        local filler_and_bottom_line = VerticalGroup:new{
            VerticalSpan:new{ width = self.titlebar_height + title_bottom_padding },
            LineWidget:new{
                dimen = Geom:new{ w = self.width, h = Size.line.thick },
            },
        }
        table.insert(self, filler_and_bottom_line)
        self.titlebar_height = filler_and_bottom_line:getSize().h
    end
    if not self.bottom_v_padding then
        if self.with_bottom_line then
            self.bottom_v_padding = Size.padding.default
        else
            self.bottom_v_padding = Size.padding.large
        end
    end
    self.titlebar_height = self.titlebar_height + self.bottom_v_padding

    self.dimen = Geom:new{
        w = self.width,
        h = self.titlebar_height, -- buttons can overflow this
    }

    if self.has_left_icon then
        self.left_button = IconButton:new{
            icon = self.left_icon,
            width = left_icon_size,
            height = left_icon_size,
            padding = self.button_padding,
            padding_right = 2 * left_icon_size, -- extend button tap zone
            padding_bottom = left_icon_size,
            overlap_align = "left",
            callback = self.left_icon_tap_callback,
            hold_callback = self.left_icon_hold_callback,
            allow_flash = self.left_icon_allow_flash
        }
        table.insert(self, self.left_button)
    end
    if self.has_right_icon then
        self.right_button = IconButton:new{
            icon = self.right_icon,
            width = right_icon_size,
            height = right_icon_size,
            padding = self.button_padding,
            padding_left = 2 * right_icon_size, -- extend button tap zone
            padding_bottom = right_icon_size,
            overlap_align = "right",
            callback = self.right_icon_tap_callback,
            hold_callback = self.right_icon_hold_callback,
            allow_flash = self.right_icon_allow_flash
        }
        table.insert(self, self.right_button)
    end

    -- We :extend() OverlapGroup and did not :new() it, so we can
    -- :init() it now, after we have added all the subelements.
    OverlapGroup.init(self)
end

function TitleBar:paintTo(bb, x, y)
    -- We need to update self.dimen's x and y for any ges.pos:intersectWith(title_bar)
    -- to work. (This is done by FrameContainer, but not by most other widgets... It
    -- should probably be done in all of them, but not sure of side effects...)
    self.dimen.x = x
    self.dimen.y = y
    OverlapGroup.paintTo(self, bb, x, y)
end

function TitleBar:getHeight()
    return self.titlebar_height
end

function TitleBar:setTitle(title)
    self.title_widget:setText(title)
    if self.inner_title_group then
        self.inner_title_group:resetLayout()
    end
    self.title_group:resetLayout()
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

function TitleBar:setSubTitle(subtitle)
    if self.subtitle_widget then
        self.subtitle_widget:setText(subtitle)
        if self.inner_title_group then
            self.inner_title_group:resetLayout()
        end
        self.title_group:resetLayout()
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setLeftIcon(icon)
    if self.has_left_icon then
        self.left_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function TitleBar:setRightIcon(icon)
    if self.has_right_icon then
        self.right_button:setIcon(icon)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end
return TitleBar
