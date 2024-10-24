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
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local TitleBar = OverlapGroup:extend{
    width = nil, -- default to screen width
    fullscreen = false, -- larger font and small adjustments if fullscreen
    align = "center", -- or "left": title & subtitle alignment inside TitleBar ("right" nor supported)

    with_bottom_line = false,
    bottom_line_color = nil, -- default to black
    bottom_line_h_padding = nil, -- default to 0: full width

    title = "",
    title_face = nil, -- if not provided, one of these will be used:
    title_face_fullscreen = Font:getFace("smalltfont"),
    title_face_not_fullscreen = Font:getFace("x_smalltfont"),
    -- by default: single line, truncated if overflow -- the default could be made dependent on self.fullscreen
    title_multilines = false, -- multilines if overflow
    title_shrink_font_to_fit = false, -- reduce font size so that single line text fits

    subtitle = nil,
    subtitle_face = Font:getFace("xx_smallinfofont"),
    subtitle_truncate_left = false, -- default with single line is to truncate right (set to true for a filepath)
    subtitle_fullwidth = false, -- true to allow subtitle to extend below the buttons
    subtitle_multilines = false, -- multilines if overflow

    info_text = nil, -- additional text displayed below bottom line
    info_text_face = Font:getFace("x_smallinfofont"),
    info_text_h_padding = nil, -- default to title_h_padding

    lang = nil, -- use this language (string) instead of the UI language

    title_top_padding = nil, -- computed if none provided
    title_h_padding = Size.padding.large, -- horizontal padding (this replaces button_padding on the inner/title side)
    title_subtitle_v_padding = Screen:scaleBySize(3),
    bottom_v_padding = nil, -- hardcoded default values, different whether with_bottom_line true or false

    button_padding = Screen:scaleBySize(11), -- fine to keep exit/cross icon diagonally aligned with screen corners
    left_icon = nil,
    left_icon_size_ratio = 0.6,
    left_icon_rotation_angle = 0,
    left_icon_tap_callback = function() end,
    left_icon_hold_callback = function() end,
    left_icon_allow_flash = true,
    right_icon = nil,
    right_icon_size_ratio = 0.6,
    right_icon_rotation_angle = 0,
    right_icon_tap_callback = function() end,
    right_icon_hold_callback = function() end,
    right_icon_allow_flash = true,
        -- set any of these _callback to false to not handle the event
        -- and let it propagate; otherwise the event is discarded

    -- If provided, use right_icon="exit" and use this as right_icon_tap_callback
    close_callback = nil,
    close_hold_callback = nil,

    show_parent = nil,

    -- Internal: remember first sizes computed when title_shrink_font_to_fit=true,
    -- and keep using them after :setTitle() in case a smaller font size is needed,
    -- to keep the TitleBar geometry stable.
    _initial_title_top_padding = nil,
    _initial_title_text_baseline = nil,
    _initial_titlebar_height = nil,
    _initial_filler_height = nil,
    _initial_re_init_needed = nil,
}

function TitleBar:init()
    if self.close_callback then
        self.right_icon = "close"
        self.right_icon_tap_callback = self.close_callback
        self.right_icon_allow_flash = false
        if self.close_hold_callback then
            self.right_icon_hold_callback = function() self.close_hold_callback() end
        end
    end

    if not self.width then
        self.width = Screen:getWidth()
    end

    local left_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * self.left_icon_size_ratio)
    local right_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * self.right_icon_size_ratio)
    self.has_left_icon = false
    self.has_right_icon = false

    -- No button on non-touch device
    local left_icon_reserved_width = 0
    local right_icon_reserved_width = 0
    if self.left_icon then
        self.has_left_icon = true
        left_icon_reserved_width = left_icon_size + self.button_padding
    end
    if self.right_icon then
        self.has_right_icon = true
        right_icon_reserved_width = right_icon_size + self.button_padding
    end

    if self.align == "center" then
        -- Keep title and subtitle text centered even if single button
        left_icon_reserved_width = math.max(left_icon_reserved_width, right_icon_reserved_width)
        right_icon_reserved_width = left_icon_reserved_width
    end
    local title_max_width = self.width - 2*self.title_h_padding - left_icon_reserved_width - right_icon_reserved_width
    local subtitle_max_width = self.width - 2*self.title_h_padding
    if not self.subtitle_fullwidth then
        subtitle_max_width = subtitle_max_width - left_icon_reserved_width - right_icon_reserved_width
    end

    -- Title, subtitle, and their alignment
    local title_face = self.title_face
    if not title_face then
        title_face = self.fullscreen and self.title_face_fullscreen or self.title_face_not_fullscreen
    end
    if self.title_multilines then
        self.title_widget = TextBoxWidget:new{
            text = self.title,
            alignment = self.align,
            width = title_max_width,
            face = title_face,
            lang = self.lang,
        }
    else
        while true do
            self.title_widget = TextWidget:new{
                text = self.title,
                face = title_face,
                padding = 0,
                lang = self.lang,
                max_width = not self.title_shrink_font_to_fit and title_max_width,
                    -- truncate if not self.title_shrink_font_to_fit
            }
            if not self.title_shrink_font_to_fit then
                break -- truncation allowed, no loop needed
            end
            if self.title_widget:getWidth() <= title_max_width then
                break -- text with normal font fits, no loop needed
            end
            -- Text doesn't fit
            if not self._initial_titlebar_height then
                -- We're with title_shrink_font_to_fit and in the first :init():
                -- we don't want to go on measuring with this too long text.
                -- We want metrics proper for when text fits, so if later :setTitle()
                -- is called with a text that fits, this text will look alright.
                -- Longer title with a smaller font size should be laid out on the
                -- baseline of a fitted text.
                -- So, go on computing sizes with an empty title. When all is
                -- gathered, we'll re :init() ourselves with the original title,
                -- using the metrics we're computing now (self._initial*).
                self._initial_re_init_needed = true
                self.title_widget:free(true)
                self.title_widget = TextWidget:new{
                    text = "",
                    face = title_face,
                    padding = 0,
                }
                break
            end
            -- otherwise, loop and do the same with a smaller font size
            self.title_widget:free(true)
            title_face = Font:getFace(title_face.orig_font, title_face.orig_size - 1)
        end
    end
    local title_top_padding = self.title_top_padding
    if not title_top_padding then
        -- Compute it so baselines of the text and of the icons align.
        -- Our icons' baselines looks like they could be at 83% to 90% of their height.
        local text_baseline = self.title_widget:getBaseline()
        local icon_height = math.max(left_icon_size, right_icon_size)
        local icon_baseline = icon_height * 0.85 + self.button_padding
        title_top_padding = Math.round(math.max(0,  icon_baseline - text_baseline))
        if self.title_shrink_font_to_fit then
            -- Use, or store, the first top padding and baseline we have computed,
            -- so the text stays vertically stable
            if self._initial_title_top_padding then
                -- Use this to have baselines aligned:
                -- title_top_padding = Math.round(self._initial_title_top_padding + self._initial_title_text_baseline - text_baseline)
                -- But then, smaller text is not vertically centered in the title bar.
                -- So, go with just half the baseline difference:
                title_top_padding = Math.round(self._initial_title_top_padding + (self._initial_title_text_baseline - text_baseline)/2)
            else
                self._initial_title_top_padding = title_top_padding
                self._initial_title_text_baseline = text_baseline
            end
        end
    end

    self.subtitle_widget = nil
    if self.subtitle then
        if self.subtitle_multilines then
            self.subtitle_widget = TextBoxWidget:new{
                text = self.subtitle,
                alignment = self.align,
                width = subtitle_max_width,
                face = self.subtitle_face,
                lang = self.lang,
            }
        else
            self.subtitle_widget = TextWidget:new{
                text = self.subtitle,
                face = self.subtitle_face,
                max_width = subtitle_max_width,
                truncate_left = self.subtitle_truncate_left,
                padding = 0,
                lang = self.lang,
            }
        end
    end
    -- To debug vertical positioning:
    -- local FrameContainer = require("ui/widget/container/framecontainer")
    -- self.title_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, self.title_widget}
    -- self.subtitle_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, self.subtitle_widget}

    self.title_group = VerticalGroup:new{
        align = self.align,
        overlap_align = self.align,
        VerticalSpan:new{width = title_top_padding},
    }
    if self.align == "left" then
        -- we need to :resetLayout() both VerticalGroup and HorizontalGroup in :setTitle()
        self.inner_title_group = HorizontalGroup:new{
            HorizontalSpan:new{ width = left_icon_reserved_width + self.title_h_padding },
            self.title_widget,
        }
        table.insert(self.title_group, self.inner_title_group)
    else
        table.insert(self.title_group, self.title_widget)
    end
    if self.subtitle_widget then
        table.insert(self.title_group, VerticalSpan:new{width = self.title_subtitle_v_padding})
        if self.align == "left" then
            local span_width = self.title_h_padding
            if not self.subtitle_fullwidth then
                span_width = span_width + left_icon_reserved_width
            end
            self.inner_subtitle_group = HorizontalGroup:new{
                HorizontalSpan:new{ width = span_width },
                self.subtitle_widget,
            }
            table.insert(self.title_group, self.inner_subtitle_group)
        else
            table.insert(self.title_group, self.subtitle_widget)
        end
    end
    table.insert(self, self.title_group)

    -- This TitleBar widget is an OverlapGroup: all sub elements overlap,
    -- and can overflow or underflow. Its height for its containers is
    -- the one we set as self.dimen.h.

    self.titlebar_height = self.title_group:getSize().h
    if self.title_shrink_font_to_fit then
        -- Use, or store, the first title_group height we have computed,
        -- so the TitleBar geometry and the bottom line position stay stable
        -- (face height may have changed, even after we kept the baseline
        -- stable, as we did above).
        if self._initial_titlebar_height then
            self.titlebar_height = self._initial_titlebar_height
        else
            self._initial_titlebar_height = self.titlebar_height
        end
    end

    if self.with_bottom_line then
        -- Be sure we add between the text and the line at least as much padding
        -- as above the text, to keep it vertically centered.
        local title_bottom_padding = math.max(title_top_padding, Size.padding.default)
        local filler_height = self.titlebar_height + title_bottom_padding
        if self.title_shrink_font_to_fit then
            -- Use, or store, the first filler height we have computed,
            if self._initial_filler_height then
                filler_height = self._initial_filler_height
            else
                self._initial_filler_height = filler_height
            end
        end
        local line_widget = LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thick },
            background = self.bottom_line_color
        }
        if self.bottom_line_h_padding then
            line_widget.dimen.w = line_widget.dimen.w - 2 * self.bottom_line_h_padding
            line_widget = HorizontalGroup:new{
                HorizontalSpan:new{ width = self.bottom_line_h_padding },
                line_widget,
            }
        end
        local filler_and_bottom_line = VerticalGroup:new{
            VerticalSpan:new{ width = filler_height },
            line_widget,
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

    if self._initial_re_init_needed then
        -- We have computed all the self._initial_ metrics needed.
        self._initial_re_init_needed = nil
        self:clear()
        self:init()
        return
    end

    if self.info_text then
        local h_padding = self.info_text_h_padding or self.title_h_padding
        local v_padding = self.with_bottom_line and Size.padding.default or 0
        local filler_and_info_text = VerticalGroup:new{
            VerticalSpan:new{ width = self.titlebar_height + v_padding },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = h_padding },
                TextBoxWidget:new{
                    text = self.info_text,
                    face = self.info_text_face,
                    width = self.width - 2 * h_padding,
                    lang = self.lang,
                }
            }
        }
        table.insert(self, filler_and_info_text)
        self.titlebar_height = filler_and_info_text:getSize().h + self.bottom_v_padding
    end

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.titlebar_height, -- buttons can overflow this
    }

    if self.has_left_icon then
        self.left_button = IconButton:new{
            icon = self.left_icon,
            icon_rotation_angle = self.left_icon_rotation_angle,
            width = left_icon_size,
            height = left_icon_size,
            padding = self.button_padding,
            padding_right = 2 * left_icon_size, -- extend button tap zone
            padding_bottom = left_icon_size,
            overlap_align = "left",
            callback = self.left_icon_tap_callback,
            hold_callback = self.left_icon_hold_callback,
            allow_flash = self.left_icon_allow_flash,
            show_parent = self.show_parent,
        }
        table.insert(self, self.left_button)
    end
    if self.has_right_icon then
        self.right_button = IconButton:new{
            icon = self.right_icon,
            icon_rotation_angle = self.right_icon_rotation_angle,
            width = right_icon_size,
            height = right_icon_size,
            padding = self.button_padding,
            padding_left = 2 * right_icon_size, -- extend button tap zone
            padding_bottom = right_icon_size,
            overlap_align = "right",
            callback = self.right_icon_tap_callback,
            hold_callback = self.right_icon_hold_callback,
            allow_flash = self.right_icon_allow_flash,
            show_parent = self.show_parent,
        }
        table.insert(self, self.right_button)
    end

    -- Call our base class's init (especially since OverlapGroup has very peculiar self.dimen semantics...)
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

function TitleBar:setTitle(title, no_refresh)
    if self.title_multilines or self.title_shrink_font_to_fit then
        -- We need to re-init the whole widget as its height or
        -- padding may change.
        local previous_height = self.titlebar_height
        -- Call WidgetContainer:clear() that will call :free() and
        -- will remove subwidgets from the OverlapGroup we are.
        self:clear()
        self.title = title
        self:init()
        if no_refresh then
            -- If caller is sure to handle refresh correctly, it can provides this
            return
        end
        if self.title_multilines and self.titlebar_height ~= previous_height then
            -- Title height have changed, and the upper widget may not have
            -- hooks to refresh a combination of its previous size and new
            -- size: be sure everything is repainted
            UIManager:setDirty("all", "ui")
        else
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
    else
        -- TextWidget with max-width: we can just update its text
        self.title_widget:setText(title)
        if self.inner_title_group then
            self.inner_title_group:resetLayout()
        end
        self.title_group:resetLayout()
        if not no_refresh then
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
    end
end

function TitleBar:setSubTitle(subtitle, no_refresh)
    if self.subtitle_widget and not self.subtitle_multilines then -- no TextBoxWidget:setText() available
        self.subtitle_widget:setText(subtitle)
        if self.inner_subtitle_group then
            self.inner_subtitle_group:resetLayout()
        end
        self.title_group:resetLayout()
        if not no_refresh then
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
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

-- layout for FocusManager
function TitleBar:generateHorizontalLayout()
    local row = {}
    if self.left_button then
        table.insert(row, self.left_button)
    end
    if self.right_button then
        table.insert(row, self.right_button)
    end
    local layout = {}
    if #row > 0 then
        table.insert(layout, row)
    end
    return layout
end

function TitleBar:generateVerticalLayout()
    local layout = {}
    if self.left_button then
        table.insert(layout, {self.left_button})
    end
    if self.right_button then
        table.insert(layout, {self.right_button})
    end
    return layout
end
return TitleBar
