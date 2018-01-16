--[[--
TouchMenu widget for hierarchical menus.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen
local getMenuText = require("util").getMenuText

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
    local checked_widget = CheckMark:new{
        checked = true,
    }
    local unchecked_widget = CheckMark:new{
        checked = false,
    }
    local empty_widget = CheckMark:new{
        checkable = false,
    }
    self.item_frame = FrameContainer:new{
        width = self.dimen.w,
        bordersize = 0,
        color = Blitbuffer.COLOR_BLACK,
        HorizontalGroup:new {
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = checked_widget:getSize().w },
                item_checkable and (
                    item_checked and checked_widget
                    or unchecked_widget
                )
                or empty_widget
            },
            TextWidget:new{
                text = getMenuText(self.item),
                fgcolor = item_enabled ~= false and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GREY,
                face = self.face,
            },
        },
    }
    self[1] = self.item_frame
end

function TouchMenuItem:onTapSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then return end

    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuSelect(self.item)
    else
        self.item_frame.invert = true
        UIManager:setDirty(self.show_parent, function()
            return "ui", self.dimen
        end)
        -- yield to main UI loop to invert item
        UIManager:scheduleIn(0.1, function()
            self.menu:onMenuSelect(self.item)
            self.item_frame.invert = false
            UIManager:setDirty(self.show_parent, function()
                return "ui", self.dimen
            end)
        end)
    end
    return true
end

function TouchMenuItem:onHoldSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then return end

    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.item)
    else
        UIManager:scheduleIn(0.0, function()
            self.item_frame.invert = true
            UIManager:setDirty(self.show_parent, function()
                return "ui", self.dimen
            end)
        end)
        UIManager:scheduleIn(0.1, function()
            self.menu:onMenuHold(self.item)
        end)
        UIManager:scheduleIn(0.5, function()
            self.item_frame.invert = false
            UIManager:setDirty(self.show_parent, function()
                return "ui", self.dimen
            end)
        end)
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
    local icon_width = Screen:scaleBySize(40)
    local icon_height = icon_width
    -- content_width is the width of all the icon images
    local content_width = icon_width * #self.icons + icons_sep_width
    local spacing_width = (self.width - content_width)/(#self.icons*2)
    local icon_padding = math.min(spacing_width, Screen:scaleBySize(16))
    self.height = icon_height + Size.span.vertical_large
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
            icon_file = v,
            width = icon_width,
            height = icon_height,
            scale_for_dpi = false,
            callback = nil,
            padding_left = icon_padding,
            padding_right = icon_padding,
        }

        table.insert(self.icon_widgets, ib)

        -- we have to use local variable here for closure callback
        local _start_seg = end_seg + icon_sep_width
        local _end_seg = _start_seg + self.icon_widgets[k]:getSize().w

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
                    self.bar_sep.empty_segments = {
                        {
                            s = icon_sep_width + stretch_width + _start_seg, e = icon_sep_width + stretch_width + _end_seg
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

        end_seg = _end_seg
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
        index = 1
    end
    self.icon_widgets[index].callback()
end

--[[
TouchMenu widget for hierarchical menus
--]]
local TouchMenu = InputContainer:new{
    tab_item_table = {},
    -- for returnning in multi-level menus
    item_table_stack = nil,
    item_table = nil,
    item_height = Size.item.height_large,
    bordersize = Size.border.window,
    padding = Size.padding.default,
    fface = Font:getFace("ffont"),
    width = nil,
    height = nil,
    page = 1,
    max_per_page = 10,
    -- for UIManager:setDirty
    show_parent = nil,
    cur_tab = -1,
    close_callback = nil,
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

    self.key_events.Close = { {"Back"}, doc = "close touch menu" }

    local icons = {}
    for _,v in ipairs(self.tab_item_table) do
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
    self.page_info_left_chev = Button:new{
        icon = "resources/icons/appbar.chevron.left.png",
        callback = function() self:onPrevPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_right_chev = Button:new{
        icon = "resources/icons/appbar.chevron.right.png",
        callback = function() self:onNextPage() end,
        bordersize = 0,
        show_parent = self,
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
    --group for device info
    self.time_info = TextWidget:new{
        text = "",
        face = self.fface,
    }
    self.device_info = HorizontalGroup:new{
        self.time_info,
        -- Add some span to balance up_button image included padding
        HorizontalSpan:new{width = Size.span.horizontal_default},
    }
    local up_button = IconButton:new{
        icon_file = "resources/icons/appbar.chevron.up.png",
        show_parent = self.show_parent,
        callback = function()
            self:backToUpperMenu()
        end,
    }
    local footer_width = self.width - self.padding*2
    local footer_height = up_button:getSize().h + Size.line.thick
    self.footer = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = footer_height},
            up_button,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = footer_height},
            self.page_info,
        },
        RightContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = footer_height},
            self.device_info,
        }
    }

    self.menu_frame = FrameContainer:new{
        padding = self.padding,
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
            background = Blitbuffer.gray(0.33),
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
    UIManager:setDirty(nil, "partial", self.dimen)
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
    if self.perpage > self.max_per_page then
        self.perpage = self.max_per_page
    end

    self.page_num = math.ceil(#self.item_table / self.perpage)
end

function TouchMenu:updateItems()
    local old_dimen = self.dimen and self.dimen:copy()
    self:_recalculatePageLayout()
    self.item_group:clear()
    table.insert(self.item_group, self.bar)

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
    self.page_info_text.text = util.template(_("Page %1 of %2"), self.page, self.page_num)
    self.page_info_left_chev:showHide(self.page_num > 1)
    self.page_info_right_chev:showHide(self.page_num > 1)
    self.page_info_left_chev:enableDisable(self.page > 1)
    self.page_info_right_chev:enableDisable(self.page < self.page_num)
    local time_info_txt = os.date("%H:%M").." @ "
    if Device:getPowerDevice():isCharging() then
        time_info_txt = time_info_txt.."+"
    end
    time_info_txt = time_info_txt..Device:getPowerDevice():getCapacity().."%"
    self.time_info:setText(time_info_txt)

    -- recalculate dimen based on new layout
    self.dimen.w = self.width
    self.dimen.h = self.item_group:getSize().h + self.bordersize*2 + self.padding*2

    UIManager:setDirty("all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
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
    if self.cur_tab ~= tab_num then
        -- it's like getting a new menu everytime we switch tab!
        self.page = 1
        -- clear item table stack
        self.item_table_stack = {}
        self.cur_tab = tab_num
        self.item_table = self.tab_item_table[tab_num]
        self:updateItems()
    end
end

function TouchMenu:backToUpperMenu()
    if #self.item_table_stack ~= 0 then
        self.item_table = table.remove(self.item_table_stack)
        self.page = 1
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

function TouchMenu:onSwipe(arg, ges_ev)
    if ges_ev.direction == "west" then
        self:onNextPage()
    elseif ges_ev.direction == "east" then
        self:onPrevPage()
    elseif ges_ev.direction == "north" then
        self:closeMenu()
    end
end

function TouchMenu:onMenuSelect(item)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if item.tap_input or type(item.tap_input_func) == "function" then
        self:closeMenu()
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
                -- put stuff in scheduler so we can see
                -- the effect of inverted menu item
                UIManager:scheduleIn(0.1, function()
                    callback(self)
                    if refresh then
                        self:updateItems()
                    else
                        self:closeMenu()
                    end
                end)
            end
        else
            table.insert(self.item_table_stack, self.item_table)
            self.item_table = sub_item_table
            self.page = 1
            self:updateItems()
        end
    end
    return true
end

function TouchMenu:onMenuHold(item)
    if self.touch_menu_callback then
        self.touch_menu_callback()
    end
    if item.hold_input or type(item.hold_input_func) == "function" then
        self:closeMenu()
        if item.hold_input then
            self:onInput(item.hold_input)
        else
            self:onInput(item.hold_input_func())
        end
    else
        local callback = item.hold_callback
        if item.hold_callback_func then
            callback = item.hold_callback_func()
        end
        if callback then
            UIManager:scheduleIn(0.1, function()
                self:closeMenu()
                callback()
            end)
        end
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

return TouchMenu
