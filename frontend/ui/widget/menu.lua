local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local Utf8Proc = require("ffi/utf8proc")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = ffiUtil.template

--[[--
Widget that displays a shortcut icon for menu item.
--]]
local ItemShortCutIcon = WidgetContainer:extend{
    dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
    key = nil,
    bordersize = Size.border.default,
    radius = 0,
    style = "square",
}

function ItemShortCutIcon:init()
    if not self.key then
        return
    end

    local radius = 0
    local background = Blitbuffer.COLOR_WHITE
    if self.style == "rounded_corner" then
        radius = math.floor(self.width / 2)
    elseif self.style == "grey_square" then
        background = Blitbuffer.COLOR_LIGHT_GRAY
    end

    --- @todo Calculate font size by icon size  01.05 2012 (houqp).
    local sc_face
    if self.key:len() > 1 then
        sc_face = Font:getFace("ffont", 14)
    else
        sc_face = Font:getFace("scfont", 22)
    end

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = self.bordersize,
        radius = radius,
        background = background,
        dimen = self.dimen:copy(),
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{
                text = self.key,
                face = sc_face,
            },
        },
    }
end

--[[
Widget that displays an item for menu
--]]
local MenuItem = InputContainer:extend{
    font = "smallinfofont",
    infont = "infont",
    linesize = Size.line.medium,
    single_line = false,
    multilines_forced = false, -- set to true to always use TextBoxWidget
    multilines_show_more_text = false,
    -- Align text & mandatory baselines (only when single_line=true)
    align_baselines = false,
    -- Show a line of dots (also called tab or dot leaders) between text and mandatory
    with_dots = false,
}

function MenuItem:init()
    self.content_width = self.dimen.w - 2 * Size.padding.fullscreen

    local shortcut_icon_dimen
    if self.shortcut then
        local icon_width = self.entry.shortcut_icon_width or math.floor(self.dimen.h * 4/5)
        shortcut_icon_dimen = Geom:new{
            x = 0,
            y = 0,
            w = icon_width,
            h = icon_width,
        }
        self.content_width = self.content_width - shortcut_icon_dimen.w - Size.span.horizontal_default
    end

    -- we need this table per-instance, so we declare it here
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
                range = self.dimen,
            },
        },
    }

    local max_item_height = self.dimen.h - 2 * self.linesize

    -- We want to show at least one line, so cap the provided font sizes
    local max_font_size = TextBoxWidget:getFontSizeToFitHeight(max_item_height, 1)
    if self.font_size > max_font_size then
        self.font_size = max_font_size
    end
    if self.infont_size > max_font_size then
        self.infont_size = max_font_size
    end
    if not self.single_line and not self.multilines_forced
            and not self.multilines_show_more_text and not self.items_max_lines then
        -- For non single line menus (File browser, Bookmarks), if the
        -- user provided font size is large and would not allow showing
        -- more than one line in our item height, just switch to single
        -- line mode. This allows, when truncating, to take the full
        -- width and cut inside a word to add the ellipsis - while in
        -- multilines modes, with TextBoxWidget, words are wrapped to
        -- follow line breaking rules, and the ellipsis might be placed
        -- way earlier than the full width.
        local min_font_size_2_lines = TextBoxWidget:getFontSizeToFitHeight(max_item_height, 2)
        if self.font_size > min_font_size_2_lines then
            self.single_line = true
        end
    end

    -- State button and indentation for tree expand/collapse (for TOC)
    local state_button = self.entry.state or HorizontalSpan:new{}
    local state_indent = self.entry.indent or 0
    local state_width = state_indent + (self.state_w or 0)
    local state_container = LeftContainer:new{
        dimen = Geom:new{w = math.floor(self.content_width / 2), h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = state_indent,
            },
            state_button,
        }
    }

    -- Font for main text (may have its size decreased to make text fit)
    self.face = Font:getFace(self.font, self.font_size)
    -- Font for "mandatory" on the right
    self.info_face = Font:getFace(self.infont, self.infont_size)
    -- Font for post_text if any: for now, this is only used with TOC, showing
    -- the chapter length: if feels best to use the face of the main text, but
    -- with the size of the mandatory font (which shows some number too).
    if self.post_text then
        self.post_text_face = Font:getFace(self.font, self.infont_size)
    end

    -- "mandatory" is the text on the right: file size, page number...
    -- Padding before mandatory
    local text_mandatory_padding = 0
    local text_ellipsis_mandatory_padding = 0
    local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
    local mandatory_dim = self.mandatory_dim_func and self.mandatory_dim_func() or self.mandatory_dim
    if mandatory then
        text_mandatory_padding = Size.span.horizontal_default
        -- Smaller padding when ellipsis for better visual feeling
        text_ellipsis_mandatory_padding = Size.span.horizontal_small
    end
    local mandatory_widget = TextWidget:new{
        text = mandatory or "",
        face = self.info_face,
        bold = self.bold,
        fgcolor = mandatory_dim and Blitbuffer.COLOR_DARK_GRAY or nil,
    }
    local mandatory_w = mandatory_widget:getWidth()

    local available_width = self.content_width - state_width - text_mandatory_padding - mandatory_w
    local item_name

    -- Whether we show text on a single or multiple lines, we don't want it shortened
    -- because of some \n that would push the following text on another line that would
    -- overflow and not be displayed, or show a tofu char when displayed by TextWidget:
    -- get rid of any \n (which could be found in highlighted text in bookmarks).
    local text = self.text:gsub("\n", " ")

    -- Wrap text with provided bidi_wrap_func (only provided by FileChooser,
    -- to correctly display filenames and directories)
    if self.bidi_wrap_func then
        text = self.bidi_wrap_func(text)
    end

    -- Note: support for post_text is currently implemented only when single_line=true
    local post_text_widget
    local post_text_left_padding = Size.padding.large
    local post_text_right_padding = self.with_dots and 0 or Size.padding.large
    local dots_widget
    local dots_left_padding = Size.padding.small
    local dots_right_padding = Size.padding.small

    if self.single_line then
        -- Items only in single line
        if self.post_text then
            post_text_widget = TextWidget:new{
                text = self.post_text,
                face = self.post_text_face,
                bold = self.bold,
                fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            }
            available_width = available_width - post_text_widget:getWidth() - post_text_left_padding - post_text_right_padding
        end
        -- No font size change: text will be truncated if it overflows
        item_name = TextWidget:new{
            text = text,
            face = self.face,
            bold = self.bold,
            truncate_left = self.truncate_left,
            fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        }
        local w = item_name:getWidth()
        if w > available_width then
            local text_max_width_if_ellipsis = available_width
            -- We give it a little more room if truncated at the right for better visual
            -- feeling (which might make it no more truncated, but well...)
            if not self.truncate_left then
                text_max_width_if_ellipsis = text_max_width_if_ellipsis + text_mandatory_padding - text_ellipsis_mandatory_padding
            end
            item_name:setMaxWidth(text_max_width_if_ellipsis)
        else
            if self.with_dots then
                local dots_width = available_width + text_mandatory_padding - w - dots_left_padding - dots_right_padding
                if dots_width > 0 then
                    local dots_text, dots_min_width = self:getDotsText(self.info_face)
                    -- Don't show any dots if there would be less than 3
                    if dots_width >= dots_min_width then
                        dots_widget = TextWidget:new{
                            text = dots_text,
                            face = self.info_face, -- same as mandatory widget, to keep their baseline adjusted
                            max_width = dots_width,
                            truncate_with_ellipsis = false,
                        }
                    end
                end
            end
        end
        if self.align_baselines then -- Align baselines of text and mandatory
            -- The container widgets would additionally center these widgets,
            -- so make sure they all get a height=self.dimen.h so they don't
            -- risk being shifted later and becoming misaligned
            local name_baseline = item_name:getBaseline()
            local mdtr_baseline = mandatory_widget:getBaseline()
            local name_height = item_name:getSize().h
            local mdtr_height = mandatory_widget:getSize().h
            -- Make all the TextWidgets be self.dimen.h
            item_name.forced_height = self.dimen.h
            mandatory_widget.forced_height = self.dimen.h
            if dots_widget then
                dots_widget.forced_height = self.dimen.h
            end
            if post_text_widget then
                post_text_widget.forced_height = self.dimen.h
            end
            -- And adjust their baselines for proper centering and alignment
            -- (We made sure the font sizes wouldn't exceed self.dimen.h, so we
            -- get only non-negative pad_top here, and we're moving them down.)
            local name_missing_pad_top = math.floor( (self.dimen.h - name_height) / 2)
            local mdtr_missing_pad_top = math.floor( (self.dimen.h - mdtr_height) / 2)
            name_baseline = name_baseline + name_missing_pad_top
            mdtr_baseline = mdtr_baseline + mdtr_missing_pad_top
            local baselines_diff = Math.round(name_baseline - mdtr_baseline)
            if baselines_diff > 0 then
                mdtr_baseline = mdtr_baseline + baselines_diff
            else
                name_baseline = name_baseline - baselines_diff
            end
            item_name.forced_baseline = name_baseline
            mandatory_widget.forced_baseline = mdtr_baseline
            if dots_widget then
                dots_widget.forced_baseline = mdtr_baseline
            end
            if post_text_widget then
                post_text_widget.forced_baseline = mdtr_baseline
            end
        end

    elseif self.multilines_show_more_text then
        -- Multi-lines, with font size decrease if needed to show more of the text.
        -- It would be costly/slow with use_xtext if we were to try all
        -- font sizes from self.font_size to min_font_size.
        -- So, we try to optimize the search of the best font size.
        logger.dbg("multilines_show_more_text menu item font sizing start")
        local function make_item_name(font_size)
            if item_name then
                item_name:free()
            end
            logger.dbg("multilines_show_more_text trying font size", font_size)
            item_name = TextBoxWidget:new {
                text = text,
                face = Font:getFace(self.font, font_size),
                width = available_width,
                alignment = "left",
                bold = self.bold,
                fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            }
            -- return true if we fit
            return item_name:getSize().h <= max_item_height
        end
        -- To keep item readable, do not decrease font size by more than 8 points
        -- relative to the specified font size, being not smaller than 12 absolute points.
        local min_font_size = math.max(12, self.font_size - 8)
        -- First, try with specified font size: short text might fit
        if not make_item_name(self.font_size) then
            -- It doesn't, try with min font size: very long text might not fit
            if not make_item_name(min_font_size) then
                -- Does not fit with min font size: keep widget with min_font_size, but
                -- impose a max height to show only the first lines up to where it fits
                item_name:free()
                item_name.height = max_item_height
                item_name.height_adjust = true
                item_name.height_overflow_show_ellipsis = true
                item_name:init()
            else
                -- Text fits with min font size: try to find some larger
                -- font size in between that make text fit, with some
                -- binary search to limit the number of checks.
                local bad_font_size = self.font_size
                local good_font_size = min_font_size
                local item_name_is_good = true
                while true do
                    local test_font_size = math.floor((good_font_size + bad_font_size) / 2)
                    if test_font_size == good_font_size then -- +1 would be bad_font_size
                        if not item_name_is_good then
                            make_item_name(good_font_size)
                        end
                        break
                    end
                    if make_item_name(test_font_size) then
                        good_font_size = test_font_size
                        item_name_is_good = true
                    else
                        bad_font_size = test_font_size
                        item_name_is_good = false
                    end
                end
            end
        end

    else
        -- Multi-lines, with fixed user provided font size
        item_name = TextBoxWidget:new {
            text = text,
            face = self.face,
            width = available_width,
            height = self.entry.height and (self.entry.height - 2 * Size.span.vertical_default - self.linesize) or max_item_height,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            bold = self.bold,
            fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        }
    end

    local text_container = LeftContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = state_width,
            },
            item_name,
            post_text_widget and HorizontalSpan:new{ width = post_text_left_padding },
            post_text_widget,
        }
    }

    if dots_widget then
        mandatory_widget = HorizontalGroup:new{
            dots_widget,
            HorizontalSpan:new{ width = dots_right_padding },
            mandatory_widget,
        }
    end
    local mandatory_container = RightContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        mandatory_widget,
    }

    self._underline_container = UnderlineContainer:new{
        color = self.line_color,
        linesize = self.linesize,
        vertical_align = "center",
        padding = 0,
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.content_width,
            h = self.dimen.h
        },
        HorizontalGroup:new{
            align = "center",
            OverlapGroup:new{
                dimen = Geom:new{w = self.content_width, h = self.dimen.h},
                state_container,
                text_container,
                mandatory_container,
            },
        }
    }
    local hgroup = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = self.items_padding or Size.padding.fullscreen },
    }
    if self.shortcut then
        table.insert(hgroup, self.menu:getItemShortCutIcon(shortcut_icon_dimen, self.shortcut, self.shortcut_style))
        table.insert(hgroup, HorizontalSpan:new{ width = Size.span.horizontal_default })
    end
    table.insert(hgroup, self._underline_container)
    table.insert(hgroup, HorizontalSpan:new{ width = Size.padding.fullscreen })

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        hgroup,
    }
end

local _dots_cached_info
function MenuItem:getDotsText(face)
    local screen_w = Screen:getWidth()
    if not _dots_cached_info or _dots_cached_info.screen_width ~= screen_w
                    or _dots_cached_info.face ~= face then
        local unit = "."
        local tmp = TextWidget:new{
            text = unit,
            face = face,
        }
        local unit_w = tmp:getSize().w
        tmp:free()
        -- (We assume/expect no kerning will happen between consecutive units)
        local nb_units = math.ceil(screen_w / unit_w)
        local min_width = unit_w * 3 -- have it not shown if smaller than this
        local text = unit:rep(nb_units)
        _dots_cached_info = {
            text = text,
            min_width = min_width,
            screen_width = screen_w,
            face = face,
        }
    end
    return _dots_cached_info.text, _dots_cached_info.min_width
end

function MenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    -- NOTE: Medium is really, really, really thin; so we'd ideally swap to something thicker...
    --       Unfortunately, this affects vertical text positioning,
    --       leading to an unsightly refresh of the item :/.
    --self._underline_container.linesize = Size.line.thick
    return true
end

function MenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    -- See above for reasoning.
    --self._underline_container.linesize = self.linesize
    return true
end

function MenuItem:getGesPosition(ges)
    local dimen = self[1].dimen
    return {
        x = (ges.pos.x - dimen.x) / dimen.w,
        y = (ges.pos.y - dimen.y) / dimen.h,
    }
end

function MenuItem:onTapSelect(arg, ges)
    -- Abort if the menu hasn't been painted yet.
    if not self[1].dimen then return end

    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuSelect(self.entry, pos)
    else
        -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        -- Highlight
        --
        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "fast", self[1].dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "ui", self[1].dimen)

        -- Callback
        --
        self.menu:onMenuSelect(self.entry, pos)

        UIManager:forceRePaint()
    end
    return true
end

function MenuItem:onHoldSelect(arg, ges)
    if not self[1].dimen then return end

    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.entry, pos)
    else
        -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        -- Highlight
        --
        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "fast", self[1].dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "ui", self[1].dimen)

        -- Callback
        --
        self.menu:onMenuHold(self.entry, pos)

        UIManager:forceRePaint()
    end
    return true
end

--[[
Widget that displays menu
--]]
local Menu = FocusManager:extend{
    show_parent = nil,

    no_title = false,
    title = "",
    custom_title_bar = nil,
    subtitle = nil,
    show_path = nil, -- path in titlebar subtitle
    -- default width and height
    width = nil,
    -- height will be calculated according to item number if not given
    height = nil,
    dimen = nil,
    item_table = nil, -- NOT mandatory (will be empty)
    item_table_stack = nil,

    item_shortcuts = { -- const
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
        "Z", "X", "C", "V", "B", "N", "M", ".", "Sym",
    },
    is_enable_shortcut = Device:hasKeyboard(),

    item_dimen = nil,
    page = 1,

    item_group = nil,
    page_info = nil,
    page_return = nil,

    items_per_page_default = 14,
    items_per_page = nil,
    items_font_size = nil,
    items_mandatory_font_size = nil,
    multilines_show_more_text = nil,
    -- Global settings or default values will be used if not provided
    -- Setting this to a number enables flexible height of items
    -- and sets the maximum number of lines in an item, longer items are truncated
    items_max_lines = nil,

    -- set this to true to not paint as popup menu
    is_borderless = false,
    -- if you want to embed the menu widget into another widget, set
    -- this to false
    is_popout = true,
    title_bar_fm_style = nil, -- set to true to mimic FileManager's custom title bar (extra padding & subtitle)
    -- set icon to add title bar left button
    title_bar_left_icon = nil,
    -- close_callback is a function, which is executed when menu is closed
    -- it is usually set by the widget which creates the menu
    close_callback = nil,
    linesize = Size.line.medium,
    line_color = Blitbuffer.COLOR_DARK_GRAY,
}

function Menu:getItemShortCutIcon(dimen, key, style)
    return ItemShortCutIcon:new{
        dimen = dimen,
        key = key,
        style = style,
    }
end

function Menu:_recalculateDimen(no_recalculate_dimen)
    local perpage = self.items_per_page or G_reader_settings:readSetting("items_per_page") or self.items_per_page_default
    local font_size = self.items_font_size or G_reader_settings:readSetting("items_font_size") or Menu.getItemFontSize(perpage)
    if self.perpage ~= perpage or self.font_size ~= font_size then
        self.perpage = perpage
        self.font_size = font_size
        no_recalculate_dimen = false
    end

    if no_recalculate_dimen then return end

    local top_height = 0
    if self.title_bar and not self.no_title then
        top_height = self.title_bar:getHeight()
    end
    local bottom_height = 0
    if self.page_return_arrow and self.page_info_text then
        -- The extra padding is for UX reasons only, to leave a bit of space above the footer.
        bottom_height = math.max(self.page_return_arrow:getSize().h, self.page_info_text:getSize().h)
                      + Size.padding.button
    end
    self.available_height = self.inner_dimen.h - top_height - bottom_height
    self.item_dimen = Geom:new{
        x = 0, y = 0,
        w = self.inner_dimen.w,
        h = math.floor(self.available_height / perpage),
    }

    if self.items_max_lines then
        self:setupItemHeights()
    end

    self.page_num = self:getPageNumber(#self.item_table)
    if self.page > self.page_num then
        self.page = self.page_num
    end
end

function Menu:init()
    self.show_parent = self.show_parent or self
    self.item_table = self.item_table or {}
    self.item_table_stack = {}
    self.page = 1

    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width or self.screen_w, h = self.height or self.screen_h }
    if self.dimen.h > self.screen_h then
        self.dimen.h = self.screen_h
    end

    self.border_size = self.is_borderless and 0 or Size.border.window
    self.inner_dimen = Geom:new{
        w = self.dimen.w - 2 * self.border_size,
        h = self.dimen.h - 2 * self.border_size,
    }

    self.paths = {}  -- per instance table to trace navigation path

    -----------------------------------
    -- start to set up widget layout --
    -----------------------------------
    if self.show_path or not self.no_title then
        if self.subtitle == nil and (self.show_path or self.title_bar_fm_style) then
            self.subtitle = ""
        end
        self.title_bar = self.custom_title_bar or TitleBar:new{
            width = self.dimen.w,
            fullscreen = "true",
            align = "center",
            with_bottom_line = self.with_bottom_line,
            bottom_line_color = self.bottom_line_color,
            bottom_line_h_padding = self.bottom_line_h_padding,
            title = self.title,
            title_face = self.title_face,
            title_multilines = self.title_multilines,
            title_shrink_font_to_fit = self.title_shrink_font_to_fit,
            subtitle = self.subtitle,
            subtitle_truncate_left = self.show_path,
            subtitle_fullwidth = self.show_path,
            title_top_padding = self.title_bar_fm_style and Screen:scaleBySize(6),
            button_padding = self.title_bar_fm_style and Screen:scaleBySize(5),
            left_icon = self.title_bar_left_icon,
            left_icon_size_ratio = self.title_bar_fm_style and 1,
            left_icon_tap_callback = function() self:onLeftButtonTap() end,
            left_icon_hold_callback = function() self:onLeftButtonHold() end,
            right_icon_size_ratio = self.title_bar_fm_style and 1,
            close_callback = function() self:onClose() end,
            show_parent = self.show_parent or self,
        }
    end

    -- group for items
    self.item_group = VerticalGroup:new{}
    -- group for page info
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.page_info_left_chev = self.page_info_left_chev or Button:new{
        icon = chevron_left,
        callback = function() self:onPrevPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_right_chev = self.page_info_right_chev or Button:new{
        icon = chevron_right,
        callback = function() self:onNextPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_first_chev = self.page_info_first_chev or Button:new{
        icon = chevron_first,
        callback = function() self:onFirstPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_last_chev = self.page_info_last_chev or Button:new{
        icon = chevron_last,
        callback = function() self:onLastPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }
    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()

    local buttons = {
        {
            {
                text = self.search_callback and _("Search…") or _("Search"),
                callback = function()
                    local search_string = self.page_info_text.input_dialog:getInputText()
                    if self.search_callback then
                        self.search_callback(search_string)
                        self.page_info_text:closeInputDialog()
                    else
                        if search_string ~= "" then
                            self:goToMenuItemMatching(search_string)
                            self.page_info_text:closeInputDialog()
                        end
                    end
                end,
            },
            {
                text = _("Go to letter"),
                callback = function()
                    local search_string = self.page_info_text.input_dialog:getInputText()
                    if search_string ~= "" then
                        self:goToMenuItemMatching(search_string, true)
                        self.page_info_text:closeInputDialog()
                    end
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    self.page_info_text:closeInputDialog()
                end,
            },
            {
                text = _("Go to page"),
                callback = function()
                    local page = tonumber(self.page_info_text.input_dialog:getInputText())
                    if page and page >= 1 and page <= self.page_num then
                        self:onGotoPage(page)
                        self.page_info_text:closeInputDialog()
                    end
                end,
            },
        },
    }
    self.page_info_text = self.page_info_text or Button:new{
        text = "",
        text_font_bold = false,
        bordersize = 0,
        call_hold_input_on_tap = true,
        hold_input = {
            title = _("Enter text, letter or page number"),
            hint_func = function()
                -- @translators First group is the standard range for alphabetic searches, second group is a page number range
                return T(_("(a - z) or (1 - %1)"), self.page_num)
            end,
            buttons = buttons,
        },
    }
    self.page_info = HorizontalGroup:new{
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_spacer,
        self.page_info_text,
        self.page_info_spacer,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    -- return button
    self.page_return_arrow = self.page_return_arrow or Button:new{
        icon = "back.top",
        callback = function()
            if self.onReturn then self:onReturn() end
        end,
        hold_callback = function()
            if self.onHoldReturn then self:onHoldReturn() end
        end,
        bordersize = 0,
        show_parent = self.show_parent,
        readonly = self.return_arrow_propagation,
    }
    self.page_return_arrow:hide()
    self.return_button = HorizontalGroup:new{
        HorizontalSpan:new{
            width = Size.span.horizontal_small,
        },
        self.page_return_arrow,
    }

    local header = self.no_title and VerticalSpan:new{ width = 0 } or self.title_bar
    local body = self.item_group
    local footer = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        self.page_info,
    }
    local page_return = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        WidgetContainer:new{
            dimen = Geom:new{
                x = 0, y = 0,
                w = self.screen_w,
                h = self.page_return_arrow:getSize().h,
            },
            self.return_button,
        }
    }

    self:_recalculateDimen()
    self.content_group = VerticalGroup:new{
        align = "left",
        header,
        body,
    }
    local content = OverlapGroup:new{
        -- This unique allow_mirroring=false looks like it's enough
        -- to have this complex Menu, and all widgets based on it,
        -- be mirrored correctly with RTL languages
        allow_mirroring = false,
        dimen = self.inner_dimen:copy(),
        self.content_group,
        page_return,
        footer,
    }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.border_size,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w * (1/20)) or 0,
        content
    }

    ------------------------------------------
    -- start to set up input event callback --
    ------------------------------------------
    -- watch for outer region if it's a self contained widget
    if self.is_popout then
        self.ges_events.TapCloseAllMenus = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = self.screen_w,
                    h = self.screen_h,
                }
            }
        }
    end
    -- delegate swipe gesture to GestureManager in filemanager
    if self.name ~= "filemanager" then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = self.dimen,
            }
        }
    end
    self.ges_events.Pan = { -- (for mousewheel scrolling support)
        GestureRange:new{
            ges = "pan",
            range = self.dimen,
        }
    }
    self.ges_events.Close = self.on_close_ges

    if Device:hasKeys() then
        -- set up keyboard events
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.LeftButtonTap = { { "Menu" } }
        if Device:hasFewKeys() then
            self.key_events.Close = { { "Left" } }
        end
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
        if Device:hasKeyboard() then
            self.key_events.FirstPage = { { "Shift", { "LPgBack", "RPgBack" } } }
            self.key_events.LastPage = { { "Shift", { "LPgFwd", "RPgFwd" } } }
            self.key_events.ShowGotoDialog = { { "Shift", "Down" } }
        elseif Device:hasScreenKB() then
            self.key_events.FirstPage = { { "ScreenKB", { "LPgBack", "RPgBack" } } }
            self.key_events.LastPage = { { "ScreenKB", { "LPgFwd", "RPgFwd" } } }
            self.key_events.ShowGotoDialog = { { "ScreenKB", "Down" } }
        end
    end

    if Device:hasDPad() then
        if Device:hasFewKeys() then
            -- we won't catch presses to "Right", leave that to MenuItem.
            self.key_events.FocusRight = nil
            -- add long press on "Right" key
            self.key_events.Right = { { "Right" } }
        end
        -- shortcut icon is not needed for touch device
        if self.is_enable_shortcut then
            self.key_events.SelectByShortCut = { { self.item_shortcuts } }
        end
    end

    if self.item_table.current then
        self.page = self:getPageNumber(self.item_table.current)
    end
    if not self.path_items then -- not FileChooser
        self:updateItems(1, true)
    end
end

function Menu:updatePageInfo(select_number)
    if #self.item_table > 0 then
        local is_focused = self.itemnumber and self.itemnumber > 0
        if is_focused or Device:hasDPad() then
            self.prev_itemnumber = self.itemnumber -- for CoverBrowser
            self.itemnumber = nil -- focus only once
            select_number = select_number or 1 -- default to select the first item
            local x, y
            local nb_cols = self.layout[1] and #self.layout[1] or 1
            if nb_cols == 1 then
                x = 1
                y = select_number
            else -- mosaic
                x = select_number % nb_cols
                x = x ~= 0 and x or nb_cols
                y = (select_number - x) / nb_cols + 1
            end
            -- Reset focus manager accordingly.
            -- NOTE: Since this runs automatically on init,
            --       we use FOCUS_ONLY_ON_NT as we don't want to see the initial underline on Touch devices.
            self:moveFocusTo(x, y, is_focused and FocusManager.FORCED_FOCUS or FocusManager.FOCUS_ONLY_ON_NT)
        end
        -- update page information
        self.page_info_text:setText(T(_("Page %1 of %2"), self.page, self.page_num))
        if self.page_num > 1 then
            self.page_info_text:enable()
        else
            self.page_info_text:disableWithoutDimming()
        end
        self.page_info_left_chev:show()
        self.page_info_right_chev:show()
        self.page_info_first_chev:show()
        self.page_info_last_chev:show()
        self.page_return_arrow:showHide(self.onReturn ~= nil)

        self.page_info_left_chev:enableDisable(self.page > 1)
        self.page_info_right_chev:enableDisable(self.page < self.page_num)
        self.page_info_first_chev:enableDisable(self.page > 1)
        self.page_info_last_chev:enableDisable(self.page < self.page_num)
        self.page_return_arrow:enableDisable(#self.paths > 0)
    else
        self.page_info_text:setText(_("No items"))
        self.page_info_text:disableWithoutDimming()

        self.page_info_left_chev:hide()
        self.page_info_right_chev:hide()
        self.page_info_first_chev:hide()
        self.page_info_last_chev:hide()
        self.page_return_arrow:showHide(self.onReturn ~= nil)
    end
end

function Menu:updateItems(select_number, no_recalculate_dimen)
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self:_recalculateDimen(no_recalculate_dimen)

    local items_nb -- number of items in the visible page
    local idx_offset, multilines_show_more_text
    if self.items_max_lines then
        items_nb = #self.page_items[self.page]
    else
        items_nb = self.perpage
        idx_offset = (self.page - 1) * items_nb
        multilines_show_more_text = self.multilines_show_more_text
        if multilines_show_more_text == nil then
            multilines_show_more_text = G_reader_settings:isTrue("items_multilines_show_more_text")
        end
    end

    for idx = 1, items_nb do
        local index = self.items_max_lines and self.page_items[self.page][idx] or idx_offset + idx
        local item = self.item_table[index]
        if item == nil then break end
        item.idx = index -- index is valid only for items that have been displayed
        if index == self.itemnumber then -- focused item
            select_number = idx
        end
        local item_shortcut, shortcut_style
        if self.is_enable_shortcut then
            item_shortcut = self.item_shortcuts[idx]
            -- give different shortcut_style to keys in different lines of keyboard
            shortcut_style = (idx < 11 or idx > 20) and "square" or "grey_square"
        end
        if self.items_max_lines then
            self.item_dimen.h = item.height
        end
        local item_tmp = MenuItem:new{
            idx = index,
            show_parent = self.show_parent,
            state_w = self.state_w,
            text = Menu.getMenuText(item),
            bidi_wrap_func = item.bidi_wrap_func,
            post_text = item.post_text,
            mandatory = item.mandatory,
            mandatory_func = item.mandatory_func,
            mandatory_dim = item.mandatory_dim or item.dim,
            mandatory_dim_func = item.mandatory_dim_func,
            bold = self.item_table.current == index or item.bold == true,
            dim = item.dim,
            font_size = self.font_size,
            infont_size = self.items_mandatory_font_size or (self.font_size - 4),
            dimen = self.item_dimen:copy(),
            shortcut = item_shortcut,
            shortcut_style = shortcut_style,
            entry = item,
            menu = self,
            linesize = self.linesize,
            single_line = self.single_line,
            multilines_forced = self.multilines_forced,
            multilines_show_more_text = multilines_show_more_text,
            items_max_lines = self.items_max_lines,
            truncate_left = self.truncate_left,
            align_baselines = self.align_baselines,
            with_dots = self.with_dots,
            line_color = self.line_color,
            items_padding = self.items_padding,
            handle_hold_on_hold_release = self.handle_hold_on_hold_release,
        }
        table.insert(self.item_group, item_tmp)
        -- this is for focus manager
        table.insert(self.layout, {item_tmp})
    end

    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()

    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
    end)
end

-- merge TitleBar layout into self FocusManager layout
function Menu:mergeTitleBarIntoLayout()
    if not self.title_bar then return end
    if Device:hasSymKey() or Device:hasScreenKB() then
        -- Title bar items can be accessed through key mappings on kindle
        return
    end
    -- On hasFewKeys devices, Menu uses the "Right" key to trigger the context menu: we can't use it to move focus in horizontal directions.
    -- So, add title bar buttons to FocusManager's layout in a vertical-only layout
    local title_bar_layout = self.title_bar:generateVerticalLayout()
    for i, row in ipairs(title_bar_layout) do
        -- Insert the title bar in the top rows of our layout
        table.insert(self.layout, i, row)
    end
    -- Adjust for the added rows to keep our current selection
    self.selected.y = self.selected.y + #title_bar_layout
    logger.dbg("Menu:mergeTitleBarIntoLayout: Adjusted focus position to account for added titlebar rows:", self.selected.x, ",", self.selected.y)
end

--[[
    the itemnumber parameter determines menu page number after switching item table
    1. itemnumber >= 0
        the page number is calculated with items per page
    2. itemnumber == nil
        the page number is 1
    3. itemnumber is negative number
        the page number is not changed, used when item_table is appended with
        new entries

    alternatively, itemmatch may be provided as a {key = value} table,
    and the page number will be the page containing the first item for
    which item.key = value
--]]
function Menu:switchItemTable(new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
    local no_recalculate_dimen = true

    if new_item_table then
        self.item_table = new_item_table
        no_recalculate_dimen = false
    end

    if self.title_bar then
        if new_title then
            self.title_bar:setTitle(new_title, true)
            if self.title_multilines then
                no_recalculate_dimen = false
            end
        end
        if new_subtitle then -- always single line
            self.title_bar:setSubTitle(new_subtitle, true)
        end
    end

    if type(itemmatch) == "table" then
        local key, value = next(itemmatch)
        for num, item in ipairs(self.item_table) do
            if item[key] == value then
                itemnumber = num
                break
            end
        end
    end

    if itemnumber == nil then
        self.page = 1
    elseif itemnumber >= 0 then
        itemnumber = math.min(itemnumber, #self.item_table)
        self.page = self:getPageNumber(itemnumber)
        -- Draw the focus in FileChooser when it has focused_path (i.e. itemmatch), except ".." item
        if self.path ~= nil and type(itemmatch) == "table" and not self.item_table[itemnumber].is_go_up then
            self.itemnumber = itemnumber
        end
    end

    self:updateItems(1, no_recalculate_dimen)
end

function Menu:getPageNumber(item_number)
    if #self.item_table == 0 or item_number == 0 then
        return 1
    end
    if self.items_max_lines then
        for page, items in ipairs(self.page_items) do
            if item_number <= items[#items] then
                return page
            end
        end
        return #self.page_items
    else
        return math.ceil(math.min(item_number, #self.item_table) / self.perpage)
    end
end

function Menu:setupItemHeights()
    if #self.item_table == 0 then
        self.page_items = {{}}
        return
    end

    local face = Font:getFace("smallinfofont", self.font_size)
    local line_height = TextBoxWidget:new{
        text = "A",
        face = face,
    }:getSize().h
    local infont_size = self.items_mandatory_font_size or (self.font_size - 4)
    local infont_face = Font:getFace("infont", infont_size)
    local infont_char_width = TextWidget:new{
        text = "0",
        face = infont_face,
        bold = true,
    }:getSize().w
    local available_width = self.inner_dimen.w
    if self.is_enable_shortcut then
        available_width = available_width - line_height - Size.span.horizontal_default
    end

    self.page_items = {} -- list of all 'items in the page' indexed by page
    local items = {} -- items in a page
    local items_height = 0 -- of all items in a page
    for i = 1, #self.item_table do
        local item = self.item_table[i]
        -- exact item height can be calculated by building the TextBoxWidget for item text,
        -- but it is slow, so estimate the number of lines by building the TextWidget
        -- empirical 8% is added to consider unjustified unhyphenated multilines text layout
        local item_text_width = TextWidget:new{
            text = item.text,
            face = face,
            bold = item.bold,
        }:getSize().w * 1.08
        local item_available_width = available_width - infont_char_width * (item.mandatory and #tostring(item.mandatory) or 0)
        local lines_nb = math.min(math.ceil(item_text_width / item_available_width), self.items_max_lines)
        item.height = lines_nb * line_height + 2 * Size.span.vertical_default + self.linesize
        item.shortcut_icon_width = line_height -- letter shortcuts of fixed size (1 line)

        -- put items in pages
        items_height = items_height + item.height
        if items_height <= self.available_height then
            table.insert(items, i)
        else -- start building next page
            table.insert(self.page_items, items)
            items = { i }
            items_height = item.height
        end
        if i == #self.item_table then -- last page
            table.insert(self.page_items, items)
        end
    end
end

function Menu:onScreenResize(dimen)
    self:init()
    return false
end

function Menu:onSetRotationMode(rotation)
    if self._recreate_func and rotation ~= nil and rotation ~= Screen:getRotationMode() then
        UIManager:close(self)
        -- Also re-layout ReaderView or FileManager itself
        if self._manager.ui.view then
            self._manager.ui.view:onSetRotationMode(rotation)
        else
            self._manager.ui:onSetRotationMode(rotation)
        end
        self._recreate_func()
        return true
    end
end

function Menu:onSelectByShortCut(_, keyevent)
    for k,v in ipairs(self.item_shortcuts) do
        if k > self.perpage then
            break
        elseif v == keyevent.key then
            if self.item_table[(self.page-1)*self.perpage + k] then
                self:onMenuSelect(self.item_table[(self.page-1)*self.perpage + k])
            end
            break
        end
    end
    return true
end

function Menu:goToMenuItemMatching(search_string, goto_letter)
    search_string = Utf8Proc.lowercase(util.fixUtf8(search_string, "?"))
    for i, item in ipairs(self.item_table) do
        if not item.is_go_up then
            local item_text = Utf8Proc.lowercase(util.fixUtf8(item.text, "?"))
            local idx = item_text:find(search_string)
            if idx and (idx == 1 or not goto_letter) then
                self.itemnumber = i -- draw focus
                self:onGotoPage(self:getPageNumber(i))
                break
            end
        end
    end
end

function Menu:onShowGotoDialog()
    if self.page_info_text and self.page_info_text.hold_input then
        self.page_info_text:onInput(self.page_info_text.hold_input)
    end
    return true
end

--[[
override this function to process the item selected in a different manner
]]--
function Menu:onMenuSelect(item)
    if item.sub_item_table == nil then
        if item.select_enabled == false then
            return true
        end
        if item.select_enabled_func then
            if not item.select_enabled_func() then
                return true
            end
        end
        self:onMenuChoice(item)
        if self.close_callback then
            self.close_callback()
        end
    else
        -- save menu title for later resume
        self.item_table.title = self.title
        table.insert(self.item_table_stack, self.item_table)
        self:switchItemTable(item.text, item.sub_item_table)
    end
    return true
end

--[[
    default to call item callback
    override this function to handle the choice
--]]
function Menu:onMenuChoice(item)
    if item.callback then
        item.callback()
    end
    return true
end

--[[
override this function to process the item hold in a different manner
]]--
function Menu:onMenuHold(item)
    return true
end

function Menu:onNextPage()
    local page = self.page < self.page_num and self.page + 1 or 1 -- cycle for swipes only
    return self:onGotoPage(page)
end

function Menu:onPrevPage()
    local page = self.page > 1 and self.page - 1 or self.page_num -- cycle for swipes only
    return self:onGotoPage(page)
end

function Menu:onFirstPage()
    return self:onGotoPage(1)
end

function Menu:onLastPage()
    return self:onGotoPage(self.page_num)
end

function Menu:onGotoPage(page)
    self.prev_itemnumber = nil
    self.page = page
    self:updateItems(1, true)
    return true
end

function Menu:onRight()
    return self:sendHoldEventToFocusedWidget()
end

function Menu:onShowingReader()
    -- Clear the dither flag to prevent it from infecting the queue and re-inserting a full-screen refresh...
    self.dithered = nil
end
Menu.onSetupShowReader = Menu.onShowingReader

function Menu:onCloseWidget()
    --- @fixme
    -- we cannot refresh regionally using the dimen field
    -- because some menus without menu title use VerticalGroup to include
    -- a text widget which is not calculated into the dimen.
    -- For example, it's a dirty hack to use two menus (one being this menu and
    -- the other touch menu) in the filemanager in order to capture tap gesture to popup
    -- the filemanager menu.
    -- NOTE: For the same reason, don't make it flash,
    --       because that'll trigger when we close the FM and open a book...

    -- Don't do anything if we're in the process of tearing down FM or RD, or if we don't actually have a live instance of 'em...
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    if (FileManager.instance and not FileManager.instance.tearing_down)
            or (ReaderUI.instance and not ReaderUI.instance.tearing_down) then
        UIManager:setDirty(nil, "ui")
    end
end

function Menu:onClose()
    if #self.item_table_stack == 0 then
        self:onCloseAllMenus()
    else
        -- back to parent menu
        local parent_item_table = table.remove(self.item_table_stack)
        self:switchItemTable(parent_item_table.title, parent_item_table)
    end
    return true
end

function Menu:onCloseAllMenus()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function Menu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:onCloseAllMenus()
        return true
    end
end

function Menu:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
    elseif direction == "south" then
        if not self.no_title then
            -- If there is a titlebar with a close button displayed (so, this Menu can be
            -- closed), allow easier closing with swipe south.
            self:onClose()
        end
        -- If there is no close button, it's a top level Menu and swipe
        -- up/down may hide/show top menu
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
    end
end

function Menu:onPan(arg, ges_ev)
    if ges_ev.mousewheel_direction then
        if ges_ev.direction == "north" then
            self:onNextPage()
        elseif ges_ev.direction == "south" then
            self:onPrevPage()
        end
    end
    return true
end

function Menu:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    if not self.no_title then
        -- If there is a titlebar with a close button displayed (so, this Menu can be
        -- closed), allow easier closing with swipe south.
        self:onClose()
    end
    return true
end

function Menu:setTitleBarLeftIcon(icon)
    self.title_bar:setLeftIcon(icon)
end

function Menu:onLeftButtonTap() -- to be overridden and implemented by the caller
end

function Menu:onLeftButtonHold() -- to be overridden and implemented by the caller
end

function Menu:getFirstVisibleItemIndex()
    return self.item_group[1] and self.item_group[1].idx or 1
end

function Menu.getItemFontSize(perpage)
    -- Get adjusted font size for the given nb of items per page:
    -- item font size between 14 and 24 for better matching
    return math.floor(24 - ((perpage - 6) * (1/18)) * 10)
end

function Menu.getItemMandatoryFontSize(perpage)
    -- Get adjusted font size for the given nb of items per page:
    -- "mandatory" font size between 12 and 18 for better matching
    return math.floor(18 - (perpage - 6) * (1/3))
end

--- Adds > to touch menu items with a submenu
local arrow_left  = "◂" -- U+25C2 BLACK LEFT-POINTING SMALL TRIANGLE
local arrow_right = "▸" -- U+25B8 BLACK RIGHT-POINTING SMALL TRIANGLE
local sub_item_format
-- Adjust arrow direction and position for menu with sub items
-- according to possible user choices
if BD.mirroredUILayout() then
    if BD.rtlUIText() then -- normal case with RTL language
        sub_item_format = "%s " .. BD.rtl(arrow_left)
    else -- user reverted text direction, so LTR
        sub_item_format = BD.ltr(arrow_left) .. " %s"
    end
else
    if BD.rtlUIText() then -- user reverted text direction, so RTL
        sub_item_format = BD.rtl(arrow_right) .. " %s"
    else -- normal case with LTR language
        sub_item_format = "%s " .. BD.ltr(arrow_right)
    end
end

function Menu.getMenuText(item)
    local text
    if item.text_func then
        text = item.text_func()
    else
        text = item.text
    end
    if item.sub_item_table ~= nil or item.sub_item_table_func then
        text = string.format(sub_item_format, text)
    end
    return text
end

function Menu.itemTableFromTouchMenu(t)
    local item_t = {}
    for k, v in ffiUtil.orderedPairs(t) do
        local item = { text = k }
        if v.callback then
            item.callback = v.callback
        else
            item.sub_item_table = v
        end
        table.insert(item_t, item)
    end
    return item_t
end

return Menu
