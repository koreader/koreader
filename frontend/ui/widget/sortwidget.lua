local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

local SortItemWidget = InputContainer:extend{
    item = nil,
    face = Font:getFace("smallinfofont"),
    width = nil,
    height = nil,
}

function SortItemWidget:init()
    self.dimen = Geom:new{x = 0, y = 0, w = self.width, h = self.height}
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
        focusable = true,
        focus_border_size = Size.border.thin,
        LeftContainer:new{ -- needed only for auto UI mirroring
            dimen = Geom:new{
                w = self.width,
                h = self.height,
            },
            HorizontalGroup:new{
                align = "center",
                CenterContainer:new{
                    dimen = Geom:new{ w = checked_widget:getSize().w },
                    self.checkmark_widget,
                },
                TextWidget:new{
                    text = self.item.text,
                    max_width = text_max_width,
                    face = self.item.face or self.face,
                },
            },
        },
    }
    self[1].invert = self.invert
end

function SortItemWidget:onTap(_, ges)
    if self.item.checked_func and ( self.show_parent.sort_disabled or ges.pos:intersectWith(self.checkmark_widget.dimen) ) then
        if self.item.callback then
            self.item:callback()
        end
    elseif self.show_parent.sort_disabled then
        if self.item.callback then
            self.item:callback()
        else
            return true
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
    if self.item.hold_callback then
        self.item:hold_callback(function() self.show_parent:_populateItems() end)
    elseif self.item.callback then
        self.item:callback()
        self.show_parent:_populateItems()
    end
    return true
end

local SortWidget = FocusManager:extend{
    title = "",
    width = nil,
    height = nil,
    -- index for the first item to show
    show_page = 1,
    -- table of items to sort
    item_table = nil, -- mandatory (array)
    callback = nil,
    sort_disabled = false,
}

function SortWidget:init()
    self.layout = {}
    -- no item is selected on start
    self.marked = 0
    self.orig_item_table = nil

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
        self.key_events.ShowWidgetMenu = { { "Menu" } }
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
    self.footer_center_width = math.floor(self.width_widget * (22/100))
    self.footer_button_width = math.floor(self.width_widget * (12/100))
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
        icon = "exit",
        width = self.footer_button_width,
        callback = function() self:onClose() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_ok = Button:new{
        icon = "check",
        width = self.footer_button_width,
        callback = function() self:onReturn() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_page = Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            input_type = "number",
            hint_func = function()
                return string.format("(1 - %s)", self.pages)
            end,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
            ok_text = _("Go to page"),
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
    table.insert(self.layout, {
        self.footer_cancel,
        self.footer_first_up,
        self.footer_left,
        self.footer_page,
        self.footer_right,
        self.footer_last_down,
        self.footer_ok,
    })
    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.item_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_DARK_GRAY,
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
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        align = "left",
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
        bottom_line_h_padding = padding,
        title = self.title,
        left_icon = not self.sort_disabled and "appbar.menu",
        left_icon_tap_callback = function() self:onShowWidgetMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    -- setup main content
    self.item_margin = math.floor(self.item_height / 8)
    local line_height = self.item_height + self.item_margin
    local content_height = self.dimen.h - self.title_bar:getHeight() - vertical_footer:getSize().h - padding
    self.items_per_page = math.floor(content_height / line_height)
    self.pages = math.ceil(#self.item_table / self.items_per_page)
    self.main_content = VerticalGroup:new{}

    self:_populateItems()

    local padding_below_title = 0
    if self.pages > 1 then -- center content vertically
        padding_below_title = (content_height - self.items_per_page * line_height) / 2
    end
    local frame_content = FrameContainer:new{
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.title_bar,
            VerticalSpan:new{ width = padding_below_title },
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
    if self.show_page < self.pages then
        self.show_page = self.show_page + 1
        if self.marked > 0 then -- put selected item first in the page
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        else
            self:_populateItems()
        end
    end
end

function SortWidget:prevPage()
    if self.show_page > 1 then
        self.show_page = self.show_page - 1
        if self.marked > 0 then -- put selected item first in the page
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        else
            self:_populateItems()
        end
    end
end

function SortWidget:goToPage(page)
    self.show_page = page
    self:_populateItems()
end

function SortWidget:moveItem(diff)
    local move_to = self.marked + diff
    if move_to > 0 and move_to <= #self.item_table then
        -- Remember the original state to support Cancel
        if not self.orig_item_table then
            self.orig_item_table = util.tableDeepCopy(self.item_table)
        end
        table.insert(self.item_table, move_to, table.remove(self.item_table, self.marked))
        self.show_page = math.ceil(move_to / self.items_per_page)
        self.marked = move_to
        self:_populateItems()
    end
end

-- make sure self.item_margin and self.item_height are set before calling this
function SortWidget:_populateItems()
    self.main_content:clear()
    self.layout = { self.layout[#self.layout] } -- keep footer
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
        local item = SortItemWidget:new{
            height = self.item_height,
            width = self.item_width,
            item = self.item_table[idx],
            invert = invert_status,
            index = idx,
            show_parent = self,
        }
        table.insert(self.layout, #self.layout, {item})
        table.insert(self.main_content, item)
    end
    if self.marked == 0 then
        -- Reset the focus to the top of the page when we're not moving an item (#12342)
        self:moveFocusTo(1, 1)
    else
        -- When we're moving an item, move the focus to the footer (last row),
        -- while keeping the focus on the current button (or cancel for the initial move,
        -- as there's only one column of items, so x == 1, which points to the first button, which is cancel).
        -- even when we change pages and the amount of rows may have changed
        self:moveFocusTo(self.selected.x, #self.layout)
    end

    -- NOTE: We forgo our usual "Page x of y" wording because of space constraints given the way the widget is currently built
    self.footer_page:setText(T(C_("Pagination", "%1 / %2"), self.show_page, self.pages), self.footer_center_width)
    if self.pages > 1 then
        self.footer_page:enable()
    else
        self.footer_page:disableWithoutDimming()
    end
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    if self.marked > 0 then
        -- setIcon will recreate the frame, but we want to preserve the focus inversion
        self.footer_cancel.preselect = self.footer_cancel.frame.invert
        self.footer_cancel:setIcon("cancel", self.footer_button_width)
        self.footer_cancel.callback = function() self:onCancel() end
        self.footer_first_up:setIcon("move.up", self.footer_button_width)
        self.footer_last_down:setIcon("move.down", self.footer_button_width)
    else
        self.footer_cancel.preselect = self.footer_cancel.frame.invert
        self.footer_cancel:setIcon("exit", self.footer_button_width)
        self.footer_cancel.callback = function() self:onClose() end
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

function SortWidget:onShowWidgetMenu()
    local dialog
    local buttons = {
        {{
            text = _("Sort A to Z"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("strcoll")
            end,
        }},
        {{
            text = _("Sort Z to A"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("strcoll", true)
            end,
        }},
        {{
            text = _("Sort A to Z (natural)"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("natural")
            end,
        }},
        {{
            text = _("Sort Z to A (natural)"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("natural", true)
            end,
        }},
    }
    dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
    return true
end

function SortWidget:sortItems(collate, reverse_collate)
    if not self.orig_item_table then
        self.orig_item_table = util.tableDeepCopy(self.item_table)
    end
    local FileChooser = require("ui/widget/filechooser")
    local sort_func = FileChooser:getSortingFunction(FileChooser.collates[collate], reverse_collate)
    table.sort(self.item_table, sort_func)
    self.show_page = 1
    self.marked = 1 -- enable cancel button
    self:_populateItems()
end

function SortWidget:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
    return true
end

function SortWidget:onCancel()
    self.marked = 0
    if self.orig_item_table then
        -- We can't break the reference to self.item_table, as that's what the callback uses to update the original data...
        -- So, do this in two passes: empty it, then re-fill it from the copy.
        for i = #self.item_table, 1, -1 do
            self.item_table[i] = nil
        end

        for __, item in ipairs(self.orig_item_table) do
            table.insert(self.item_table, item)
        end

        self.orig_item_table = nil
    end

    self:goToPage(self.show_page)
    return true
end

function SortWidget:onReturn()
    -- The callback we were passed is usually responsible for passing along the re-ordered table itself,
    -- as well as items' enabled flag, if any, meaning we have to honor it even if nothing was moved.
    if self.callback then
        self:callback()
    end

    -- If we're not in the middle of moving stuff around, just exit.
    if self.marked == 0 then
        return self:onClose()
    end

    self.marked = 0
    self.orig_item_table = nil
    self:goToPage(self.show_page)
    return true
end

return SortWidget
