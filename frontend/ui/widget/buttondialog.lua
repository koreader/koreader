--[[--
A button dialog widget that shows a grid of buttons.

    @usage
    local button_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = "First row, left side",
                    callback = function() end,
                    hold_callback = function() end
                },
                {
                    text = "First row, middle",
                    callback = function() end
                },
                {
                    text = "First row, right side",
                    callback = function() end
                }
            },
            {
                {
                    text = "Second row, full span",
                    callback = function() end
                }
            },
            {
                {
                    text = "Third row, left side",
                    callback = function() end
                },
                {
                    text = "Third row, right side",
                    callback = function() end
                }
            }
        }
    }
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = require("device").screen

local ButtonDialog = InputContainer:extend{
    buttons = nil,
    tap_close_callback = nil,
    alpha = nil, -- passed to MovableContainer
}

function ButtonDialog:init()
    if Device:hasKeys() then
        local close_keys = Device:hasFewKeys() and { "Back", "Left" } or Device.input.group.Back
        self.key_events = {
            Close = { { close_keys }, doc = "close button dialog" }
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
    self.movable = MovableContainer:new{
            alpha = self.alpha,
            FrameContainer:new{
                ButtonTable:new{
                    buttons = self.buttons,
                    show_parent = self,
                },
                background = Blitbuffer.COLOR_WHITE,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = Size.padding.button,
                -- No padding at top or bottom to make all buttons
                -- look the same size
                padding_top = 0,
                padding_bottom = 0,
            }
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
end

function ButtonDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ButtonDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "flashui", self.movable.dimen
    end)
end

function ButtonDialog:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialog:onClose()
    self:onTapClose()
    return true
end

function ButtonDialog:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self.movable.dimen
end

return ButtonDialog
