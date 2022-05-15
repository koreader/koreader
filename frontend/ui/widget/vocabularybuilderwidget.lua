local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
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
local RightContainer = require("ui/widget/container/rightcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Screen = Device.screen
local logger = require("logger")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

--------

local word_face = Font:getFace("x_smallinfofont")
local subtitle_face = Font:getFace("cfont", 12)
local subtitle_italic_face = Font:getFace("NotoSans-Italic.ttf", 12)
local nerd_face = Font:getFace("smallinfofont")
-- More Info

function getDialogWidth()
    return math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.61)
end

local WordInfoDialog = InputContainer:new{
    title = nil,
    book_title = nil,
    dates = nil,
    padding = Size.padding.large,
    margin = Size.margin.title,
    tap_close_callback = nil,
    dismissable = true, -- set to false if any button callback is required
}

function WordInfoDialog:init()
    if self.dismissable then
        if Device:hasKeys() then
            local close_keys = Device:hasFewKeys() and { "Back", "Left" } or Device.input.group.Back
            self.key_events = {
                Close = { { close_keys }, doc = "close button dialog" }
            }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0,
                        y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end
    local width = getDialogWidth()
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{
            FrameContainer:new{
                VerticalGroup:new{
                    align = "center",
                    FrameContainer:new{
                        padding =self.padding,
                        margin = self.margin,
                        bordersize = 0,
                        VerticalGroup:new {
                            align = "left",
                            TextWidget:new{
                                text = self.title,
                                width = width,
                                face = word_face,
                                bold = true,
                                alignment = self.title_align or "left",
                            },
                            TextBoxWidget:new{
                                text = self.book_title,
                                width = width,
                                face = subtitle_italic_face,
                                fgcolor = Blitbuffer.Color8(0x88),
                                alignment = self.title_align or "left",
                            },
                            VerticalSpan:new{width= Size.padding.default},
                            TextBoxWidget:new{
                                text = self.dates,
                                width = width,
                                face = subtitle_face,
                                alignment = self.title_align or "left",
                            },
                        }
                        
                    },
                    -- VerticalSpan:new{ width = Size.padding.default },
                    LineWidget:new{
                        background = Blitbuffer.COLOR_GRAY,
                        dimen = Geom:new{
                            w = width + self.padding + self.margin,
                            h = Screen:scaleBySize(2),
                        }
                    },
                    self.button,
                },
                background = Blitbuffer.COLOR_WHITE,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = Size.padding.button,
                padding_bottom = 0, -- no padding below buttontable
            }
        }
    }
end

function WordInfoDialog:setTitle(title)
    self.title = title
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
end

function WordInfoDialog:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self[1][1].dimen
    end)
end

function WordInfoDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function WordInfoDialog:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function WordInfoDialog:onClose()
    self:onTapClose()
    return true
end

function WordInfoDialog:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen -- FrameContainer
end


local review_button_width = Screen:scaleBySize(95)
local ellipsis_button_width = Screen:scaleBySize(34)
local star_width = Screen:scaleBySize(25)

local VocabItemWidget = InputContainer:new{
    face = Font:getFace("smallinfofont"),
    width = nil,
    height = nil,
    show_parent = nil,
    item = nil
}

-- [[
    -- item: {
    --     reviewable: BOOL,
    --     checked_func: Block,
    --     review_count: interger,
    --     word: Text
    --     book_title: TEXT
    --     create_time: Integer
    --     review_time: Integer
    --     due_time: Integer,
    --     got_it_callback: function
    --     remove_callback: function
    --     is_dim: BOOL
    -- } 
--]]

local point_widget = TextWidget:new{
    text = " • ",
    bold = true,
    face = Font:getFace("cfont", 24),
    fgcolor = Blitbuffer.Color8(0x66)
}

local point_widget_height = point_widget:getSize().h
local point_widget_width = point_widget:getSize().w
local word_height = TextWidget:new{text = " ", face = word_face}:getSize().h
local subtitle_height = TextWidget:new{text = " ", face = subtitle_face}:getSize().h


function VocabItemWidget:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
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

    self.v_spacer = VerticalSpan:new{width = (self.height - word_height - subtitle_height)/2}
    self.point_v_spacer = VerticalSpan:new{width = (self.v_spacer.width + word_height/2) - point_widget_height/2 + Screen:scaleBySize(1) }
    self.margin_span = HorizontalSpan:new{ width = Size.padding.large }
    self:initItemWidget()
end

function VocabItemWidget:initItemWidget()

    local more_button
    if self .item.review_count < 5 then
        more_button = Button:new{
            text = "⋮",
            padding = Size.padding.button,
            callback = function() self:showMore() end,
            width = ellipsis_button_width,
            bordersize = 0
        } 
        -- more_button.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
    else 
        more_button = Button:new{
            icon = "exit",
            icon_width = star_width,
            icon_height = star_width,
            bordersize = 0,
            radius = 0,
            padding = (ellipsis_button_width - star_width)/2,
            callback = function() 
                self:remover()
            end
        }
        -- more_button.label_widget.alpha = true
    end
    
    
    local right_side_width
    local right_widget
    if self .item.reviewable then
        right_side_width = review_button_width * 2 + Size.padding.large * 2 + ellipsis_button_width
        
        local forgot_button = Button:new{
            text = _("Forgot"),
            callback = nil,
            background = Blitbuffer.COLOR_DARK_GRAY,
            radius = 5,
            width = review_button_width,
            bordersize = 0,
            callback = function() 
                self:onForgot()
            end,
        }
        forgot_button.label_widget.fgcolor = Blitbuffer.COLOR_WHITE
    
        local got_it_button = Button:new{
            text = _("Got it"),
            callback = function() 
                self:onGotIt()
            end,
            background = Blitbuffer.COLOR_DARK_GRAY,
            radius = 5,
            width = review_button_width,
            bordersize = 0
        }
        got_it_button.label_widget.fgcolor = Blitbuffer.COLOR_WHITE

        right_widget = HorizontalGroup:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.margin_span,
            forgot_button,
            self.margin_span,
            got_it_button,
            more_button,
        }
    else
        right_side_width =  Size.padding.large * 3 + self .item.review_count * star_width

        if self .item.review_count > 0 then
            local star = Button:new{
                icon = "check",
                icon_width = star_width,
                icon_height = star_width,
                bordersize = 0,
                radius = 0,
                margin = 0,
                enabled = false,
            }
            

            right_widget = HorizontalGroup:new {
                dimen = Geom:new{w=0, h = self.height}
            }
            for i=1, self .item.review_count, 1 do
                table.insert(right_widget, star)
            end
        else
            right_widget = HorizontalGroup:new{
                dimen = Geom:new{w=0, h = self.height},
                 HorizontalSpan:new {width = Size.padding.default }
            }
        end
        table.insert(right_widget, self.margin_span)
        table.insert(right_widget, more_button)
    end

    local text_max_width = self.width - point_widget_width - right_side_width

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        focusable = true,
        focus_border_size = Size.border.thin,
        HorizontalGroup:new{
            dimen = Geom:new{
                w = self.width,
                h = self.height,
            },
            HorizontalGroup:new{
                dimen = Geom:new{
                    w = self.width - right_side_width,
                    h = self.height,
                },
                VerticalGroup:new{
                    dimen = Geom:new{w = point_widget_width, h = self.height},
                    self.point_v_spacer,
                    point_widget,
                    VerticalSpan:new { width = self.height - point_widget_height - self.point_v_spacer.width}
                },
                VerticalGroup:new{
                    dimen = Geom:new{
                        w = text_max_width,
                        h = self.height,
                    },
                    self.v_spacer,
                    LeftContainer:new{
                        dimen = Geom:new{w = text_max_width, h = word_height},
                        TextWidget:new{
                            text = self .item.word,
                            face = word_face,
                            bold = true,
                            fgcolor = self .item.is_dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
                        }
                    },
                    LeftContainer:new{
                        dimen = Geom:new{w = text_max_width, h = self.height - word_height - self.v_spacer.width*2.2},
                        HorizontalGroup:new{
                            TextWidget:new{
                                text = self:getTimeSinceDue() .. "From " ,
                                face = subtitle_face,
                                max_width = text_max_width,
                                fgcolor = Blitbuffer.Color8(0x88)
                            },
                            TextWidget:new{
                                text = self .item.book_title,
                                face = subtitle_italic_face,
                                max_width = text_max_width,
                                fgcolor = Blitbuffer.Color8(0x88)
                            }
                        }
                    },
                    self.v_spacer
                }

            },
            RightContainer:new{
                dimen = Geom:new{ w = right_side_width+Size.padding.default, h = self.height},
                right_widget
            }
        },
    }
    self[1].invert = self.invert
end

function VocabItemWidget:getTimeSinceDue()
    if self .item.review_count >= 8 then return "" end

    local elapsed = os.time() - self .item.due_time
    local abs = math.abs(elapsed)
    local readable_time
    if abs < 60 then
        readable_time = "1m"
    elseif abs < 3600 then
        readable_time = string.format("%dm", math.ceil(abs/60))
    elseif abs < 3600 * 24 then
        readable_time = string.format("%dh", math.ceil(abs/3600))
    else
        readable_time = string.format("%dd", math.ceil(abs/3600/24))
    end

    if elapsed < 0 then
        return " " .. readable_time .. " | " --hourglass
    else
        return readable_time .. " | "
    end
end

function VocabItemWidget:remover()
    self .item.remove_callback(self .item)
    self.show_parent:removeAt(self.index)
end

function VocabItemWidget:removeAndClose()
    self:remover()
    UIManager:close(self.dialogue)
end

function VocabItemWidget:showMore()
    local dialogue = WordInfoDialog:new{
        title = self .item.word,
        book_title = self .item.book_title,
        dates = _("Added on ") .. os.date("%Y-%m-%d", self .item.create_time) .. " | " ..
        _("Review scheduled at ") .. os.date("%Y-%m-%d %H:%M", self .item.due_time),
        button = Button:new{
            text = _("Remove Word"),
            bordersize = 0,
            show_parent = dialogue,
            width = getDialogWidth(),
            padding = Size.padding.default
        }
    }

    

    dialogue.button.callback = function() 
        self:remover()
        UIManager:close(dialogue)
    end,

    UIManager:show(dialogue)
end

function VocabItemWidget:onTap(_, ges)
    if self .item.callback then
        self .item.callback(self .item)
    elseif self.show_parent.marked == self.index then
        self.show_parent.marked = 0
    else
        self.show_parent.marked = self.index
    end
    -- self.show_parent:_populateItems()
    return true
end

function VocabItemWidget:onHold()
    if self .item.callback then
        self .item.callback(self .item)
        -- self.show_parent:_populateItems()
    end
    return true
end

function VocabItemWidget:onGotIt()
    self .item.got_it_callback(self .item)
    self .item.is_dim = true
    self:initItemWidget()
    UIManager:setDirty(self.show_parent, function()
    return "ui", self[1].dimen end) 
end

function VocabItemWidget:onForgot()
    self .item.forgot_callback(self .item)
    self .item.is_dim = false
    self:initItemWidget()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self[1].dimen end) 
    if self .item.callback then
        self .item.callback(self .item.word) 
    end
end
------- 


local VocabularyBuilderWidget = FocusManager:new{
    title = "",
    width = nil,
    height = nil,
    -- index for the first item to show
    show_page = 1,
    -- table of items to sort
    item_table = nil, -- mandatory (array)
    callback = nil,
}

function VocabularyBuilderWidget:init()
    self.layout = {}
    -- no item is selected on start
    self.marked = 0

    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back }, doc = "close dialog" }
        self.key_events.NextPage = { { Device.input.group.PgFwd}, doc = "next page"}
        self.key_events.PrevPage = { { Device.input.group.PgBack}, doc = "prev page"}
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
    self.footer_center_width = math.floor(self.width_widget * 32 / 100)
    self.footer_button_width = math.floor(self.width_widget * 12 / 100)
    self.item_height = Screen:scaleBySize(72)
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
        self.footer_first_up,
        self.footer_left,
        self.footer_page,
        self.footer_right,
        self.footer_last_down,
    }

    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.item_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_LIGHT_GRAY,
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
        align = "center",
        title_face = Font:getFace("smallinfofontbold"),
        bottom_line_color = Blitbuffer.COLOR_LIGHT_GRAY,
        with_bottom_line = true,
        bottom_line_h_padding = padding,
        title = self.title,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    -- self.title_bar.title_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
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

function VocabularyBuilderWidget:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        if self.marked > 0 then
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        end
        self:_populateItems()
    end
end

function VocabularyBuilderWidget:prevPage()
    local new_page = math.max(self.show_page-1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        if self.marked > 0 then
            self:moveItem(self.items_per_page * (self.show_page - 1) + 1 - self.marked)
        end
        self:_populateItems()
    end
end

function VocabularyBuilderWidget:goToPage(page)
    self.show_page = page
    self:_populateItems()
end

function VocabularyBuilderWidget:moveItem(diff)
    local move_to = self.marked + diff
    if move_to > 0 and move_to <= #self.item_table then

        table.insert(self.item_table, move_to, table.remove(self.item_table, self.marked))
        self.show_page = math.ceil(move_to / self.items_per_page)
        self.marked = move_to
        self:_populateItems()
    end
end

function VocabularyBuilderWidget:removeAt(index)
    logger.err("------------- index", index, self.item_table)
    if index > #self.item_table then return end
    table.remove(self.item_table, index)
    self.show_page = math.ceil(math.min(index, #self.item_table) / self.items_per_page)
    self:_populateItems()
end

-- make sure self.item_margin and self.item_height are set before calling this
function VocabularyBuilderWidget:_populateItems()
    self.main_content:clear()
    self.layout = { self.layout[#self.layout] } -- keep footer
    local idx_offset = (self.show_page - 1) * self.items_per_page
    local page_last
    if idx_offset + self.items_per_page <= #self.item_table then
        page_last = idx_offset + self.items_per_page
    else
        page_last = #self.item_table
    end

    if self.select_items_callback then
        self.select_items_callback(self.item_table ,idx_offset, page_last)
    end

    for idx = idx_offset + 1, page_last do
        table.insert(self.main_content, VerticalSpan:new{ width = self.item_margin })
        local invert_status = false
        if idx == self.marked then
            invert_status = true
        end
        if #self.item_table == 0 or not self.item_table[idx].word then break end
        local item = VocabItemWidget:new{
            height = self.item_height,
            width = self.item_width,
            item = self.item_table[idx],
            invert = invert_status,
            index = idx,
            show_parent = self,
        }
        table.insert(self.layout, #self.layout, {item})
        table.insert(
            self.main_content,
            item
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
    if BD.mirroredUILayout() then
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    if self.marked > 0 then
        -- self.footer_cancel:setIcon("cancel", self.footer_button_width)
        -- self.footer_cancel.callback = function() self:onCancel() end
        self.footer_first_up:setIcon("move.up", self.footer_button_width)
        self.footer_last_down:setIcon("move.down", self.footer_button_width)
    else
        -- self.footer_cancel:setIcon("exit", self.footer_button_width)
        -- self.footer_cancel.callback = function() self:onClose() end
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

function VocabularyBuilderWidget:gotItFromDict(word) 
    for i = 1, #self.main_content, 1 do
        if self.main_content[i].item and self.main_content[i].item.word == word then
            self.main_content[i]:onGotIt()
            return
        end
    end
end

function VocabularyBuilderWidget:forgotFromDict(word)
    for i = 1, #self.main_content, 1 do
        if self.main_content[i].item and self.main_content[i].item.word == word then
            self.main_content[i]:onForgot()
            return
        end
    end
end

function VocabularyBuilderWidget:onNextPage()
    self:nextPage()
    return true
end

function VocabularyBuilderWidget:onPrevPage()
    self:prevPage()
    return true
end

function VocabularyBuilderWidget:onSwipe(arg, ges_ev)
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

function VocabularyBuilderWidget:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
    return true
end

function VocabularyBuilderWidget:onCancel()
    self.marked = 0

    self:goToPage(self.show_page)
    return true
end

function VocabularyBuilderWidget:onReturn()
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
    self:goToPage(self.show_page)
    return true
end

return VocabularyBuilderWidget

