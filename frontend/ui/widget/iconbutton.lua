--[[--
Button with a big icon image! Designed for touch devices.
--]]

local InputContainer = require("ui/widget/container/inputcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")

local IconButton = InputContainer:new{
    icon_file = "resources/info-confirm.png",
    dimen = nil,
    -- show_parent is used for UIManager:setDirty, so we can trigger repaint
    show_parent = nil,
    scale_for_dpi = true,
    callback = function() end,
}

function IconButton:init()
    self.image = ImageWidget:new{
        file = self.icon_file,
        scale_for_dpi = self.scale_for_dpi,
    }

    self.show_parent = self.show_parent or self
    self.dimen = self.image:getSize()

    self:initGesListener()

    self[1] = self.image
end

function IconButton:initGesListener()
    self.ges_events = {
        TapClickButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        },
    }
end

function IconButton:onTapClickButton()
    UIManager:scheduleIn(0.0, function()
        self.image.invert = true
        UIManager:setDirty(self.show_parent, function()
            return "ui", self[1].dimen
        end)
    end)
    -- make sure button reacts before doing callback
    UIManager:scheduleIn(0.1, function()
        self.callback()
        self.image.invert = false
        UIManager:setDirty(self.show_parent, function()
            return "ui", self[1].dimen
        end)
    end)
    return true
end

function IconButton:onSetDimensions(new_dimen)
    self.dimen = new_dimen
end

return IconButton
