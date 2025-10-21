--[[--
TouchMenu widget for hierarchical menus.
]]
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RadioMark = require("ui/widget/radiomark")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local Utf8Proc = require("ffi/utf8proc")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local getMenuText = require("ui/widget/menu").getMenuText
local _ = require("gettext")
local ffiUtil = require("ffi/util")
local util = require("util")
local T = ffiUtil.template
local Input = Device.input
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

--[[
TouchMenuItem widget
--]]
local TouchMenuItem = InputContainer:extend{
    menu = nil,
    vertical_align = "center",
    item = nil,
    dimen = nil,
    face = Font:getFace("smallinfofont"),
    show_parent = nil,
    check_callback_updates_menu = nil, -- set to true for item with checkmark if its callback updates menu
    check_callback_closes_menu = nil, -- set to true for item with checkmark if its callback closes menu
}

function TouchMenuItem:init()
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }

    local item_enabled = self.item.enabled
    if self.item.enabled_func then
        item_enabled = self.item.enabled_func()
    end
    local item_checkable = false
    local item_checked = self.item.checked
    if self.item.checked_func then
        item_checkable = true
        item_checked = self.item.checked_func()
    end
    local checkmark_widget
    if self.item.radio then
        checkmark_widget = RadioMark:new{
            checkable = item_checkable,
            checked = item_checked,
            enabled = item_enabled,
        }
    else
        checkmark_widget = CheckMark:new{
            checkable = item_checkable,
            checked = item_checked,
            enabled = item_enabled,
        }
    end

    local checked_widget = CheckMark:new{ -- for layout, to :getSize()
        checked = true,
    }

    self.checkmark_tap_width = checked_widget:getSize().w + 2*Size.padding.default

    -- text_max_width should be the TouchMenuItem width minus the below
    -- FrameContainer default paddings minus the checked widget width
    local text_max_width = self.dimen.w - 2*Size.padding.default - checked_widget:getSize().w
    local text = getMenuText(self.item)
    local face = self.face
    local forced_baseline, forced_height
    if self.item.font_func then
        -- A font_func() may be provided by ReaderFont to have each font name
        -- displayed in its own font: we must tell TextWidget to use the default
        -- font baseline and height for items to be correctly aligned without
        -- variations due to each font different metrics.
        face = self.item.font_func(self.face.orig_size)
        if face then
            local w = TextWidget:new{ text = "", face = self.face }
            forced_baseline = w:getBaseline()
            forced_height = w:getSize().h
            w:free()
        else
            face = self.face
        end
    end
    local text_widget = TextWidget:new{
        text = text,
        max_width = text_max_width,
        fgcolor = item_enabled ~= false and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        face = face,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }
    self.text_truncated = text_widget:isTruncated()
    self.item_frame = FrameContainer:new{
        width = self.dimen.w,
        bordersize = 0,
        color = Blitbuffer.COLOR_BLACK,
        HorizontalGroup:new {
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = checked_widget:getSize().w },
                checkmark_widget,
            },
            text_widget,
        },
    }

    self._underline_container = UnderlineContainer:new{
        vertical_align = "center",
        dimen = self.dimen:copy(),
        line_width = self.item_frame:getSize().w, -- we'll draw a shorter line
        self.item_frame,
    }

    self[1] = self._underline_container
    function self:isEnabled()
        return item_enabled ~= false and true
    end
end

function TouchMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function TouchMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    return true
end

function TouchMenuItem:onTapSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then return true end -- don't propagate

    local tap_on_checkmark = false
    if ges and ges.pos and ges.pos.x then
        local tap_x = BD.mirroredUILayout() and self.dimen.w - ges.pos.x - 1
                                             or ges.pos.x
        if tap_x <= self.checkmark_tap_width then
            tap_on_checkmark = true
        end
    end

    -- If the menu hasn't actually been drawn yet, don't do anything (as it's confusing, and the coordinates may be wrong).
    if not self.item_frame.dimen then return true end

    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuSelect(self.item, tap_on_checkmark)
    else
        -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        -- The item frame's width stops at the text width, but we want it to match the menu's length instead
        local highlight_dimen = self.item_frame.dimen
        highlight_dimen.w = self.item_frame.width

        -- Highlight
        --
        self.item_frame.invert = true
        UIManager:widgetInvert(self.item_frame, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
        UIManager:setDirty(nil, "fast", highlight_dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self.item_frame.invert = false
        if self.item.keep_menu_open or self.item.check_callback_updates_menu then
            UIManager:widgetInvert(self.item_frame, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "ui", highlight_dimen)
        end

        -- Callback
        --
        self.menu:onMenuSelect(self.item, tap_on_checkmark)

        UIManager:forceRePaint()
    end
    return true
end

function TouchMenuItem:onHoldSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then
        -- Allow help_text to be displayed even if menu item disabled
        local help_text = self.item.help_text_func and self.item.help_text_func(self) or self.item.help_text
        if help_text then
            UIManager:show(InfoMessage:new{ text = help_text, })
        end
        return true -- don't propagate
    end

    if not self.item_frame.dimen then return true end

    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.item, self.text_truncated)
    else
        -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

        -- The item frame's width stops at the text width, but we want it to match the menu's length instead
        local highlight_dimen = self.item_frame.dimen
        highlight_dimen.w = self.item_frame.width

        -- Highlight
        --
        self.item_frame.invert = true
        UIManager:widgetInvert(self.item_frame, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
        UIManager:setDirty(nil, "fast", highlight_dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self.item_frame.invert = false
        -- NOTE: If the menu is going to be closed, we can safely drop that.
        --       (This field defaults to nil, meaning keep the menu open, hence the negated test)
        if self.item.hold_keep_menu_open ~= false then
            UIManager:widgetInvert(self.item_frame, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "ui", highlight_dimen)
        end

        -- Callback
        --
        self.menu:onMenuHold(self.item, self.text_truncated)

        UIManager:forceRePaint()
    end
    return true
end

--[[
TouchMenuBar widget
--]]
local TouchMenuBar = InputContainer:extend{
    width = Screen:getWidth(),
    icons = nil, -- array, mandatory
    -- touch menu that holds the bar, used for trigger repaint on icons
    show_parent = nil,
    menu = nil,
}

function TouchMenuBar:init()
    local icon_sep_width = Size.span.vertical_default
    local icons_sep_width = icon_sep_width * (#self.icons + 1)
    -- we assume all icons are of the same width
    local icon_width = Screen:scaleBySize(DGENERIC_ICON_SIZE)
    local icon_height = icon_width
    -- content_width is the width of all the icon images
    local content_width = icon_width * #self.icons + icons_sep_width
    local spacing_width = (self.width - content_width)/(#self.icons*2)
    local icon_padding = math.min(spacing_width, Screen:scaleBySize(16))
    self.height = icon_height + 2*Size.padding.default
    self.show_parent = self.show_parent or self
    self.bar_icon_group = HorizontalGroup:new{}
    -- build up image widget for menu icon bar
    self.icon_widgets = {}
    -- hold icon separators
    self.icon_seps = {}
    -- the start_seg for first icon_widget should be 0
    -- we assign negative here to offset it in the loop
    local start_seg = -icon_sep_width
    local end_seg = start_seg
    -- self.width is the screen width
    -- content_width is the width of all the icon images
    -- (2 * icon_padding * #self.icons) is the combined width of icons paddings
    local stretch_width = self.width - content_width - (2 * icon_padding * #self.icons) + icon_sep_width

    for k, v in ipairs(self.icons) do
        local ib = IconButton:new{
            show_parent = self.show_parent,
            icon = v,
            width = icon_width,
            height = icon_height,
            callback = nil,
            padding_left = icon_padding,
            padding_right = icon_padding,
            menu = self.menu,
        }

        table.insert(self.icon_widgets, ib)
        table.insert(self.menu.layout, ib) -- for the focusmanager

        -- we have to use local variable here for closure callback
        local _start_seg = end_seg + icon_sep_width
        local _end_seg = _start_seg + self.icon_widgets[k]:getSize().w
        end_seg = _end_seg -- for next loop _start_seg

        if BD.mirroredUILayout() then
            _start_seg, _end_seg = self.width - _end_seg, self.width - _start_seg
        end

        if k == 1 then
            self.bar_sep = LineWidget:new{
                dimen = Geom:new{
                    w = self.width,
                    h = Size.line.thick,
                },
                empty_segments = {
                    {
                        s = _start_seg, e = _end_seg
                    }
                },
            }
        end

        local icon_sep = LineWidget:new{
            style = k == 1 and "solid" or "none",
            dimen = Geom:new{
                w = icon_sep_width,
                h = self.height,
            }
        }
        -- no separator on the right
        if k < #self.icons then
            table.insert(self.icon_seps, icon_sep)
        end

        -- callback to set visual style
        ib.callback = function()
            self.bar_sep.empty_segments = {
                {
                    s = _start_seg, e = _end_seg
                }
            }
            for i, sep in ipairs(self.icon_seps) do
                local current_icon, last_icon
                if k == #self.icons then
                    current_icon = false
                    last_icon = i == k
                else
                    current_icon = i == k - 1 or i == k
                    last_icon = false
                end

                -- if the active icon is the last icon then the empty bar segment has
                -- to move over to the right by the width of a separator and the stretch width
                if last_icon then
                    local _start_last_seg = icon_sep_width + stretch_width + _start_seg
                    local _end_last_seg = icon_sep_width + stretch_width + _end_seg
                    if BD.mirroredUILayout() then
                        _start_last_seg = _start_seg - icon_sep_width - stretch_width
                        _end_last_seg = _end_seg - icon_sep_width - stretch_width
                    end
                    self.bar_sep.empty_segments = {
                        {
                            s = _start_last_seg, e = _end_last_seg
                        }
                    }
                    sep.style = "solid"
                -- regular behavior
                else
                    sep.style = current_icon and "solid" or "none"
                end
            end
            self.menu:switchMenuTab(k)
        end

        table.insert(self.bar_icon_group, self.icon_widgets[k])
        table.insert(self.bar_icon_group, icon_sep)

        -- if we're at the before-last icon, add an extra span and the final separator
        if k == #self.icons - 1 then
            table.insert(self.bar_icon_group, HorizontalSpan:new{
                width = stretch_width
            })
            -- need to create a new LineWidget otherwise it's just a reference to the same instance
            local icon_sep_duplicate = LineWidget:new{
                style = "none",
                dimen = Geom:new{
                    w = icon_sep_width,
                    h = self.height,
                }
            }
            table.insert(self.icon_seps, icon_sep_duplicate)
            table.insert(self.bar_icon_group, icon_sep_duplicate)
        end
    end

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        VerticalGroup:new{
            align = "left",
            -- bar icons
            self.bar_icon_group,
            -- horizontal separate line
            self.bar_sep
        },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function TouchMenuBar:switchToTab(index)
    -- a little safety check
    -- don't auto-activate a non-existent index
    if index > #self.icon_widgets then
        index = #self.icon_widgets
    end
    if self.menu.tab_item_table[index] and self.menu.tab_item_table[index].remember == false then
        -- Don't auto-activate those that should not be
        -- remembered (FM plus menu on non-touch devices)
        index = 1
    end
    self.icon_widgets[index].callback()
end

--[[
TouchMenu widget for hierarchical menus
--]]
local TouchMenu = FocusManager:extend{
    tab_item_table = nil, -- mandatory
    -- for returning in multi-level menus
    item_table_stack = nil,
    parent_id = nil,
    item_table = nil,
    item_height = Size.item.height_large,
    bordersize = Size.border.window,
    padding = Size.padding.default, -- (not used at top)
    fface = Font:getFace("ffont"),
    width = nil,
    height = nil,
    max_per_page_default = 10,
    -- for UIManager:setDirty
    show_parent = nil,
    cur_tab = -1,
    close_callback = nil,
    is_fresh = true,
}

function TouchMenu:init()
    self.screen_size = Screen:getSize()
    -- We won't include self.bordersize in our width calculations, so that
    -- borders are pushed off-(screen-)width and so not visible.
    -- We'll then be similar to bottom menu ConfigDialog (where this
    -- nice effect is caused by some width calculations bug).
    if not self.dimen then self.dimen = Geom:new() end
    self.show_parent = self.show_parent or self
    if not self.close_callback then
        self.close_callback = function()
            UIManager:close(self.show_parent)
        end
    end

    self.layout = {}

    self.ges_events.TapCloseAllMenus = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0, y = 0,
                w = self.screen_size.w,
                h = self.screen_size.h,
            }
        }
    }
    self.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = self.dimen,
        }
    }

    self.key_events.Back = { { Input.group.Back } }
    self.key_events.Close = { { "Menu" } }
    if Device:hasFewKeys() then
        self.key_events.Back = { { "Left" } }
    end
    self.key_events.NextPage = { { Input.group.PgFwd } }
    self.key_events.PrevPage = { { Input.group.PgBack } }

    local icons = {}
    for _, v in ipairs(self.tab_item_table) do
        table.insert(icons, v.icon)
    end
    self.bar = TouchMenuBar:new{
        width = self.width, -- will impose width and push left and right borders offscreen
        icons = icons,
        show_parent = self.show_parent,
        menu = self,
    }

    self.item_group = VerticalGroup:new{
        align = "center",
    }
    -- group for page info
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
    end
    self.page_info_left_chev = Button:new{
        icon = chevron_left,
        callback = function() self:onPrevPage() end,
        hold_callback = function() self:onFirstPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_right_chev = Button:new{
        icon = chevron_right,
        callback = function() self:onNextPage() end,
        hold_callback = function() self:onLastPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_text = TextWidget:new{
        text = "",
        face = self.fface,
    }
    self.page_info = HorizontalGroup:new{
        self.page_info_left_chev,
        self.page_info_text,
        self.page_info_right_chev
    }
    -- group for device info
    self.time_info = Button:new{
        text = "",
        face = self.fface,
        text_font_bold = false,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = datetime.secondsToDateTime(nil, nil, true),
            })
        end,
        hold_callback = function()
            UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
        end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.device_info = HorizontalGroup:new{
        self.time_info,
        -- Add some span to balance up_button image included padding
        HorizontalSpan:new{width = Size.span.horizontal_default},
    }
    local footer_width = self.width - self.padding*2
    local up_button = IconButton:new{
        icon = "chevron.up",
        show_parent = self.show_parent,
        padding_left = math.floor(footer_width*0.33*0.1),
        padding_right = math.floor(footer_width*0.33*0.1),
        callback = function()
            self:backToUpperMenu()
        end,
    }
    local footer_height = up_button:getSize().h + Size.line.thick
    self.footer = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = math.floor(footer_width*0.33), h = footer_height},
            up_button,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = math.floor(footer_width*0.33), h = footer_height},
            self.page_info,
        },
        RightContainer:new{
            dimen = Geom:new{ w = math.floor(footer_width*0.33), h = footer_height},
            self.device_info,
        }
    }

    self.menu_frame = FrameContainer:new{
        padding = self.padding,
        padding_top = 0, -- ensured by TouchMenuBar
        bordersize = self.bordersize,
        background = Blitbuffer.COLOR_WHITE,
        -- menubar and footer will be inserted in
        -- item_group in updateItems
        self.item_group,
    }
    -- This CenterContainer will make the left and right borders drawn
    -- off-screen
    self[1] = CenterContainer:new{
        dimen = self.screen_size,
        ignore = "height",
        self.menu_frame
    }

    self.item_width = self.width - self.padding*2
    self.split_line = HorizontalGroup:new{
        -- pad with 10 pixel to align with the up arrow in footer
        HorizontalSpan:new{width = Size.span.horizontal_default},
        LineWidget:new{
            background = Blitbuffer.COLOR_GRAY,
            dimen = Geom:new{
                w = self.item_width - 2*Size.span.horizontal_default,
                h = Size.line.medium,
            }
        },
        HorizontalSpan:new{width = Size.span.horizontal_default},
    }
    self.footer_top_margin = VerticalSpan:new{width = Size.span.vertical_default}

    local menu_height = self.height and math.min(self.height, self.screen_size.h) or self.screen_size.h
    local items_height = menu_height - self.bar:getSize().h - self.footer_top_margin:getSize().h - self.footer:getSize().h
    self.max_per_page = math.floor(items_height / (self.item_height + self.split_line:getSize().h))

    self.bar:switchToTab(self.last_index or 1)
end

function TouchMenu:updateItems(target_page, target_item_id)
    if #self.item_table == 0 then return end
    self.perpage = math.min(self.max_per_page, self.item_table.max_per_page or self.max_per_page_default)
    self.page_num = math.ceil(#self.item_table / self.perpage)
    if target_item_id ~= nil then -- show menu page with target item
        for i, v in ipairs(self.item_table) do
            if v.menu_item_id == target_item_id then
                target_page = math.floor( (i - 1) / self.perpage ) + 1
                break
            end
        end
    end
    self.page = target_page or self.page
    if self.page > self.page_num then
        self.page = self.page_num
    end

    self.item_group:clear()
    self.layout = {}
    table.insert(self.item_group, self.bar)
    table.insert(self.layout, self.bar.icon_widgets) -- for the focusmanager

    local idx_offset = (self.page - 1) * self.perpage
    for c = 1, self.perpage do
        -- calculate index in item_table
        local i = idx_offset + c
        if i <= #self.item_table then
            local item = self.item_table[i]
            item.idx = i
            local item_tmp = TouchMenuItem:new{
                item = item,
                menu = self,
                dimen = Geom:new{
                    w = self.item_width,
                    h = self.item_height,
                },
                show_parent = self.show_parent,
            }
            table.insert(self.item_group, item_tmp)
            if item_tmp:isEnabled() then
                table.insert(self.layout, {[self.cur_tab] = item_tmp}) -- for the focusmanager
            end
            if item.separator and c ~= self.perpage and i ~= #self.item_table then
                table.insert(self.item_group, self.split_line)
            end
        else
            -- item not enough to fill the whole page, break out of loop
            break
        end -- if i <= self.items
    end -- for c=1, self.perpage

    table.insert(self.item_group, self.footer_top_margin)
    table.insert(self.item_group, self.footer)
    if self.page_num > 1 then
        -- @translators %1 is the current page. %2 is the total number of pages. In some languages a good translation might need to reverse this order, for instance: "Total %2, page %1".
        self.page_info_text:setText(T(_("Page %1 of %2"), self.page, self.page_num))
    else
        self.page_info_text:setText("")
    end
    self.page_info_left_chev:showHide(self.page_num > 1)
    self.page_info_right_chev:showHide(self.page_num > 1)
    self.page_info_left_chev:enableDisable(self.page > 1)
    self.page_info_right_chev:enableDisable(self.page < self.page_num)

    local time_info_txt = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local powerd = Device:getPowerDevice()
    if Device:hasBattery() then
        local batt_lvl = powerd:getCapacity()
        local batt_symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), batt_lvl)
        time_info_txt = BD.wrap(time_info_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(batt_symbol) ..  BD.wrap(batt_lvl .. "%")
        if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            local aux_batt_lvl = powerd:getAuxCapacity()
            local aux_batt_symbol = powerd:getBatterySymbol(powerd:isAuxCharged(), powerd:isAuxCharging(), aux_batt_lvl)
            time_info_txt = time_info_txt .. " " .. BD.wrap("+") .. BD.wrap(aux_batt_symbol) ..  BD.wrap(aux_batt_lvl .. "%")
        end
    end
    self.time_info:setText(time_info_txt)

    -- recalculate dimen based on new layout
    local old_dimen = self.dimen:copy()
    self.dimen.w = self.width
    self.dimen.h = self.item_group:getSize().h + self.bordersize*2 + self.padding -- (no padding at top)
    self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS) -- reset the position of the focusmanager

    -- NOTE: We use a slightly ugly hack to detect a brand new menu vs. a tab switch,
    --       in order to optionally flash on initial menu popup...
    -- NOTE: Also avoid repainting what's underneath us on initial popup.
    -- NOTE: And we also only need to repaint what's behind us when switching to a smaller menu...
    local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
    UIManager:setDirty((self.is_fresh or keep_bg) and self.show_parent or "all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        local refresh_type = "ui"
        if self.is_fresh then
            refresh_type = "flashui"
            -- Drop the region, too, to make it full-screen? May help when starting from a "small" menu.
            --refresh_dimen = nil
            self.is_fresh = false
        end
        return refresh_type, refresh_dimen
    end)
end

function TouchMenu:switchMenuTab(tab_num)
    if self.tab_item_table[tab_num].remember ~= false then
        self.last_index = tab_num
    end
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if self.tab_item_table[tab_num].callback then
        self.tab_item_table[tab_num].callback()
    end

    -- It's like getting a new menu every time we switch tab!
    -- Also, switching to the _same_ tab resets the stack and takes us back to
    -- the top of the menu tree
    self.item_table_stack = {}
    self.parent_id = nil
    self.cur_tab = tab_num
    self.item_table = self.tab_item_table[tab_num]
    self:updateItems(1)
end

function TouchMenu:backToUpperMenu(no_close)
    if #self.item_table_stack ~= 0 then
        self.item_table = table.remove(self.item_table_stack)
        -- Allow a menu table to refresh itself when going up (ie. from a setting
        -- submenu that may want to have its parent menu updated).
        if self.item_table.needs_refresh and self.item_table.refresh_func then
            self.item_table = self.item_table.refresh_func()
        end
        self:updateItems(1, self.parent_id)
        self.parent_id = nil
    elseif not no_close then
        self:closeMenu()
    end
end

function TouchMenu:onBack()
    self:backToUpperMenu()
end

function TouchMenu:onNextPage()
    return self:onGotoPage(self.page + 1)
end

function TouchMenu:onPrevPage()
    return self:onGotoPage(self.page - 1)
end

function TouchMenu:onFirstPage()
    return self:onGotoPage(1)
end

function TouchMenu:onLastPage()
    return self:onGotoPage(self.page_num)
end

function TouchMenu:onGotoPage(nb)
    if nb > self.page_num then -- cycle by swipes only
        nb = 1
    elseif nb < 1 then
        nb = self.page_num
    end
    self:updateItems(nb)
    return true
end

function TouchMenu:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
    elseif direction == "north" then
        self:closeMenu()
    elseif direction == "south" then
        -- We don't allow the menu to be closed (this is also necessary as
        -- a swipe south will be emitted when done opening the menu with
        -- swipe, as the event handled for that is pan south).
        self:backToUpperMenu(true)
    end
end

function TouchMenu:onMenuSelect(item, tap_on_checkmark)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end

    if tap_on_checkmark and item.checkmark_callback then
        item.checkmark_callback()
        self:updateItems()
        return true
    end

    if item.tap_input or item.tap_input_func then
        if not item.keep_menu_open then
            self:closeMenu()
        end
        self:onInput(item.tap_input or item.tap_input_func())
        return true
    end

    local sub_item_table = item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
    if sub_item_table then
        if #sub_item_table > 0 then
            table.insert(self.item_table_stack, self.item_table)
            item.menu_item_id = item.menu_item_id or tostring(item) -- unique id
            self.parent_id = item.menu_item_id
            self.item_table = sub_item_table
            self:updateItems(1, self.item_table.open_on_menu_item_id_func
                and self.item_table.open_on_menu_item_id_func())
        end
        return true
    end

    -- keep menu opened if this item is a check option
    local callback = item.callback_func and item.callback_func() or item.callback
    if callback then
        -- Provide callback with us, so it can call our
        -- closemenu() or updateItems() when it sees fit
        -- (if not providing checked or checked_func, caller
        -- must set keep_menu_open=true if that is wished)
        callback(self)
        if item.checked or item.checked_func then -- refresh
            if not (item.check_callback_updates_menu or item.check_callback_closes_menu) then
                self:updateItems()
            end
        elseif not item.keep_menu_open then
            self:closeMenu()
        end
    end
    return true
end

function TouchMenu:onMenuHold(item, text_truncated)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end

    if item.hold_input or item.hold_input_func then
        if item.hold_keep_menu_open == false then
            self:closeMenu()
        end
        self:onInput(item.hold_input or item.hold_input_func())
        return true
    end

    local hold_callback = item.hold_callback_func and item.hold_callback_func() or item.hold_callback
    if hold_callback then
        -- With hold, the default is to keep menu open, as we're
        -- most often showing a ConfirmBox that can be cancelled
        -- (provide hold_keep_menu_open=false to override)
        if item.hold_keep_menu_open == false then
            self:closeMenu()
        end
        -- Provide callback with us, so it can call our
        -- closemenu() or updateItems() when it sees fit
        hold_callback(self, item)
        return true
    end

    local help_text = item.help_text_func and item.help_text_func(self) or item.help_text
    if help_text then
        UIManager:show(InfoMessage:new{ text = help_text, })
        return true
    end

    if text_truncated then
        UIManager:show(InfoMessage:new{
            text = getMenuText(item),
            show_icon = false,
        })
    end
    return true
end

function TouchMenu:closeMenu()
    self.close_callback()
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:closeMenu()
    end
end

function TouchMenu:onClose()
    self:closeMenu()
end

function TouchMenu:onCloseWidget()
    -- NOTE: We don't pass a region in order to ensure a full-screen flash to avoid ghosting,
    --       but we only need to do that if we actually have a FM or RD below us.
    -- Don't do anything when we're switching between the two, or if we don't actually have a live instance of 'em...
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    if (FileManager.instance and not FileManager.instance.tearing_down)
            or (ReaderUI.instance and not ReaderUI.instance.tearing_down) then
        UIManager:setDirty(nil, "flashui")
    end
end

-- Menu search feature
function TouchMenu:search(search_for)
    local found_menu_items = {}

    local MAX_MENU_DEPTH = 10 -- our menu max depth is currently 6
    local function recurse(item_table, path, text, icon, depth)
        if item_table.ignored_by_menu_search then
            return
        end
        depth = depth + 1
        if depth > MAX_MENU_DEPTH then
            return
        end
        for i, v in ipairs(item_table) do
            if type(v) == "table" and not v.ignored_by_menu_search then
                local entry_text = v.text_func and v.text_func() or v.text
                local entry_displayed_text = entry_text
                if v.enabled == false or (v.enabled_func and v.enabled_func() == false) then
                    entry_displayed_text = "\u{2592}\u{200A}" .. entry_displayed_text -- Medium Shade (▒) + Hair Space
                end
                local indent = "\u{2192}\u{200A}" -- Rightwards Arrow (→) + Hair Space
                if text then
                    indent = ("\u{200A}"):rep(2*math.min(depth-1, 6)) .. indent
                end
                local walk_text = text and (text .. "\n" .. indent .. entry_displayed_text) or (indent .. entry_displayed_text)
                local walk_path = path .. "." .. i
                if Utf8Proc.lowercase(entry_text):find(search_for, 1, true) then
                    table.insert(found_menu_items, {entry_text, icon, walk_path, walk_text})
                end
                local sub_item_table = v.sub_item_table
                if v.sub_item_table_func then
                    sub_item_table = v.sub_item_table_func()
                end
                if sub_item_table and not sub_item_table.ignored_by_menu_search then
                    recurse(sub_item_table, walk_path, walk_text, icon, depth)
                end
            end
        end
    end -- recurse

    -- Initial call of recurse, for each tab
    for i = 1, #self.tab_item_table do
        recurse(self.tab_item_table[i], i, nil, self.tab_item_table[i].icon, 0)
    end

    return found_menu_items
end

function TouchMenu:openMenu(path, with_animation)
    if self.not_shown then
        UIManager:show(self.show_parent)
    end
    local parts = {}
    for part in util.gsplit(path, "%.", false) do -- path is ie. "2.3.3.1"
        table.insert(parts, tonumber(part))
    end
    util.arrayReverse(parts) -- so we can just table.remove() and pop them from end

    local function highlightWidget(widget, unhighlight)
        if not widget then return end
        local highlight_dimen = widget.dimen
        if highlight_dimen.w == 0 then
            highlight_dimen.w = widget.width
        end
        if unhighlight then
            widget.invert = false
            UIManager:widgetInvert(widget, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "ui", highlight_dimen)
        else
            widget.invert = true
            UIManager:widgetInvert(widget, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "fast", highlight_dimen)
        end
    end

    -- Steps/state among consecutive calls to walkStep()
    local STEPS = {
        START = 0,
        TARGET_TAB_HIGHLIGHT_ICON = 1,
        TARGET_TAB_OPEN = 2,
        TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV = 3,
        TARGET_PAGE_OR_NAVIGATE_NEXT_PREV = 4,
        MENU_ITEM_HIGHLIGHT = 5, -- intermediate or final menu item
        MENU_ITEM_ENTER = 6, -- intermediate menu item only
        DONE = 7,
    }
    local step = STEPS.START
    local tab_nb
    local item_nb
    local walkStep_scheduled
    local trap_widget

    local function walkStep()
        walkStep_scheduled = false
        -- Default delay if not overridden (-1 means no scheduleIn() so no refresh, 0 means nextTick)
        local next_delay = with_animation and 1 or -1
        if step == STEPS.START then
            -- Ensure some initial delay so search dialog and result list can be closed and refreshed
            next_delay = with_animation and 1 or 0
            step = STEPS.TARGET_TAB_HIGHLIGHT_ICON
        elseif step == STEPS.TARGET_TAB_HIGHLIGHT_ICON then
            tab_nb = table.remove(parts)
            if with_animation then
                highlightWidget(self.bar.icon_widgets[tab_nb].image)
            end
            step = STEPS.TARGET_TAB_OPEN
        elseif step == STEPS.TARGET_TAB_OPEN then
            -- The tab icon wouldn't be unhighligted by any other action.
            -- Animation may have been cancelled, so unhighlight if it was.
            if self.bar.icon_widgets[tab_nb].image.invert then
                highlightWidget(self.bar.icon_widgets[tab_nb].image, true)
            end
            self:switchMenuTab(tab_nb)
            self.bar:switchToTab(tab_nb)
            item_nb = table.remove(parts)
            step = STEPS.TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV
        elseif step == STEPS.TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV or
               step == STEPS.TARGET_PAGE_OR_NAVIGATE_NEXT_PREV then
            local target_page = math.floor((item_nb - 1) / self.perpage) + 1
            local pages_diff = target_page - self.page
            if pages_diff == 0 then -- we are on the right menu page
                step = STEPS.MENU_ITEM_HIGHLIGHT
                next_delay = -1 -- we paused before, no need for more pause
                if not with_animation and #parts == 0 then
                    -- Except if no animation and we are on the final menu that
                    -- we want to highlight: this final highlight needs to be
                    -- delayed for it to be drawn after the final menu page is.
                    next_delay = 1
                end
            elseif step == STEPS.TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV then
                -- No need to highlight chevrons if no animation
                if with_animation then
                    if pages_diff > 0 then
                        highlightWidget(self.page_info_right_chev)
                    else
                        highlightWidget(self.page_info_left_chev)
                    end
                    if pages_diff > 1 or pages_diff < -1 then
                        -- Change pages quicker if more than one needed, but slow on the last one
                        next_delay = 0.5
                    end
                end
                step = STEPS.TARGET_PAGE_OR_NAVIGATE_NEXT_PREV
            else -- STEPS.TARGET_PAGE_OR_NAVIGATE_NEXT_PREV
                if pages_diff > 0 then
                    self:onNextPage()
                else
                    self:onPrevPage()
                end
                step = STEPS.TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV
                if with_animation and (pages_diff > 1 or pages_diff < -1) then
                    -- Change pages quicker if more than one needed, but slow on the last one
                    next_delay = 0.5
                end
            end
        elseif step == STEPS.MENU_ITEM_HIGHLIGHT then
            local item_widget
            for _, w in ipairs(self.item_group) do
                if w.item and w.item.idx == item_nb then
                    item_widget = w
                    break
                end
            end
            if item_widget then
                local is_disabled = item_widget.item.enabled == false
                    or (item_widget.item.enabled_func and item_widget.item.enabled_func() == false)
                if is_disabled then
                    -- do not go down to disabled submenu
                    -- do not highlight, text of highlighted disabled item is not visible
                    step = STEPS.DONE
                else
                    if with_animation or #parts == 0 then
                        -- Even if no animation, highlight the final item (and don't unhighlight it)
                        highlightWidget(item_widget)
                    end
                    step = #parts == 0 and STEPS.DONE or STEPS.MENU_ITEM_ENTER
                end
            else
                step = STEPS.DONE
            end
        elseif step == STEPS.MENU_ITEM_ENTER then
            self:onMenuSelect(self.item_table[item_nb])
            item_nb = table.remove(parts)
            step = STEPS.TARGET_PAGE_OR_HIGHLIGHT_NEXT_PREV
        else -- STEPS.DONE
            if trap_widget then
                UIManager:close(trap_widget)
                trap_widget = nil
            end
            return
        end
        if next_delay >= 0 then
            walkStep_scheduled = true
            UIManager:scheduleIn(next_delay, walkStep)
        else
            walkStep()
        end
    end

    -- We use an invisible TrapWidget when no animation, so we can
    -- cancel the delayed final highlight
    local TrapWidget = require("ui/widget/trapwidget")
    trap_widget = TrapWidget:new{
        text = with_animation and _("Walking you there…") or nil,
        dismiss_callback = function()
            trap_widget = nil
            if walkStep_scheduled then
                UIManager:unschedule(walkStep)
                if with_animation then
                    -- continue walking as if no animation, so we immediately
                    -- reach the requested menu item. We need a new invisible
                    -- TrapWidget for the reason explained above in case a
                    -- second tap happens.
                    with_animation = false
                    trap_widget = TrapWidget:new{
                        text = nil,
                        dismiss_callback = function()
                            trap_widget = nil
                            if walkStep_scheduled then
                                UIManager:unschedule(walkStep)
                            end
                        end,
                        resend_event = true,
                    }
                    UIManager:show(trap_widget)
                    walkStep()
                end
            end
        end,
        resend_event = not with_animation, -- if not animation, don't eat the tap
    }
    UIManager:show(trap_widget) -- catch taps during animation

    -- Call it: it will reschedule itself if animation; if not, it will
    -- just execute itself without pause until done.
    -- If tap while animating, it will switch to the non-animation
    -- behaviour, to reach the requested menu item immediately.
    walkStep()
end

function TouchMenu:onShowMenuSearch()
    local InputDialog = require("ui/widget/inputdialog")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Menu = require("ui/widget/menu")

    local function show_search_results(search_string)
        local found_menu_items = self:search(search_string)

        local function get_current_search_results()
            local function open_menu(i, animate)
                UIManager:close(self.results_menu_container)
                UIManager:setDirty(nil, "ui")
                self:openMenu(found_menu_items[i][3], animate)
            end
            local function item_callback(i)
                local confirm_box
                confirm_box = ConfirmBox:new{
                    text = found_menu_items[i][4],
                    icon = found_menu_items[i][2],
                    ok_text = _("Open"),
                    ok_callback = function()
                        UIManager:close(confirm_box)
                        open_menu(i)
                    end,
                    other_buttons = {{
                        {
                            text = _("Walk me there"),
                            callback = function()
                                UIManager:close(confirm_box)
                                open_menu(i, true)
                            end,
                        },
                    }},

                }
                UIManager:show(confirm_box)
            end

            local result_items = {}
            for i = 1, #found_menu_items do
                table.insert(result_items,
                    {
                        text = found_menu_items[i][1],
                        callback = function() item_callback(i) end,
                        hold_callback = function() open_menu(i) end,
                    }
                )
            end
            return result_items
        end -- get_current_search_results()

        if #found_menu_items > 0 then
            local results_menu = Menu:new{
                title = _("Search results"),
                subtitle = T(_("Query: %1"), search_string),
                item_table = get_current_search_results(),
                width = math.floor(self.screen_size.w * 0.9),
                height = math.floor(self.screen_size.h * 0.9),
                single_line = true,
                items_per_page = 10,
                items_font_size = Menu.getItemFontSize(10),
                onMenuSelect = function(item, pos)
                    if pos.callback then pos.callback() end
                end,
                onMenuHold = function(item, pos)
                    if pos.hold_callback then pos.hold_callback() end
                end,
                close_callback = function()
                    UIManager:close(self.results_menu_container)
                end
            }

            -- build container
            self.results_menu_container = CenterContainer:new{
                dimen = self.screen_size,
                results_menu,
            }

            results_menu.show_parent = self.results_menu_container

            UIManager:show(self.results_menu_container)

        else
            UIManager:show(InfoMessage:new{
                text = T(_("No menus containing '%1' found."), search_string),
            })
        end
    end -- show_search_results()

    local search_dialog
    search_dialog = InputDialog:new{
        title = _("Search menu entry"),
        description = _("Search for a menu entry containing the following text (case insensitive)."),
        input = G_reader_settings:readSetting("menu_search_string", _("Help")),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_for = search_dialog:getInputText()
                        search_for = Utf8Proc.lowercase(search_for)
                        G_reader_settings:saveSetting("menu_search_string", search_for)
                        UIManager:close(search_dialog)
                        show_search_results(search_for)
                    end,
                },
            }
        },
    }

    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
end

return TouchMenu
