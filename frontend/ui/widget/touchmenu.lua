local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local InputDialog = require("ui/widget/inputdialog")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local IconButton = require("ui/widget/iconbutton")
local GestureRange = require("ui/gesturerange")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")
local NetworkMgr = require("ui/networkmgr")

--[[
TouchMenuItem widget
--]]
local TouchMenuItem = InputContainer:new{
    menu = nil,
    vertical_align = "center",
    item = nil,
    dimen = nil,
    face = Font:getFace("cfont", 22),
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
    local item_checked = self.item.checked
    if self.item.checked_func then
        item_checked = self.item.checked_func()
    end
    local checked_widget = TextWidget:new{
        text = "√ ",
        face = self.face,
    }
    local unchecked_widget = TextWidget:new{
        text = "",
        face = self.face,
    }
    self.item_frame = FrameContainer:new{
        width = self.dimen.w,
        bordersize = 0,
        color = 15,
        HorizontalGroup:new {
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = checked_widget:getSize().w },
                item_checked and checked_widget or unchecked_widget
            },
            TextWidget:new{
                text = self.item.text or self.item.text_func(),
                bgcolor = 0.0,
                fgcolor = item_enabled ~= false and 1.0 or 0.5,
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

    self.item_frame.invert = true
    UIManager:setDirty(self.show_parent, "partial")
    UIManager:scheduleIn(0.5, function()
        self.item_frame.invert = false
        UIManager:setDirty(self.show_parent, "partial")
    end)
    self.menu:onMenuSelect(self.item)
end

function TouchMenuItem:onHoldSelect(arg, ges)
    local enabled = self.item.enabled
    if self.item.enabled_func then
        enabled = self.item.enabled_func()
    end
    if enabled == false then return end

    self.item_frame.invert = true
    UIManager:setDirty(self.show_parent, "partial")
    UIManager:scheduleIn(0.5, function()
        self.item_frame.invert = false
        UIManager:setDirty(self.show_parent, "partial")
    end)
    self.menu:onMenuHold(self.item)
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
    local icon_sep_width = Screen:scaleByDPI(2)
    local icons_sep_width = icon_sep_width * (#self.icons + 1)
    -- we assume all icons are of the same width
    local ib = IconButton:new{icon_file = self.icons[1]}
    local content_width = ib:getSize().w * #self.icons + icons_sep_width
    local spacing_width = (self.width - content_width)/(#self.icons*2)
    local spacing = HorizontalSpan:new{
        width = math.min(spacing_width, Screen:scaleByDPI(20))
    }
    self.height = ib:getSize().h + Screen:scaleByDPI(10)
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
    for k, v in ipairs(self.icons) do
        local ib = IconButton:new{
            show_parent = self.show_parent,
            icon_file = v,
            callback = nil,
        }

        table.insert(self.icon_widgets, HorizontalGroup:new{
            spacing, ib, spacing,
        })

        -- we have to use local variable here for closure callback
        local _start_seg = end_seg + icon_sep_width
        local _end_seg = _start_seg + self.icon_widgets[k]:getSize().w

        if k == 1 then
            self.bar_sep = LineWidget:new{
                dimen = Geom:new{
                    w = self.width,
                    h = Screen:scaleByDPI(2),
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
                w = Screen:scaleByDPI(2),
                h = self.height,
            }
        }
        table.insert(self.icon_seps, icon_sep)

        -- callback to set visual style
        ib.callback = function()
            self.bar_sep.empty_segments = {
                {
                    s = _start_seg, e = _end_seg
                }
            }
            for i, sep in ipairs(self.icon_seps) do
                local current_icon = i == k - 1 or i == k
                self.icon_seps[i].style = current_icon and "solid" or "none"
            end
            self.menu:switchMenuTab(k)
        end

        table.insert(self.bar_icon_group, self.icon_widgets[k])
        table.insert(self.bar_icon_group, icon_sep)

        start_seg = _start_seg
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


--[[
TouchMenu widget for hierarchical menus
--]]
local TouchMenu = InputContainer:new{
    tab_item_table = {},
    -- for returnning in multi-level menus
    item_table_stack = nil,
    item_table = nil,
    item_height = Screen:scaleByDPI(50),
    bordersize = Screen:scaleByDPI(2),
    padding = Screen:scaleByDPI(5),
    footer_height = 48 + Screen:scaleByDPI(5),
    fface = Font:getFace("ffont", 20),
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
        width = self.width - self.padding * 2 - self.bordersize * 2,
        icons = icons,
        show_parent = self.show_parent,
        menu = self,
    }

    self.item_group = VerticalGroup:new{
        align = "left",
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
    self.net_info = Button:new{
        icon = "resources/icons/appbar.wifi.png",
        callback = function() self:netToggle() end,
        bordersize = 0,
        show_parent = self,
    }
    self.device_info = HorizontalGroup:new{
        self.time_info,
        self.net_info,
    }
    local footer_width = self.width - self.padding*2 - self.bordersize*2
    self.footer = HorizontalGroup:new{
        LeftContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = self.footer_height},
            IconButton:new{
                invert = true,
                icon_file = "resources/icons/appbar.chevron.up.png",
                show_parent = self.show_parent,
                callback = function()
                    self:backToUpperMenu()
                end,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = self.footer_height},
            self.page_info,
        },
        RightContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = self.footer_height},
            self.device_info,
        }
    }

    self[1] = FrameContainer:new{
        padding = self.padding,
        bordersize = self.bordersize,
        background = 0,
        -- menubar and footer will be inserted in
        -- item_group in updateItems
        self.item_group,
    }

    self:switchMenuTab(1)
    self:updateItems()
end

function TouchMenu:_recalculateDimen()
    self.dimen.w = self.width

    -- if height not given, dynamically calculate it
    if not self.height then
        self.dimen.h = (#self.item_table + 2) * self.item_height
                        + self.bar:getSize().h
    else
        self.dimen.h = self.height
    end
    -- make sure self.dimen.h does not overflow screen height
    if self.dimen.h > Screen:getHeight() then
        self.dimen.h = Screen:getHeight() - self.bar:getSize().h
    end

    self.perpage = math.floor(self.dimen.h / self.item_height) - 2
    if self.perpage > self.max_per_page then
        self.perpage = self.max_per_page
    end

    self.page_num = math.ceil(#self.item_table / self.perpage)
end

function TouchMenu:updateItems()
    self:_recalculateDimen()
    self.item_group:clear()
    table.insert(self.item_group, self.bar)

    local item_width = self.dimen.w - self.padding*2 - self.bordersize*2

    for c = 1, self.perpage do
        -- calculate index in item_table
        local i = (self.page - 1) * self.perpage + c
        if i <= #self.item_table then
            local item_tmp = TouchMenuItem:new{
                item = self.item_table[i],
                menu = self,
                dimen = Geom:new{
                    w = item_width,
                    h = self.item_height,
                },
                show_parent = self.show_parent,
            }
            table.insert(self.item_group, item_tmp)
            -- insert split line
            if c ~= self.perpage then
                table.insert(self.item_group, HorizontalGroup:new{
                    -- pad with 10 pixel to align with the up arrow in footer
                    HorizontalSpan:new{width = 10},
                    LineWidget:new{
                        style = "dashed",
                        dimen = Geom:new{
                            w = item_width - 20,
                            h = 1,
                        }
                    }
                })
            end
        else
            -- item not enough to fill the whole page, break out of loop
            --table.insert(self.item_group,
                --VerticalSpan:new{
                    --width = self.item_height
                --})
            --break
        end -- if i <= self.items
    end -- for c=1, self.perpage

    table.insert(self.item_group, VerticalSpan:new{width = Screen:scaleByDPI(2)})
    table.insert(self.item_group, self.footer)
    self.page_info_text.text = _("Page ")..self.page.."/"..self.page_num
    self.page_info_left_chev:showHide(self.page_num > 1)
    self.page_info_right_chev:showHide(self.page_num > 1)
    self.page_info_left_chev:enableDisable(self.page > 1)
    self.page_info_right_chev:enableDisable(self.page < self.page_num)
    self.time_info.text = os.date("%H:%M").." @ "..Device:getPowerDevice():getCapacity().."%"
    self.net_info.label_widget.dim = not NetworkMgr:getWifiStatus()
    -- FIXME: this is a dirty hack to clear previous menus
    -- refert to issue #664
    UIManager.repaint_all = true
end

function TouchMenu:netToggle()
    if self.net_info.label_widget.dim == false then
        NetworkMgr:promptWifiOff()
    else
        NetworkMgr:promptWifiOn()
    end
    self:closeMenu()
end


function TouchMenu:switchMenuTab(tab_num)
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
    end
end

function TouchMenu:closeMenu()
    self.close_callback()
end

function TouchMenu:onNextPage()
    if self.page < self.page_num then
        self.page = self.page + 1
        self:updateItems()
    end
    return true
end

function TouchMenu:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
        self:updateItems()
    end
    return true
end

function TouchMenu:onSwipe(arg, ges_ev)
    if ges_ev.direction == "west" or ges_ev.direction == "north" then
        self:onNextPage()
    elseif ges_ev.direction == "east" or ges_ev.direction == "south" then
        self:onPrevPage()
    end
end

function TouchMenu:onMenuSelect(item)
    if item.tap_input then
        self:closeMenu()
        self:onMenuInput(item.tap_input)
    else
        local sub_item_table = item.sub_item_table
        if item.sub_item_table_func then
            sub_item_table = item.sub_item_table_func()
        end
        if sub_item_table == nil then
            local callback = item.callback
            if item.callback_func then
                callback = item.callback_func()
            end
            if callback then
                -- put stuff in scheduler so we can See
                -- the effect of inverted menu item
                UIManager:scheduleIn(0.1, function()
                    self:closeMenu()
                    callback()
                end)
            end
        else
            table.insert(self.item_table_stack, self.item_table)
            self.item_table = sub_item_table
            self:updateItems()
        end
    end
    return true
end

function TouchMenu:onMenuHold(item)
    if item.hold_input then
        self:closeMenu()
        self:onMenuInput(item.hold_input)
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

function TouchMenu:onMenuInput(input)
    self.input_dialog = InputDialog:new{
        title = input.title or "",
        input_hint = input.hint or "",
        input_type = input.type or "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("OK"),
                    callback = function()
                        input.callback(self.input_dialog:getInputText())
                        self:closeInputDialog()
                    end,
                },
            },
        },
        enter_callback = function()
            input.callback(self.input_dialog:getInputText())
            self:closeInputDialog()
        end,
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.input_dialog:onShowKeyboard()
    UIManager:show(self.input_dialog)
end

function TouchMenu:closeInputDialog()
    self.input_dialog:onClose()
    UIManager:close(self.input_dialog)
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
