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
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local getMenuText = require("ui/widget/menu").getMenuText
local _ = require("gettext")
local T = require("ffi/util").template
local Input = Device.input
local Screen = Device.screen

--[[
TouchMenuItem widget
--]]
local TouchMenuItem = InputContainer:new{
    menu = nil,
    vertical_align = "center",
    item = nil,
    dimen = nil,
    face = Font:getFace("smallinfofont"),
    show_parent = nil,
}

function TouchMenuItem:init()
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
    local checkmark_widget = CheckMark:new{
        checkable = item_checkable,
        checked = item_checked,
        enabled = item_enabled,
    }

    local checked_widget = CheckMark:new{ -- for layout, to :getSize()
        checked = true,
    }

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
        dimen = self.dimen,
        self.item_frame
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
    if enabled == false then return end

    -- If the menu hasn't actually been drawn yet, don't do anything (as it's confusing, and the coordinates may be wrong).
    if not self.item_frame.dimen then return end

    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuSelect(self.item)
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
        if self.item.keep_menu_open then
            UIManager:widgetInvert(self.item_frame, highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "ui", highlight_dimen)
        end

        -- Callback
        --
        self.menu:onMenuSelect(self.item)

        UIManager:forceRePaint()
    end
    return true
end

function TouchMenuItem:onHoldSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then return end

    if not self.item_frame.dimen then return end

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
local TouchMenuBar = InputContainer:new{
    width = Screen:getWidth(),
    icons = {},
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
    -- hold icon seperators
    self.icon_seps = {}
    -- the start_seg for first icon_widget should be 0
    -- we asign negative here to offset it in the loop
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
    self.dimen = Geom:new{ w = self.width, h = self.height }
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
local TouchMenu = FocusManager:new{
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
    page = 1,
    max_per_page_default = 10,
    -- for UIManager:setDirty
    show_parent = nil,
    cur_tab = -1,
    close_callback = nil,
    is_fresh = true,
}

function TouchMenu:init()
    -- We won't include self.bordersize in our width calculations, so that
    -- borders are pushed off-(screen-)width and so not visible.
    -- We'll then be similar to bottom menu ConfigDialog (where this
    -- nice effect is caused by some width calculations bug).
    if not self.dimen then self.dimen = Geom:new{} end
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
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
        }
    }
    self.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = self.dimen,
        }
    }

    self.key_events.Back = { {"Back"}, doc = "back to upper menu or close touchmenu" }
    if Device:hasFewKeys() then
        self.key_events.Back = { {"Left"}, doc = "back to upper menu or close touchmenu" }
    end
    self.key_events.NextPage = { {Input.group.PgFwd}, doc = "next page" }
    self.key_events.PrevPage = { {Input.group.PgBack}, doc = "previous page" }
    self.key_events.Press = { {"Press"}, doc = "chose selected item" }

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
    self.time_info = TextWidget:new{
        text = "",
        face = self.fface,
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
        dimen = Screen:getSize(),
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
    self.bar:switchToTab(self.last_index or 1)
end

function TouchMenu:onCloseWidget()
    -- NOTE: We don't pass a region in order to ensure a full-screen flash to avoid ghosting,
    --       but we only need to do that if we actually have a FM or RD below us.
    -- Don't do anything when we're switching between the two, or if we don't actually have a live instance of 'em...
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local reader_ui = ReaderUI:_getRunningInstance()
    if (FileManager.instance and not FileManager.instance.tearing_down) or (reader_ui and not reader_ui.tearing_down) then
        UIManager:setDirty(nil, "flashui")
    end
end

function TouchMenu:_recalculatePageLayout()
    local content_height  -- content == item_list + footer

    local bar_height = self.bar:getSize().h
    local footer_height = self.footer:getSize().h
    if self.height then
        content_height = self.height - bar_height
    else
        content_height = #self.item_table * self.item_height + footer_height
        -- split line height
        content_height = content_height + (#self.item_table - 1)
        content_height = content_height + self.footer_top_margin:getSize().h
    end
    if content_height + bar_height > Screen:getHeight() then
        content_height = Screen:getHeight() - bar_height
    end

    local item_list_content_height = content_height - footer_height
    self.perpage = math.floor(item_list_content_height / self.item_height)
    local max_per_page = self.item_table.max_per_page or self.max_per_page_default
    if self.perpage > max_per_page then
        self.perpage = max_per_page
    end

    self.page_num = math.ceil(#self.item_table / self.perpage)
end

function TouchMenu:updateItems()
    local old_dimen = self.dimen and self.dimen:copy()
    self:_recalculatePageLayout()
    self.item_group:clear()
    self.layout = {}
    table.insert(self.item_group, self.bar)
    table.insert(self.layout, self.bar.icon_widgets) -- for the focusmanager

    for c = 1, self.perpage do
        -- calculate index in item_table
        local i = (self.page - 1) * self.perpage + c
        if i <= #self.item_table then
            local item = self.item_table[i]
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
            if item.separator and c ~= self.perpage then
                -- insert split line
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

    local time_info_txt = util.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local powerd = Device:getPowerDevice()
    local batt_lvl = powerd:getCapacity()
    local batt_symbol
    if powerd:isCharging() then
        batt_symbol = ""
    else
        if batt_lvl >= 100 then
            batt_symbol = ""
        elseif batt_lvl >= 90 then
            batt_symbol = ""
        elseif batt_lvl >= 80 then
            batt_symbol = ""
        elseif batt_lvl >= 70 then
            batt_symbol = ""
        elseif batt_lvl >= 60 then
            batt_symbol = ""
        elseif batt_lvl >= 50 then
            batt_symbol = ""
        elseif batt_lvl >= 40 then
            batt_symbol = ""
        elseif batt_lvl >= 30 then
            batt_symbol = ""
        elseif batt_lvl >= 20 then
            batt_symbol = ""
        elseif batt_lvl >= 10 then
            batt_symbol = ""
        else
            batt_symbol = ""
        end
    end
    if Device:hasBattery() then
        time_info_txt = BD.wrap(time_info_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(batt_symbol) ..  BD.wrap(batt_lvl .. "%")
    end
    self.time_info:setText(time_info_txt)

    -- recalculate dimen based on new layout
    self.dimen.w = self.width
    self.dimen.h = self.item_group:getSize().h + self.bordersize*2 + self.padding -- (no padding at top)
    self.selected = { x = self.cur_tab, y = 1 } -- reset the position of the focusmanager

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

    -- It's like getting a new menu everytime we switch tab!
    -- Also, switching to the _same_ tab resets the stack and takes us back to
    -- the top of the menu tree
    self.page = 1
    -- clear item table stack
    self.item_table_stack = {}
    self.parent_id = nil
    self.cur_tab = tab_num
    self.item_table = self.tab_item_table[tab_num]
    self:updateItems()
end

function TouchMenu:backToUpperMenu()
    if #self.item_table_stack ~= 0 then
        self.item_table = table.remove(self.item_table_stack)
        self.page = 1
        if self.parent_id then
            self:_recalculatePageLayout() -- we need an accurate self.perpage
            for i = 1, #self.item_table do
                if self.item_table[i].menu_item_id == self.parent_id then
                    self.page = math.floor( (i - 1) / self.perpage ) + 1
                    break
                end
            end
            self.parent_id = nil
        end
        self:updateItems()
    else
        self:closeMenu()
    end
end

function TouchMenu:closeMenu()
    self.close_callback()
end

function TouchMenu:onNextPage()
    if self.page < self.page_num then
        self.page = self.page + 1
    elseif self.page == self.page_num then
        self.page = 1
    end
        self:updateItems()
    return true
end

function TouchMenu:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
    elseif self.page == 1 then
        self.page = self.page_num
    end
    self:updateItems()
    return true
end

function TouchMenu:onFirstPage()
    self.page = 1
    self:updateItems()
    return true
end

function TouchMenu:onLastPage()
    self.page = self.page_num
    self:updateItems()
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
    end
end

function TouchMenu:onMenuSelect(item)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if item.tap_input or type(item.tap_input_func) == "function" then
        if not item.keep_menu_open then
            self:closeMenu()
        end
        if item.tap_input then
            self:onInput(item.tap_input)
        else
            self:onInput(item.tap_input_func())
        end
    else
        local sub_item_table = item.sub_item_table
        if item.sub_item_table_func then
            sub_item_table = item.sub_item_table_func()
        end
        if sub_item_table == nil then
            -- keep menu opened if this item is a check option
            local callback, refresh = item.callback, item.checked or item.checked_func
            if item.callback_func then
                callback = item.callback_func()
            end
            if callback then
                -- Provide callback with us, so it can call our
                -- closemenu() or updateItems() when it sees fit
                -- (if not providing checked or checked_fund, caller
                -- must set keep_menu_open=true if that is wished)
                callback(self)
                if refresh then
                    self:updateItems()
                elseif not item.keep_menu_open then
                    self:closeMenu()
                end
            end
        else
            table.insert(self.item_table_stack, self.item_table)
            self.parent_id = item.menu_item_id
            self.item_table = sub_item_table
            self.page = 1
            if self.item_table.open_on_menu_item_id_func then
                self:_recalculatePageLayout() -- we need an accurate self.perpage
                local open_id = self.item_table.open_on_menu_item_id_func()
                for i = 1, #self.item_table do
                    if self.item_table[i].menu_item_id == open_id then
                        self.page = math.floor( (i - 1) / self.perpage ) + 1
                        break
                    end
                end
            end
            self:updateItems()
        end
    end
    return true
end

function TouchMenu:onMenuHold(item, text_truncated)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if item.hold_input or type(item.hold_input_func) == "function" then
        if item.hold_keep_menu_open == false then
            self:closeMenu()
        end
        if item.hold_input then
            self:onInput(item.hold_input)
        else
            self:onInput(item.hold_input_func())
        end
    elseif item.hold_callback or type(item.hold_callback_func) == "function" then
        local callback = item.hold_callback
        if item.hold_callback_func then
            callback = item.hold_callback_func()
        end
        if callback then
            -- With hold, the default is to keep menu open, as we're
            -- most often showing a ConfirmBox that can be cancelled
            -- (provide hold_keep_menu_open=false to override)
            if item.hold_keep_menu_open == false then
                self:closeMenu()
            end
            -- Provide callback with us, so it can call our
            -- closemenu() or updateItems() when it sees fit
            callback(self)
        end
    elseif item.help_text or type(item.help_text_func) == "function" then
        local help_text = item.help_text
        if item.help_text_func then
            help_text = item.help_text_func()
        end
        if help_text then
            UIManager:show(InfoMessage:new{ text = help_text, })
        end
    elseif text_truncated then
        UIManager:show(InfoMessage:new{
            text = getMenuText(item),
            show_icon = false,
        })
    end
    return true
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:closeMenu()
    end
end

function TouchMenu:onClose()
    self:closeMenu()
end

function TouchMenu:onBack()
    self:backToUpperMenu()
end

function TouchMenu:onPress()
    self:getFocusItem():handleEvent(Event:new("TapSelect"))
end

return TouchMenu
