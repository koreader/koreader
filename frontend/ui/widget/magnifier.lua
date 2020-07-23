--[[--
Widget that displays zoomed pic.

It vanishes on key press or after a given timeout.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local magnifier
    magnifier = Magnifier:new{
        image = Image,
        height = Screen:scaleBySize(400),
        width = Screen:scaleBySize(400),
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(magnifier)
    magnifier:onShowKeyboard()
]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Topcontainer = require("ui/widget/container/topcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local TimeVal = require("ui/timeval")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template



local Magnifier = InputContainer:new{
    image = nil,
    timeout = nil, -- in seconds
    alpha = false, -- does that icon have an alpha channel?
    dismiss_callback = function() end,
    zoom = nil,
    x_ratio = nil,
    y_ratio = nil

}

function Magnifier:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = "close dialog" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
   
    
    local image_widget
    image_widget = ImageWidget:new{
        image = self.image,
        width = Screen:getWidth(),
        height = Screen:scaleBySize(200),
        alpha = self.alpha,
        scale_for_dpi = true,
        scale_factor = self.zoom,
        center_x_ratio = self.x_ratio,
        center_y_ratio = self.y_ratio,

    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        image_widget
       
    }
    self.movable = MovableContainer:new{
        frame,
    }
    if self.x_ratio < 0.5 then
        
        self[1] = BottomContainer:new{
            dimen = Screen:getSize(),
            self.movable,
        }
    else
        self[1] = Topcontainer:new{
            dimen = Screen:getSize(),
            self.movable,
        } 
    end
end

function Magnifier:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function Magnifier:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function Magnifier:onAnyKeyPressed()
    -- triggered by our defined key events
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end

function Magnifier:onTapClose()
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end


return Magnifier
