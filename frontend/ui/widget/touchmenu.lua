local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local Screen = require("ui/screen")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local IconButton = require("ui/widget/iconbutton")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local DEBUG = require("dbg")
local _ = require("gettext")

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
    }

    local item_enabled = self.item.enabled
    if self.item.enabled_func then
        item_enabled = self.item.enabled_func()
    end
    self.item_frame = FrameContainer:new{
        width = self.dimen.w,
        bordersize = 0,
        color = 15,
        HorizontalGroup:new {
            align = "center",
            HorizontalSpan:new{ width = 10 },
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
TouchMenu widget
--]]
local TouchMenu = InputContainer:new{
    tab_item_table = {},
    -- for returnning in multi-level menus
    item_table_stack = nil,
    item_table = nil,
    item_height = Screen:scaleByDPI(50),
    bordersize = Screen:scaleByDPI(2),
    padding = Screen:scaleByDPI(5),
    footer_height = Screen:scaleByDPI(50),
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

    self.footer_page = TextWidget:new{
        face = Font:getFace("ffont", 20),
        text = "",
    }
    self.time_info = TextWidget:new{
        face = Font:getFace("ffont", 20),
        text = "",
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
            self.footer_page,
        },
        RightContainer:new{
            dimen = Geom:new{ w = footer_width*0.33, h = self.footer_height},
            self.time_info,
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
    self.footer_page.text = _("Page ")..self.page.."/"..self.page_num
    self.time_info.text = os.date("%H:%M")
    -- FIXME: this is a dirty hack to clear previous menus
    -- refert to issue #664
    UIManager.repaint_all = true
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
    local enabled = item.enabled
    if item.enabled_func then
        enabled = item.enabled_func()
    end
    if enabled == false then return end
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
    return true
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:closeMenu()
    end
end

return TouchMenu
