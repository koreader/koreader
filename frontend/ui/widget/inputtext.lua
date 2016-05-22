local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local util = require("util")
local Keyboard

local InputText = InputContainer:new{
    text = "",
    hint = "demo hint",
    charlist = nil, -- table to store input string
    charpos = nil, -- position to insert a new char, or the position of the cursor
    input_type = nil,
    text_type = nil,
    text_widget = nil, -- Text Widget for cursor movement

    width = nil,
    height = nil,
    face = Font:getFace("cfont", 22),

    padding = 5,
    margin = 5,
    bordersize = 2,

    parent = nil, -- parent dialog that will be set dirty
    scroll = false,
    focused = true,
}

-- only use PhysicalKeyboard if the device does not have touch screen
if Device.isTouchDevice() then
    Keyboard = require("ui/widget/virtualkeyboard")
    function InputText:initEventListener()
        self.ges_events = {
            TapTextBox = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen
                }
            }
        }
    end

    function InputText:onTapTextBox(arg, ges)
        if self.parent.onSwitchFocus then
            self.parent:onSwitchFocus(self)
        else
            local x = ges.pos.x - self.dimen.x - self.bordersize - self.padding
            local y = ges.pos.y - self.dimen.y - self.bordersize - self.padding
            if x > 0 and y > 0 then
                self.charpos = self.text_widget:moveCursor(x, y)
                UIManager:setDirty(self.parent, function()
                    return "ui", self[1].dimen
                end)
            end
        end
    end
else
    Keyboard = require("ui/widget/physicalkeyboard")
    function InputText:initEventListener() end
end

function InputText:init()
    self:initTextBox(self.text)
    self:initKeyboard()
    self:initEventListener()
end

function InputText:initTextBox(text)
    self.text = text
    self.charlist = util.splitToChars(text)
    if self.charpos == nil then
        self.charpos = #self.charlist + 1
    end
    local fgcolor = Blitbuffer.gray(self.text == "" and 0.5 or 1.0)

    local show_text = self.text
    if self.text_type == "password" and show_text ~= "" then
        show_text = self.text:gsub("(.-).", function() return "*" end)
        show_text = show_text:gsub("(.)$", function() return self.text:sub(-1) end)
    end
    if self.scroll then
        self.text_widget = ScrollTextWidget:new{
            text = show_text,
            charlist = self.charlist,
            charpos = self.charpos,
            editable = true,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
        }
    else
        self.text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = self.charlist,
            charpos = self.charpos,
            editable = true,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
        }
    end
    self[1] = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = self.margin,
        color = Blitbuffer.gray(self.focused and 1.0 or 0.5),
        self.text_widget,
    }
    self.dimen = self[1]:getSize()
    -- FIXME: self.parent is not always in the widget statck (BookStatusWidget)
    UIManager:setDirty(self.parent, function()
        return "ui", self[1].dimen
    end)
end

function InputText:initKeyboard()
    local keyboard_layout = 2
    if self.input_type == "number" then
        keyboard_layout = 3
    end
    self.keyboard = Keyboard:new{
        layout = keyboard_layout,
        inputbox = self,
        width = Screen:getWidth(),
    }
end

function InputText:unfocus()
    self.focused = false
    self[1].color = Blitbuffer.gray(0.5)
end

function InputText:focus()
    self.focused = true
    self[1].color = Blitbuffer.COLOR_BLACK
end

function InputText:onShowKeyboard()
    UIManager:show(self.keyboard)
end

function InputText:onCloseKeyboard()
    UIManager:close(self.keyboard)
end

function InputText:getKeyboardDimen()
    return self.keyboard.dimen
end

function InputText:addChar(char)
    if self.enter_callback and char == '\n' then
        UIManager:scheduleIn(0.3, function() self.enter_callback() end)
        return
    end
    table.insert(self.charlist, self.charpos, char)
    self.charpos = self.charpos + 1
    self:initTextBox(table.concat(self.charlist))
end

function InputText:delChar()
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    table.remove(self.charlist, self.charpos)
    self:initTextBox(table.concat(self.charlist))
end

function InputText:clear()
    self:initTextBox("")
    UIManager:setDirty(self.parent, function()
        return "ui", self[1][1].dimen
    end)
end

function InputText:getText()
    return self.text
end

function InputText:setText(text)
    self:initTextBox(text)
    UIManager:setDirty(self.parent, function()
        return "partial", self[1].dimen
    end)
end

return InputText
