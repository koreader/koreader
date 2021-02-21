--[[--
Button with a big icon image! Designed for touch devices.
--]]

local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local IconWidget = require("ui/widget/iconwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local IconButton = InputContainer:new{
    icon = "notice-warning",
    dimen = nil,
    -- show_parent is used for UIManager:setDirty, so we can trigger repaint
    show_parent = nil,
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    padding = 0,
    padding_top = nil,
    padding_right = nil,
    padding_bottom = nil,
    padding_left = nil,
    enabled = true,
    callback = nil,
}

function IconButton:init()
    self.image = IconWidget:new{
        icon = self.icon,
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
    if not self.callback then return end
    if G_reader_settings:isFalse("flash_ui") then
        self.callback()
    else
        -- c.f., ui/widget/button for more gnarly details about the implementation, but the flow of the flash_ui codepath essentially goes like this:
        -- 1. Paint the highlight
        -- 2. Refresh the highlighted item (so we can see the highlight)
        -- 3. Paint the unhighlight
        -- 4. Do NOT refresh the highlighted item, but enqueue a refresh request
        -- 5. Run the callback
        -- 6. Explicitly drain the paint & refresh queues; i.e., refresh (so we get to see both the callback results, and the unhighlight).

        -- Highlight
        --
        self.image.invert = true
        UIManager:widgetInvert(self.image, self.dimen.x + self.padding_left, self.dimen.y + self.padding_top)
        UIManager:setDirty(nil, "fast", self.dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self.image.invert = false
        UIManager:widgetInvert(self.image, self.dimen.x + self.padding_left, self.dimen.y + self.padding_top)

        -- Callback
        --
        self.callback()

        -- NOTE: plugins/coverbrowser.koplugin/covermenu (ab)uses UIManager:clearRenderStack,
        --       so we need to enqueue the actual refresh request for the unhighlight post-callback,
        --       otherwise, it's lost.
        --       This changes nothing in practice, since we follow by explicitly requesting to drain the refresh queue ;).
        UIManager:setDirty(nil, "fast", self.dimen)

        UIManager:forceRePaint()
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
    elseif self.hold_callback == nil then return end
    return true
end

function IconButton:onFocus()
    --quick and dirty, need better way to show focus
    self.image.invert = true
    return true
end

function IconButton:onUnfocus()
    self.image.invert = false
    return true
end

function IconButton:onTapSelect()
    self:onTapIconButton()
end

return IconButton
