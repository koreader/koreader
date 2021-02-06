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
        self.image.invert = true
        -- For ConfigDialog icons, we can't avoid that initial repaint...
        UIManager:widgetInvert(self.image, self.dimen.x + self.padding_left, self.dimen.y + self.padding_top)
        UIManager:setDirty(nil, function()
            return "fast", self.dimen
        end)

        -- Force the repaint *now*, so we don't have to delay the callback to see the invert...
        UIManager:forceRePaint()
        self.callback()
        UIManager:forceRePaint()
        --UIManager:waitForVSync()

        self.image.invert = false
        -- If the callback closed our parent (which may not always be the top-level widget, or even *a* window-level widget), we're done
        local top_widget = UIManager:getTopWidget()
        print("IconButton", self, "top dimen:", top_widget.dimen)
        local sec_widget = UIManager:getSecondTopmostWidget()
        print("IconButton", self, "sec dimen:", sec_widget and sec_widget:getSize() or nil)
        print("IconButton", self, "parent, top, sec", self.show_parent, top_widget, top_widget.init and debug.getinfo(top_widget.init, "S").short_src or nil, sec_widget, sec_widget and sec_widget.init and debug.getinfo(sec_widget.init, "S").short_src or nil)
        if top_widget == self.show_parent or UIManager:isSubwidgetShown(self.show_parent) then
            -- If the callback popped up the VK, it prevents us from finessing this any further,
            -- because getPreviousRefreshRegion will return the VK's region,
            -- and it's impossible to get the actual geometry of *only* the dialog part of an InputDialog,
            -- making the same kind of getSecondTopmostWidget trickery as in Button useless,
            -- so repaint the whole stack instead.
            if top_widget == "VirtualKeyboard" then
                UIManager:waitForVSync()
                UIManager:setDirty(self.show_parent, function()
                    return "ui", self.dimen
                end)
                return true
            end

            -- If the callback popped up a modal above us, repaint the whole stack
            if top_widget ~= self.show_parent and top_widget.modal and self.dimen:intersectWith(UIManager:getPreviousRefreshRegion()) then
                UIManager:waitForVSync()
                UIManager:setDirty(self.show_parent, function()
                    return "ui", self.dimen
                end)
                return true
            end

            -- Otherwise, we can unhighlight it safely
            UIManager:widgetInvert(self.image, self.dimen.x + self.padding_left, self.dimen.y + self.padding_top)
            UIManager:setDirty(nil, function()
                return "fast", self.dimen
            end)
        else
            -- Callback closed our parent, we're done
            return true
        end
        --UIManager:forceRePaint()
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
