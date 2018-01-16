local Blitbuffer = require("ffi/blitbuffer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local Keyboard

local InputText = InputContainer:new{
    text = "",
    hint = "demo hint",
    charlist = nil, -- table to store input string
    charpos = nil, -- position to insert a new char, or the position of the cursor
    input_type = nil,
    text_type = nil,
    text_widget = nil, -- Text Widget for cursor movement
    show_password_toggle = true,

    width = nil,
    height = nil,
    face = Font:getFace("smallinfofont"),

    padding = Screen:scaleBySize(5),
    margin = Screen:scaleBySize(5),
    bordersize = Screen:scaleBySize(2),

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
        end
        local x = ges.pos.x - self._frame_textwidget.dimen.x - self.bordersize - self.padding
        local y = ges.pos.y - self._frame_textwidget.dimen.y - self.bordersize - self.padding
        if x > 0 and y > 0 then
            self.charpos = self.text_widget:moveCursor(x, y)
            UIManager:setDirty(self.parent, function()
                return "ui", self.dimen
            end)
        end
    end
else
    Keyboard = require("ui/widget/physicalkeyboard")
    function InputText:initEventListener() end
end

function InputText:init()
    self:initTextBox(self.text)
    if self.readonly ~= true then
        self:initKeyboard()
        self:initEventListener()
    end
end

function InputText:initTextBox(text, char_added, is_password_type)
    self.text = text
    if self.text_type == "password" then
        is_password_type = true
    end
    local fgcolor
    local show_charlist
    local show_text = text
    if show_text == "" or show_text == nil then
        -- no preset value, use hint text if set
        show_text = self.hint
        fgcolor = Blitbuffer.COLOR_GREY
        self.charlist = {}
        self.charpos = 1
    else
        fgcolor = Blitbuffer.COLOR_BLACK
        if self.text_type == "password" then
            show_text = self.text:gsub(
                "(.-).", function() return "*" end)
            if char_added then
                show_text = show_text:gsub(
                    "(.)$", function() return self.text:sub(-1) end)
            end
        end
        self.charlist = util.splitToChars(text)
        if self.charpos == nil then
            self.charpos = #self.charlist + 1
        end
    end
    if is_password_type and self.show_password_toggle then
        self._check_button = self._check_button or CheckButton:new{
            text = _("Show password"),
            callback = function()
                if self.text_type == "text" then
                    self.text_type = "password"
                    self._check_button:unCheck()
                else
                    self.text_type = "text"
                    self._check_button:check()
                end
                self:setText(self:getText(), is_password_type)
            end,

            width = self.width,
            height = self.height,

            padding = self.padding,
            margin = self.margin,
            bordersize = self.bordersize,
        }
        self._password_toggle = FrameContainer:new{
            bordersize = 0,
            padding = self.padding,
            margin = self.margin,
            self._check_button,
        }
    else
        self._password_toggle = nil
    end
    show_charlist = util.splitToChars(show_text)
    if self.scroll then
        self.text_widget = ScrollTextWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
            dialog = self.parent,
        }
    else
        self.text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
        }
    end
    self._frame_textwidget = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = self.margin,
        color = self.focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GREY,
        self.text_widget,
    }
    self._verticalgroup = VerticalGroup:new{
        align = "left",
        self._frame_textwidget,
        self._password_toggle,
    }
    self._frame = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        self._verticalgroup,
    }
    self[1] = self._frame
    self.dimen = self._frame:getSize()
    -- FIXME: self.parent is not always in the widget stack (BookStatusWidget)
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
    end)
end

function InputText:initKeyboard()
    local keyboard_layout = 2
    if self.input_type == "number" then
        keyboard_layout = 4
    end
    self.keyboard = Keyboard:new{
        layout = keyboard_layout,
        inputbox = self,
        width = Screen:getWidth(),
    }
end

function InputText:unfocus()
    self.focused = false
    self.text_widget:unfocus()
    self[1].color = Blitbuffer.COLOR_GREY
end

function InputText:focus()
    self.focused = true
    self.text_widget:focus()
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
    self:initTextBox(table.concat(self.charlist), true)
end

function InputText:delChar()
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    table.remove(self.charlist, self.charpos)
    self:initTextBox(table.concat(self.charlist))
end

function InputText:leftChar()
    if self.charpos == 1 then return end
    self.charpos = self.charpos -1
    self:initTextBox(table.concat(self.charlist))
end

function InputText:rightChar()
    if self.charpos > #table.concat(self.charlist) then return end
    self.charpos = self.charpos +1
    self:initTextBox(table.concat(self.charlist))
end

function InputText:upLine()
    if self.text_widget.moveCursorUp then
        self.text_widget:moveCursorUp()
    end
end

function InputText:downLine()
    if self.text_widget.moveCursorDown then
        self.text_widget:moveCursorDown()
    end
end

function InputText:clear()
    self.charpos = nil
    self:initTextBox("")
    UIManager:setDirty(self.parent, function()
        return "ui", self[1][1].dimen
    end)
end

function InputText:getText()
    return self.text
end

function InputText:setText(text, is_password_type)
    self.charpos = nil
    self:initTextBox(text, nil, is_password_type)
    UIManager:setDirty(self.parent, function()
        return "partial", self[1].dimen
    end)
end

return InputText
