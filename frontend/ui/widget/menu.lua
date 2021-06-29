--[[--
Widget that displays a shortcut icon for menu item.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FFIUtil = require("ffi/util")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = FFIUtil.template

local ItemShortCutIcon = WidgetContainer:new{
    dimen = Geom:new{ w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
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
        dimen = self.dimen,
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
NOTICE:
@menu entry must be provided in order to close the menu
--]]
local MenuCloseButton = InputContainer:new{
    overlap_align = "right",
    padding_right = 0,
    menu = nil,
    dimen = nil,
}

function MenuCloseButton:init()
    local text_widget = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", 30), -- this font size align nicely with title
    }
    -- The text box height is greater than its width, and we want this × to be
    -- diagonally aligned with the top right corner (assuming padding_right=0,
    -- or padding_right = padding_top so the diagonal aligment is preserved).
    local text_size = text_widget:getSize()
    local text_width_pad = math.floor((text_size.h - text_size.w) / 2)

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padding_top = self.padding_top,
        padding_bottom = self.padding_bottom,
        padding_left = self.padding_left,
        padding_right = self.padding_right + text_width_pad,
        text_widget,
    }

    self.dimen = Geom:new{
        w = text_size.w + text_width_pad + self.padding_right,
        h = text_size.h,
    }
    self.ges_events.Close = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        },
        doc = "Close menu",
    }
end

function MenuCloseButton:onClose()
    self.menu:onClose()
    return true
end

--[[
Widget that displays an item for menu
--]]
local MenuItem = InputContainer:new{
    text = nil,
    bidi_wrap_func = nil,
    show_parent = nil,
    detail = nil,
    font = "cfont",
    font_size = 24,
    infont = "infont",
    infont_size = 18,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    _underline_container = nil,
    linesize = Size.line.medium,
    single_line = false,
    multilines_show_more_text = false,
    -- Align text & mandatory baselines (only when single_line=true)
    align_baselines = false,
    -- Show a line of dots (also called tab or dot leaders) between text and mandatory
    with_dots = false,
}

function MenuItem:init()
    self.content_width = self.dimen.w - 2 * Size.padding.fullscreen
    local shortcut_icon_dimen = Geom:new()
    if self.shortcut then
        shortcut_icon_dimen.w = math.floor(self.dimen.h * 4/5)
        shortcut_icon_dimen.h = shortcut_icon_dimen.w
        self.content_width = self.content_width - shortcut_icon_dimen.w - Size.span.horizontal_default
    end

    self.detail = self.text

    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Menu Item",
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Menu Item",
            },
        }
    end

    local max_item_height = self.dimen.h - 2 * self.linesize

    -- We want to show at least one line, so cap the provided font sizes
    local max_font_size = TextBoxWidget:getFontSizeToFitHeight(max_item_height, 1)
    if self.font_size > max_font_size then
        self.font_size = max_font_size
    end
    if self.infont_size > max_font_size then
        self.infont_size = max_font_size
    end
    if not self.single_line and not self.multilines_show_more_text then
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
    local state_button_width = self.state_size.w or 0
    local state_button = self.state or HorizontalSpan:new{
        width = state_button_width,
    }
    local state_indent = self.state and self.state.indent or ""
    local state_container = LeftContainer:new{
        dimen = Geom:new{w = math.floor(self.content_width / 2), h = self.dimen.h},
        HorizontalGroup:new{
            TextWidget:new{
                text = state_indent,
                face = Font:getFace(self.font, self.font_size),
            },
            state_button,
        }
    }

    -- Font for main text (may have its size decreased to make text fit)
    self.face = Font:getFace(self.font, self.font_size)
    -- Font for "mandatory" on the right
    self.info_face = Font:getFace(self.infont, self.infont_size)

    -- "mandatory" is the text on the right: file size, page number...
    -- Padding before mandatory
    local text_mandatory_padding = 0
    local text_ellipsis_mandatory_padding = 0
    local mandatory = self.mandatory_func and self.mandatory_func() or self.mandatory
    if mandatory then
        text_mandatory_padding = Size.span.horizontal_default
        -- Smaller padding when ellipsis for better visual feeling
        text_ellipsis_mandatory_padding = Size.span.horizontal_small
    end
    mandatory = mandatory and ""..mandatory or ""
    local mandatory_widget = TextWidget:new{
        text = mandatory,
        face = self.info_face,
        bold = self.bold,
        fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
    }
    local mandatory_w = mandatory_widget:getWidth()

    local available_width = self.content_width - state_button_width - text_mandatory_padding - mandatory_w
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

    local dots_widget
    local dots_left_padding = Size.padding.small
    local dots_right_padding = Size.padding.small
    if self.single_line then  -- items only in single line
        -- No font size change: text will be truncated if it overflows
        item_name = TextWidget:new{
            text = text,
            face = self.face,
            bold = self.bold,
            fgcolor = self.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        }
        local w = item_name:getWidth()
        if w > available_width then
            -- We give it a little more room if truncated for better visual
            -- feeling (which might make it no more truncated, but well...)
            local text_max_width_if_ellipsis = available_width + text_mandatory_padding - text_ellipsis_mandatory_padding
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
        end

    elseif self.multilines_show_more_text then
        -- Multi-lines, with font size decrease if needed to show more of the text.
        -- It would be costly/slow with use_xtext if we were to try all
        -- font sizes from self.font_size to min_font_size (12).
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
        local min_font_size = 12
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
            height = max_item_height,
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
                width = self.state_size.w,
            },
            item_name,
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
        table.insert(hgroup, ItemShortCutIcon:new{
            dimen = shortcut_icon_dimen,
            key = self.shortcut,
            style = self.shortcut_style,
        })
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

function MenuItem:onFocus(initial_focus)
    if Device:isTouchDevice() then
        -- Devices which are Keys capable will get this onFocus called by
        -- updateItems(), which will toggle the underline color of first item.
        -- If the device is also Touch capable, let's not show the initial
        -- underline for a prettier display (it will be shown only when keys
        -- are used).
        if not initial_focus or self.menu.did_focus_with_keys then
            self._underline_container.color = Blitbuffer.COLOR_BLACK
            self.menu.did_focus_with_keys = true
        end
    else
        self._underline_container.color = Blitbuffer.COLOR_BLACK
    end
    return true
end

function MenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    return true
end

function MenuItem:onShowItemDetail()
    UIManager:show(InfoMessage:new{ text = self.detail, })
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
        logger.dbg("creating coroutine for menu select")
        local co = coroutine.create(function()
            self.menu:onMenuSelect(self.table, pos)
        end)
        coroutine.resume(co)
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
        logger.dbg("creating coroutine for menu select")
        local co = coroutine.create(function()
            self.menu:onMenuSelect(self.table, pos)
        end)
        coroutine.resume(co)

        UIManager:forceRePaint()
    end
    return true
end

function MenuItem:onHoldSelect(arg, ges)
    if not self[1].dimen then return end

    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.table, pos)
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
        self.menu:onMenuHold(self.table, pos)

        UIManager:forceRePaint()
    end
    return true
end

--[[
Widget that displays menu
--]]
local Menu = FocusManager:new{
    show_parent = nil,

    title = "No Title",
    -- default width and height
    width = nil,
    -- height will be calculated according to item number if not given
    height = nil,
    header_padding = Size.padding.large,
    dimen = nil,
    item_table = nil, -- NOT mandatory (will be empty)
    item_shortcuts = {
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
        "Z", "X", "C", "V", "B", "N", "M", ".", "Sym",
    },
    item_table_stack = nil,
    is_enable_shortcut = true,

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

    -- set this to true to not paint as popup menu
    is_borderless = false,
    -- if you want to embed the menu widget into another widget, set
    -- this to false
    is_popout = true,
    -- set this to true to add close button
    has_close_button = true,
    -- close_callback is a function, which is executed when menu is closed
    -- it is usually set by the widget which creates the menu
    close_callback = nil,
    linesize = Size.line.medium,
    line_color = Blitbuffer.COLOR_DARK_GRAY,
}

function Menu:_recalculateDimen()
    self.perpage = self.items_per_page or G_reader_settings:readSetting("items_per_page") or self.items_per_page_default
    self.span_width = 0
    local height_dim
    local bottom_height = 0
    local top_height = 0
    if self.page_return_arrow and self.page_info_text then
        bottom_height = math.max(self.page_return_arrow:getSize().h, self.page_info_text:getSize().h)
            + 2 * Size.padding.button
    end
    if self.menu_title and not self.no_title then
        top_height = self.menu_title_group:getSize().h + self.header_padding
    end
    height_dim = self.inner_dimen.h - bottom_height - top_height
    local item_height = math.floor(height_dim / self.perpage)
    self.span_width = math.floor((height_dim - (self.perpage * item_height)) / 2 - 1)
    self.item_dimen = Geom:new{
        w = self.inner_dimen.w,
        h = item_height,
    }
    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end
end

function Menu:init()
    self.show_parent = self.show_parent or self
    self.item_table = self.item_table or {}
    self.item_table_stack = {}
    self.dimen = Geom:new{ w = self.width, h = self.height or Screen:getHeight() }
    if self.dimen.h > Screen:getHeight() or self.dimen.h == nil then
        self.dimen.h = Screen:getHeight()
    end

    self.border_size = self.is_borderless and 0 or Size.border.window
    self.inner_dimen = Geom:new{
        w = self.dimen.w - 2 * self.border_size,
        h = self.dimen.h - 2 * self.border_size,
    }

    self.page = 1

    self.paths = {}  -- per instance table to trace navigation path

    -----------------------------------
    -- start to set up widget layout --
    -----------------------------------
    self.menu_title = TextWidget:new{
        overlap_align = "center",
        text = self.title,
        face = Font:getFace("tfont"),
    }
    local menu_title_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.inner_dimen.w,
            h = self.menu_title:getSize().h,
        },
        self.menu_title,
    }
    local path_text_container

    if self.show_path then
        self.path_text = TextWidget:new{
            face = Font:getFace("xx_smallinfofont"),
            text = BD.directory(self.path),
            max_width = self.inner_dimen.w - 2*Size.padding.small,
            truncate_left = true,
        }
        path_text_container = CenterContainer:new{
            dimen = Geom:new{
                w = self.inner_dimen.w,
                h = self.path_text:getSize().h,
            },
            self.path_text,
        }
        self.menu_title_group = VerticalGroup:new{
            align = "center",
            menu_title_container,
            path_text_container,
        }
    else
        self.menu_title_group = VerticalGroup:new{
            align = "center",
            menu_title_container
        }
    end
    -- group for title bar
    self.title_bar = OverlapGroup:new{
        dimen = {w = self.inner_dimen.w, h = self.menu_title_group:getSize().h},
        self.menu_title_group,
    }
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

    local title_goto, type_goto, hint_func
    local buttons = {
        {
            {
                text = _("Cancel"),
                callback = function()
                    self.page_info_text:closeInputDialog()
                end,
            },
            {
                text = _("Go to page"),
                is_enter_default = true,
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

    if self.goto_letter then
        title_goto = _("Enter page number or letter")
        type_goto = "string"
        hint_func = function()
            -- @translators First group is a page number range, second group the standard range for alphabetic searches
            return T(_("(1 - %1) or (a - z)"), self.page_num)
        end
        table.insert(buttons[1], {
            text = _("Go to letter"),
            is_enter_default = true,
            callback = function()
                for k, v in ipairs(self.item_table) do
                    --- @todo Support utf8 lowercase.
                    local filename = FFIUtil.basename(v.path):lower()
                    local search_string = self.page_info_text.input_dialog:getInputText():lower()
                    if search_string == "" then return end
                    local i, _ = filename:find(search_string)
                    if i == 1 and not v.is_go_up then
                        self:onGotoPage(math.ceil(k / self.perpage))
                        break
                    end
                end
                self.page_info_text:closeInputDialog()
            end,
        })
    else
        title_goto = _("Enter page number")
        type_goto = "number"
        hint_func = function()
            return string.format("(1 - %s)", self.page_num)
        end
    end

    self.page_info_text = self.page_info_text or Button:new{
        text = "",
        hold_input = {
            title = title_goto,
            type = type_goto,
            hint_func = hint_func,
            buttons = buttons,
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = false,
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

    local header = VerticalGroup:new{
        VerticalSpan:new{width = self.header_padding},
        self.title_bar,
    }
    local body = self.item_group
    local footer = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        self.page_info,
    }
    local page_return = BottomContainer:new{
        dimen = self.inner_dimen:copy(),
        WidgetContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = self.page_return_arrow:getSize().h,
            },
            self.return_button,
        }
    }

    self:_recalculateDimen()
    self.vertical_span = HorizontalGroup:new{
        VerticalSpan:new{ width = self.span_width }
    }
    if self.no_title then
        self.content_group = VerticalGroup:new{
            align = "left",
            self.vertical_span,
            body,
        }
    else
        self.content_group = VerticalGroup:new{
            align = "left",
            header,
            self.vertical_span,
            body,
        }
    end
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
        radius = self.is_popout and math.floor(self.dimen.w / 20) or 0,
        content
    }

    ------------------------------------------
    -- start to set up input event callback --
    ------------------------------------------
    if Device:isTouchDevice() then
        if self.has_close_button then
            table.insert(self.title_bar, MenuCloseButton:new{
                menu = self,
                padding_right = self.header_padding,
            })
        end
        -- watch for outer region if it's a self contained widget
        if self.is_popout then
            self.ges_events.TapCloseAllMenus = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
        -- delegate swipe gesture to GestureManager in filemanager
        if self.is_file_manager ~= true then
            self.ges_events.Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = self.dimen,
                }
            }
        end
        self.ges_events.Close = self.on_close_ges
    end

    if not Device:hasKeyboard() then
        -- remove menu item shortcut for K4
        self.is_enable_shortcut = false
    end

    if Device:hasKeys() then
        -- set up keyboard events
        self.key_events.Close = { {"Back"}, doc = "close menu" }
        if Device:hasFewKeys() then
            self.key_events.Close = { {"Left"}, doc = "close menu" }
        end
        self.key_events.NextPage = {
            {Input.group.PgFwd}, doc = "goto next page of the menu"
        }
        self.key_events.PrevPage = {
            {Input.group.PgBack}, doc = "goto previous page of the menu"
        }
    end

    if Device:hasDPad() then
        -- we won't catch presses to "Right", leave that to MenuItem.
        self.key_events.FocusRight = nil
        -- shortcut icon is not needed for touch device
        if self.is_enable_shortcut then
            self.key_events.SelectByShortCut = { {self.item_shortcuts} }
        end
        self.key_events.Select = {
            {"Press"}, doc = "select current menu item"
        }
        self.key_events.Right = {
            {"Right"}, doc = "hold  menu item"
        }
    end

    if #self.item_table > 0 then
        -- if the table is not yet initialized, this call
        -- must be done manually:
        self.page = math.ceil((self.item_table.current or 1) / self.perpage)
    end
    if self.path_items then
        self:refreshPath()
    else
        self:updateItems()
    end
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
    local reader_ui = ReaderUI:_getRunningInstance()
    if (FileManager.instance and not FileManager.instance.tearing_down) or (reader_ui and not reader_ui.tearing_down) then
        UIManager:setDirty(nil, "ui")
    end
end

function Menu:updatePageInfo(select_number)
    if self.item_group[1] then
        if Device:hasDPad() then
            -- reset focus manager accordingly
            self.selected = { x = 1, y = select_number }
        end
        -- update page information
        self.page_info_text:setText(FFIUtil.template(_("Page %1 of %2"), self.page, self.page_num))
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

function Menu:updateItems(select_number)
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.vertical_span:clear()
    self.content_group:resetLayout()
    self:_recalculateDimen()

    -- default to select the first item
    if not select_number then
        select_number = 1
    end

    local font_size = self.items_font_size or G_reader_settings:readSetting("items_font_size")
                                     or Menu.getItemFontSize(self.perpage)
    local infont_size = self.items_mandatory_font_size or (font_size - 4)
    local multilines_show_more_text = self.multilines_show_more_text
    if multilines_show_more_text == nil then
        multilines_show_more_text = G_reader_settings:isTrue("items_multilines_show_more_text")
    end

    for c = 1, math.min(self.perpage, #self.item_table) do
        -- calculate index in item_table
        local i = (self.page - 1) * self.perpage + c
        if i <= #self.item_table then
            local item_shortcut = nil
            local shortcut_style = "square"
            if self.is_enable_shortcut then
                -- give different shortcut_style to keys in different
                -- lines of keyboard
                if c >= 11 and c <= 20 then
                    --shortcut_style = "rounded_corner"
                    shortcut_style = "grey_square"
                end
                item_shortcut = self.item_shortcuts[c]
            end
            local item_tmp = MenuItem:new{
                show_parent = self.show_parent,
                state = self.item_table[i].state,
                state_size = self.state_size or {},
                text = Menu.getMenuText(self.item_table[i]),
                bidi_wrap_func = self.item_table[i].bidi_wrap_func,
                mandatory = self.item_table[i].mandatory,
                mandatory_func = self.item_table[i].mandatory_func,
                bold = self.item_table.current == i or self.item_table[i].bold == true,
                dim = self.item_table[i].dim,
                font = "smallinfofont",
                font_size = font_size,
                infont = "infont",
                infont_size = infont_size,
                dimen = self.item_dimen:new(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                table = self.item_table[i],
                menu = self,
                linesize = self.linesize,
                single_line = self.single_line,
                multilines_show_more_text = multilines_show_more_text,
                align_baselines = self.align_baselines,
                with_dots = self.with_dots,
                line_color = self.line_color,
                items_padding = self.items_padding,
            }
            table.insert(self.item_group, item_tmp)
            -- this is for focus manager
            table.insert(self.layout, {item_tmp})
        end -- if i <= self.items
    end -- for c=1, self.perpage

    self:updatePageInfo(select_number)
    if self.show_path then
        self.path_text:setText(BD.directory(self.path))
    end

    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
    end)
end

--[[
    the itemnumber paramter determines menu page number after switching item table
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
function Menu:switchItemTable(new_title, new_item_table, itemnumber, itemmatch)
    if self.menu_title and new_title then
        self.menu_title:setText(new_title)
    end

    if itemnumber == nil then
        self.page = 1
    elseif itemnumber >= 0 then
        self.page = math.ceil(itemnumber / self.perpage)
    end

    if type(itemmatch) == "table" then
        local key, value = next(itemmatch)
        for num, item in ipairs(new_item_table) do
            if item[key] == value then
                self.page = math.floor((num-1) / self.perpage) + 1
                break
            end
        end
    end

    -- make sure current page is in right page range
    local max_pages = math.ceil(#new_item_table / self.perpage)
    if self.page > max_pages then
        self.page = max_pages
    end

    self.item_table = new_item_table
    self:updateItems()
end

function Menu:onScreenResize(dimen)
    --- @todo Investigate: could this cause minor memory leaks?
    self:init()
    return false
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

function Menu:onShowGotoDialog()
    if self.page_info_text and self.page_info_text.hold_input then
        self.page_info_text:onInput(self.page_info_text.hold_input)
    end
    return true
end

function Menu:onWrapFirst()
    if self.page > 1 then
        self.page = self.page - 1
        local end_position = self.perpage
        if self.page == self.page_num then
            end_position = #self.item_table % self.perpage
        end
        self:updateItems(end_position)
    end
    return false
end

function Menu:onWrapLast()
    if self.page < self.page_num then
        self:onNextPage()
    end
    return false
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
    if self.onNext and self.page == self.page_num - 1 then
        self:onNext()
    end
    if self.page < self.page_num then
        self.page = self.page + 1
        self:updateItems()
    elseif self.page == self.page_num then
        -- on the last page, we check if we're on the last item
        local end_position = #self.item_table % self.perpage
        if end_position == 0 then
            end_position = self.perpage
        end
        if end_position ~= self.selected.y then
            self:updateItems(end_position)
        end
        self.page = 1
        self:updateItems()
    end
    return true
end

function Menu:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
    elseif self.page == 1 then
        self.page = self.page_num
    end
    self:updateItems()
    return true
end

function Menu:onFirstPage()
    self.page = 1
    self:updateItems()
    return true
end

function Menu:onLastPage()
    self.page = self.page_num
    self:updateItems()
    return true
end

function Menu:onGotoPage(page)
    self.page = page
    self:updateItems()
    return true
end

function Menu:onSelect()
    local item = self.item_table[(self.page-1)*self.perpage+self.selected.y]
    if item then
        self:onMenuSelect(item)
    end
    return true
end

function Menu:onRight()
    local item = self.item_table[(self.page-1)*self.perpage+self.selected.y]
    if item then
        self:onMenuHold(item)
    end
    return true
end

function Menu:onClose()
    local table_length = #self.item_table_stack
    if table_length == 0 then
        self:onCloseAllMenus()
    else
        -- back to parent menu
        local parent_item_table = table.remove(self.item_table_stack, table_length)
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
        if self.has_close_button and not self.no_title then
            -- If there is a close button displayed (so, this Menu can be
            -- closed), allow easier closing with swipe up/down
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

function Menu.getItemFontSize(perpage)
    -- Get adjusted font size for the given nb of items per page:
    -- item font size between 14 and 24 for better matching
    return math.floor(24 - ((perpage - 6) / 18) * 10)
end

function Menu.getItemMandatoryFontSize(perpage)
    -- Get adjusted font size for the given nb of items per page:
    -- "mandatory" font size between 12 and 18 for better matching
    return math.floor(18 - (perpage - 6) / 3)
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
    for k, v in FFIUtil.orderedPairs(t) do
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
