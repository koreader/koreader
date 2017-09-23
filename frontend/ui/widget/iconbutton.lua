--[[--
Button with a big icon image! Designed for touch devices.
--]]

local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")

local IconButton = InputContainer:new{
    icon_file = "resources/info-confirm.png",
    dimen = nil,
    -- show_parent is used for UIManager:setDirty, so we can trigger repaint
    show_parent = nil,
    width = nil,
    height = nil,
    scale_for_dpi = true,
    horizontal_padding = 0,
    callback = function() end,
}

function IconButton:init()
    self.image = ImageWidget:new{
        file = self.icon_file,
        scale_for_dpi = self.scale_for_dpi,
        width = self.width,
        height = self.height,
    }

    self.show_parent = self.show_parent or self

    self.button = HorizontalGroup:new{}
    table.insert(self.button, HorizontalSpan:new{})
    table.insert(self.button, self.image)
    table.insert(self.button, HorizontalSpan:new{})

    self[1] = self.button
    self:update()
end

function IconButton:update()
    self.button[1].width = self.horizontal_padding
    self.button[3].width = self.horizontal_padding
    self.dimen = self.image:getSize()
    self.dimen.w = self.dimen.w + 2*self.horizontal_padding
    self:initGesListener()
end

function IconButton:setHorizontalPadding(padding)
    self.horizontal_padding = padding
    self:update()
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
