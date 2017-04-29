local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local SkimToWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
}

function SkimToWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = self.screen_width * 0.95
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close skimto page" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapProgress = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                },
            },
         }
    end
    if self.document.info.has_pages then
        self.dialog_title = _("Go to Page")
        self.curr_page = self.ui.paging.current_page
    else
        self.dialog_title = _("Go to Location")
        self.curr_page = self.document:getCurrentPage()
    end
    self.page_count = self.document:getPageCount()

    self.skimto_title = FrameContainer:new{
        padding = Screen:scaleBySize(5),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        TextWidget:new{
            text = self.dialog_title,
            face = self.title_face,
            bold = true,
            width = self.screen_width * 0.95,
        },
    }

    self.skimto_container = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width * 0.95, h = self.screen_height * 0.075 },
    }
    local progress_bar = ProgressWidget:new{
        width = self.screen_width * 0.9,
        height = Screen:scaleBySize(30),
        percentage = self.curr_page / self.page_count,
        ticks = nil,
        last = nil,
    }
    local vertical_group = VerticalGroup:new{ align = "center" }
    table.insert(vertical_group, progress_bar)
    table.insert(self.skimto_container, vertical_group)

    self.skimto_progress = FrameContainer:new{
        padding = Screen:scaleBySize(2),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        self.skimto_container
    }

    self.skimto_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Screen:scaleBySize(2),
        }
    }
    self.skimto_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.skimto_title:getSize().h
        },
        self.skimto_title,
        CloseButton:new{ window = self, },
    }
    self.button_minus = Button:new{
        text = "-1",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.16,
        show_parent = self,
        callback = function()
            self.curr_page = self.curr_page - 1
            self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
            self:update()
        end,
    }
    self.button_minus_ten = Button:new{
        text = "-10",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.16,
        show_parent = self,
        callback = function()
            self.curr_page = self.curr_page - 10
            self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
            self:update()
        end,
    }
    self.button_plus = Button:new{
        text = "+1",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.16,
        show_parent = self,
        callback = function()
            self.curr_page = self.curr_page + 1
            self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
            self:update()
        end,
    }
    self.button_plus_ten = Button:new{
        text = "+10",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.16,
        show_parent = self,
        callback = function()
            self.curr_page = self.curr_page + 10
            self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
            self:update()
        end,
    }
    local current_page_text = Button:new{
        text = self.curr_page,
        bordersize = 0,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.2,
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
    }

    local button_group_up = HorizontalGroup:new{ align = "center" }
    local button_table_up = HorizontalGroup:new{
        align = "center",
        self.button_minus,
        self.button_minus_ten,
        current_page_text,
        self.button_plus_ten,
        self.button_plus,
    }
    local vertical_group_control= VerticalGroup:new{ align = "center" }
    local padding_span = VerticalSpan:new{ width = self.screen_height * 0.01 }
    table.insert(button_group_up, button_table_up)
    table.insert(vertical_group_control,button_group_up)
    table.insert(vertical_group_control,padding_span)

    self.skimto_frame = FrameContainer:new{
        radius = 5,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.skimto_bar,
            self.skimto_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.skimto_line:getSize().w,
                    h = self.skimto_progress:getSize().h,
                },
                self.skimto_progress,
            },
            vertical_group_control
        }
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            padding = Screen:scaleBySize(5),
            self.skimto_frame,
        }
    }
end

function SkimToWidget:update()
    self.skimto_container:clear()
    UIManager:setDirty("all", "ui")
    if self.curr_page <= 0 then
        self.curr_page = 1
    end
    if self.curr_page > self.page_count then
        self.curr_page = self.page_count
    end
    local progress_bar = ProgressWidget:new{
        width = self.screen_width * 0.9,
        height = Screen:scaleBySize(30),
        percentage = self.curr_page / self.page_count,
        ticks = nil,
        last = nil,
    }
    local vertical_group = VerticalGroup:new{ align = "center" }
    table.insert(vertical_group, progress_bar)
    table.insert(self.skimto_container, vertical_group)

    self.skimto_progress = FrameContainer:new{
        padding = Screen:scaleBySize(2),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        self.skimto_container
    }
    local current_page_text = Button:new{
        text = self.curr_page,
        bordersize = 0,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.2,
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
    }

    local button_group_up = HorizontalGroup:new{ align = "center" }
    local button_table_up = HorizontalGroup:new{
        align = "center",
        self.button_minus,
        self.button_minus_ten,
        current_page_text,
        self.button_plus_ten,
        self.button_plus,
    }
    local vertical_group_control= VerticalGroup:new{ align = "center" }
    local padding_span = VerticalSpan:new{ width = self.screen_height * 0.01 }
    table.insert(button_group_up, button_table_up)
    table.insert(vertical_group_control,button_group_up)
    table.insert(vertical_group_control,padding_span)

    self.skimto_frame = FrameContainer:new{
        radius = 5,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.skimto_bar,
            self.skimto_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.skimto_line:getSize().w,
                    h = self.skimto_progress:getSize().h,
                },
                self.skimto_progress,
            },
            vertical_group_control
        }
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            padding = Screen:scaleBySize(5),
            self.skimto_frame,
        }
    }
end

function SkimToWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function SkimToWidget:onTapProgress(arg, ges_ev)
    if ges_ev.pos:intersectWith(self.skimto_progress.dimen) then
        local width = self.screen_width * 0.89
        local pos = ges_ev.pos.x - width * 0.05 - 3
        local perc = pos / width
        local page = math.floor(perc * self.page_count)
        self.ui:handleEvent(Event:new("GotoPage", page ))
        self.curr_page = page
        self:update()
    else
        self:onClose()
    end
    return true
end

function SkimToWidget:onClose()
    UIManager:close(self)
    return true
end

return SkimToWidget
