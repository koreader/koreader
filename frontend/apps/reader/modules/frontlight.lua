local InputContainer = require("ui/widget/container/inputcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local CloseButton = require("ui/widget/closebutton")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local GestureRange = require("ui/gesturerange")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")

local ReaderFrontLight = InputContainer:new{
    title_face = Font:getFace("tfont", 22),
    width = nil,
    height = nil,
    fl_cur = 0,
    fl_min = 0,
    fl_max = 10,
}

function ReaderFrontLight:init()
    self.medium_font_face = Font:getFace("ffont", 20)
    self.light_bar = {}
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    self.width = self.screen_width * 0.95
    local powerd = Device:getPowerDevice()
    self.fl_cur = powerd.fl_intensity
    self.fl_min = powerd.fl_min
    self.fl_max = powerd.fl_max
    local steps_fl = self.fl_max - self.fl_min + 1
    self.one_step = math.ceil(steps_fl  / 25 )
    self.steps = math.ceil(steps_fl / self.one_step)
    if (self.steps - 1) * self.one_step < self.fl_max - self.fl_min then
        self.steps = self.steps + 1
    end
    self.steps = math.min(self.steps , steps_fl)
    self.fl_cur = math.floor(self.fl_cur / self.one_step)
    -- button width to fit screen size
    self.button_width = math.floor(self.screen_width * 0.9 / self.steps) - 12

    self.fl_prog_button = Button:new{
        text = "",
        bordersize = 3,
        radius = 0,
        margin = 1,
        enabled = true,
        width = self.button_width,
        show_parent = self,
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close frontlight" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapCloseFL = {
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
    self:update()
end

function ReaderFrontLight:generateProgressGroup(width, height, fl_level)
    self.fl_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    self:setProgress(fl_level)
    return self.fl_container
end

function ReaderFrontLight:setProgress(num)
    --clear previous data
    self.fl_container:clear()
    local button_group = HorizontalGroup:new{ align = "center" }
    local fl_group = HorizontalGroup:new{ align = "center" }
    local vertical_group = VerticalGroup:new{ align = "center" }
    local set_fl
    if num then
        self.fl_cur = num * self.one_step + self.fl_min
        set_fl = math.min(self.fl_cur, self.fl_max)
        Device:getPowerDevice():setIntensity(set_fl)

        for i = 0, num do
            table.insert(fl_group, self.fl_prog_button:new{
                text= "",
                margin = 1,
                preselect = true,
                width = self.button_width,
                callback = function() self:setProgress(i) end
            })
        end
    else
        num = 0
    end

    for i = num + 1, self.steps -1 do
        table.insert(fl_group, self.fl_prog_button:new{
            callback = function() self:setProgress(i) end
        })
    end
    local button_min = Button:new{
        text = "Min",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(0) end,
    }
    local button_max = Button:new{
        text = "Max",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(math.floor(self.fl_max / self.one_step)) end,
    }
    local item_level = TextBoxWidget:new{
        text = set_fl,
        width = self.screen_width * 0.95 - 1.25 * button_max.width - 1.25 * button_min.width,
        face = self.medium_font_face,
        alignment = "center",
    }
    local button_table = HorizontalGroup:new{
        align = "center",
        button_min,
        item_level,
        button_max,
    }
    table.insert(button_group, button_table)
    table.insert(vertical_group,fl_group)
    table.insert(vertical_group,button_group)
    table.insert(self.fl_container, vertical_group)

    UIManager:setDirty("all", "ui")
    return true
end

function ReaderFrontLight:update()
    -- header
    self.light_title = FrameContainer:new{
        padding = Screen:scaleBySize(5),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        TextWidget:new{
            text = _("Frontlight"),
            face = self.title_face,
            bold = true,
            width = self.screen_width * 0.95,
        },
    }
    local light_level = FrameContainer:new{
        padding = Screen:scaleBySize(2),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        self:generateProgressGroup(self.screen_width * 0.95, self.screen_height * 0.15, self.fl_cur)
    }
    local light_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Screen:scaleBySize(2),
        }
    }
    self.light_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.light_title:getSize().h
        },
        self.light_title,
        CloseButton:new{ window = self, },
    }
    self.light_frame = FrameContainer:new{
        radius = 5,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.light_bar,
            light_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = light_line:getSize().w,
                    h = light_level:getSize().h,
                },
                light_level,
            },
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
            self.light_frame,
        }
    }
end

function ReaderFrontLight:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.light_frame.dimen
    end)
    return true
end

function ReaderFrontLight:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.light_frame.dimen
    end)
    return true
end

function ReaderFrontLight:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function ReaderFrontLight:onTapCloseFL(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.light_frame.dimen) then
        self:onClose()
    end
    return true
end

function ReaderFrontLight:onClose()
    UIManager:close(self)
    return true
end

return ReaderFrontLight
