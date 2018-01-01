--[[--
Button with a big icon image! Designed for touch devices.
--]]

local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local IconButton = InputContainer:new{
    icon_file = "resources/info-confirm.png",
    dimen = nil,
    -- show_parent is used for UIManager:setDirty, so we can trigger repaint
    show_parent = nil,
    width = nil,
    height = nil,
    scale_for_dpi = true,
    padding = 0,
    padding_top = nil,
    padding_right = nil,
    padding_bottom = nil,
    padding_left = nil,
    enabled = true,
    callback = nil,
}

function IconButton:init()
    self.image = ImageWidget:new{
        file = self.icon_file,
        scale_for_dpi = self.scale_for_dpi,
        width = self.width,
        height = self.height,
    }

    self.show_parent = self.show_parent or self

    self.horizontal_group = HorizontalGroup:new{}
    table.insert(self.horizontal_group, HorizontalSpan:new{})
    table.insert(self.horizontal_group, self.image)
    table.insert(self.horizontal_group, HorizontalSpan:new{})

    self.button = VerticalGroup:new{}
    table.insert(self.button, VerticalSpan:new{})
    table.insert(self.button, self.horizontal_group)
    table.insert(self.button, VerticalSpan:new{})

    self[1] = self.button
    self:update()
end

function IconButton:update()
    if not self.padding_top then self.padding_top = self.padding end
    if not self.padding_right then self.padding_right = self.padding end
    if not self.padding_bottom then self.padding_bottom = self.padding end
    if not self.padding_left then self.padding_left = self.padding end

    self.horizontal_group[1].width = self.padding_left
    self.horizontal_group[3].width = self.padding_right
    self.dimen = self.image:getSize()
    self.dimen.w = self.dimen.w + self.padding_left+self.padding_right

    self.button[1].width = self.padding_top
    self.button[3].width = self.padding_bottom
    self.dimen.h = self.dimen.h + self.padding_top+self.padding_bottom
    self:initGesListener()
end

function IconButton:initGesListener()
    if Device:isTouchDevice() then
        self.ges_events = {
            TapIconButton = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Tap IconButton",
            },
            HoldIconButton = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold IconButton",
            }
        }
    end
end

function IconButton:onTapIconButton()
    if G_reader_settings:isFalse("flash_ui") then
        self.callback()
    else
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
    end
    return true
end

function IconButton:onHoldIconButton()
    if self.enabled and self.hold_callback then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func())
    end
    return true
end

return IconButton
