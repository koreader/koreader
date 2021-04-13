local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local SortTitleWidget = VerticalGroup:new{
    sort_page = nil,
    title = "",
    tface = Font:getFace("tfont"),
    align = "left",
}

function SortTitleWidget:init()
    self.close_button = CloseButton:new{ window = self }
    local btn_width = self.close_button:getSize().w
    -- title, close button, separation line
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width },
        TextWidget:new{
            text = self.title,
            max_width = self.width - btn_width,
            face = self.tface,
        },
        self.close_button,
    })
    self.title_bottom = OverlapGroup:new{
        dimen = { w = self.width, h = Size.line.thick },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thick },
            background = Blitbuffer.COLOR_DARK_GRAY,
            style = "solid",
        },
    }
    table.insert(self, self.title_bottom)
    table.insert(self, VerticalSpan:new{ width = Size.span.vertical_large })
end

function SortTitleWidget:onClose()
    self.sort_page:onClose()
    return true
end

local SortItemWidget = InputContainer:new{
    item = nil,
    face = Font:getFace("smallinfofont"),
    width = nil,
    height = nil,
}

function SortItemWidget:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
        self.ges_events.Hold = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            }
        }
    end

    local item_checkable = false
    local item_checked = self.item.checked
    if self.item.checked_func then
        item_checkable = true
        item_checked = self.item.checked_func()
    end
    self.checkmark_widget = CheckMark:new{
        checkable = item_checkable,
        checked = item_checked,
    }

    local checked_widget = CheckMark:new{ -- for layout, to :getSize()
        checked = true,
    }

    local text_max_width = self.width - 2 * Size.padding.default - checked_widget:getSize().w

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        HorizontalGroup:new {
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = checked_widget:getSize().w },
                self.checkmark_widget,
            },
            TextWidget:new{
                text = self.item.text,
                max_width = text_max_width,
                face = self.face,
            },
        },
    }
    self[1].invert = self.invert
end

function SortItemWidget:onTap(_, ges)
    if self.item.checked_func and ges.pos:intersectWith(self.checkmark_widget.dimen) then
        if self.item.callback then
            self.item:callback()
        end
    elseif self.show_parent.marked == self.index then
        self.show_parent.marked = 0
    else
        self.show_parent.marked = self.index
    end
    self.show_parent:_populateItems()
    return true
end

function SortItemWidget:onHold()
    if self.item.callback then
        self.item:callback()
        self.show_parent:_populateItems()
    end
    return true
end

local SortWidget = InputContainer:new{
    title = "",
    width = nil,
    height = nil,
    -- index for the first item to show
    show_page = 1,
    -- table of items to sort
    item_table = {},
    callback = nil,
}

function SortWidget:init()
    self.marked = 0 -- no item is selected on start
    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events = {
            --don't get locked in on non touch devices
            AnyKeyPressed = { { Device.input.group.Any },
                seqtext = "any key", doc = "close dialog" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end
    local padding = Size.padding.large
    self.width_widget = self.dimen.w - 2 * padding
    self.item_width = self.dimen.w - 2 * padding
    self.footer_center_width = self.width_widget * 22 / 100
    self.footer_button_width = self.width_widget * 12 / 100
    self.item_height = Size.item.height_big
    -- group for footer
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.footer_left = Button:new{
        icon = chevron_left,
        width = self.footer_button_width,
        callback = function() self:prevPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_right = Button:new{
        icon = chevron_right,
        width = self.footer_button_width,
        callback = function() self:nextPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_first_up = Button:new{
        icon = chevron_first,
        width = self.footer_button_width,
        callback = function()
            if self.marked > 0 then
                self:moveItem(-1)
            else
                self:goToPage(1)
            end
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_last_down = Button:new{
        icon = chevron_last,
        width = self.footer_button_width,
        callback = function()
            if self.marked > 0 then
                self:moveItem(1)
            else
                self:goToPage(self.pages)
            end
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_cancel = Button:new{
        text = _("Cancel"),
        width = self.footer_button_width,
        callback = function() self:onClose() end,
        bordersize = 0,
        padding = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_ok = Button:new{
        text = _("Save"),
        width = self.footer_button_width,
        callback = function() self:onReturn() end,
        bordersize = 0,
        padding = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_page = Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            hint_func = function()
                return "(" .. "1 - " .. self.pages .. ")"
            end,
            type = "number",
            deny_blank_input = true,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
            ok_text = "Go to page",
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        margin = 0,
        text_font_face = "pgfont",
        text_font_bold = false,
        width = self.footer_center_width,
        show_parent = self,
    }
    self.page_info = HorizontalGroup:new{
        self.footer_cancel,
        self.footer_first_up,
        self.footer_left,
        self.footer_page,
        self.footer_right,
        self.footer_last_down,
        self.footer_ok,
    }
    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.item_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_DARK_GRAY,
        style = "solid",
    }
    local vertical_footer = VerticalGroup:new{
        bottom_line,
        self.page_info,
    }
    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        vertical_footer,
    }
    -- setup title bar
    self.title_bar = SortTitleWidget:new{
        title = self.title,
        width = self.item_width,
        height = self.item_height,
        sort_page = self,
    }
    -- setup main content
    self.item_margin = self.item_height / 8
    local line_height = self.item_height + self.item_margin
    local content_height = self.dimen.h - self.title_bar:getSize().h - vertical_footer:getSize().h - padding
    self.items_per_page = math.floor(content_height / line_height)
    self.pages = math.ceil(#self.item_table / self.items_per_page)
    self.main_content = VerticalGroup:new{}

    self:_populateItems()

    local frame_content = FrameContainer:new{
        height = self.dimen.h,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.main_content,
        },
    }
    local content = OverlapGroup:new{
        dimen = self.dimen:copy(),
        frame_content,
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
end

function SortWidget:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        if self.marked > 0 then
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        end
        self:_populateItems()
    end
end

function SortWidget:prevPage()
    local new_page = math.max(self.show_page - 1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        if self.marked > 0 then
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        end
        self:_populateItems()
    end
end

function SortWidget:goToPage(page)
    self.show_page = page
    self:_populateItems()
end

function SortWidget:moveItem(diff)
    local move_to = self.marked + diff
    if move_to > 0 and move_to <= #self.item_table then
        table.insert(self.item_table, move_to, table.remove(self.item_table, self.marked))
        self.show_page = math.ceil(move_to / self.items_per_page)
        self.marked = move_to
        self:_populateItems()
    end
end

-- make sure self.item_margin and self.item_height are set before calling this
function SortWidget:_populateItems()
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page
    local page_last
    if idx_offset + self.items_per_page <= #self.item_table then
        page_last = idx_offset + self.items_per_page
    else
        page_last = #self.item_table
    end
    for idx = idx_offset + 1, page_last do
        table.insert(self.main_content, VerticalSpan:new{ width = self.item_margin })
        local invert_status = false
        if idx == self.marked then
            invert_status = true
        end
        table.insert(
            self.main_content,
            SortItemWidget:new{
                height = self.item_height,
                width = self.item_width,
                item = self.item_table[idx],
                invert = invert_status,
                index = idx,
                show_parent = self,
            }
        )
    end
    self.footer_page:setText(T(_("Page %1 of %2"), self.show_page, self.pages), self.footer_center_width)
    if self.pages > 1 then
        self.footer_page:enable()
    else
        self.footer_page:disableWithoutDimming()
    end
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    local move_up = "move.up"
    local move_down = "move.down"
    if BD.mirroredUILayout() then
        chevron_first, chevron_last = chevron_last, chevron_first
        move_up, move_down = move_down, move_up
    end
    if self.marked > 0 then
        self.footer_first_up:setIcon(move_up, self.footer_button_width)
        self.footer_last_down:setIcon(move_down, self.footer_button_width)
    else
        self.footer_first_up:setIcon(chevron_first, self.footer_button_width)
        self.footer_last_down:setIcon(chevron_last, self.footer_button_width)
    end
    self.footer_left:enableDisable(self.show_page > 1)
    self.footer_right:enableDisable(self.show_page < self.pages)
    self.footer_first_up:enableDisable(self.show_page > 1 or (self.marked > 0 and self.marked > 1))
    self.footer_last_down:enableDisable(self.show_page < self.pages or (self.marked > 0 and self.marked < #self.item_table))
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function SortWidget:onAnyKeyPressed()
    return self:onClose()
end

function SortWidget:onNextPage()
    self:nextPage()
    return true
end

function SortWidget:onPrevPage()
    self:prevPage()
    return true
end

function SortWidget:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function SortWidget:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
    return true
end

function SortWidget:onReturn()
    UIManager:close(self)
    if self.callback then self:callback() end
    return true
end

return SortWidget
