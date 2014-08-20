local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local Screen = require("ui/screen")
local Font = require("ui/font")
local DEBUG = require("dbg")
local util = require("ffi/util")

local InputText = InputContainer:new{
    text = "",
    hint = "demo hint",
    charlist = {}, -- table to store input string
    charpos = 1,
    input_type = nil,
    text_type = nil,

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

function InputText:init()
    self:StringToCharlist(self.text)
    self:initTextBox()
    self:initKeyboard()
    if Device:isTouchDevice() then
        self.ges_events = {
            TapTextBox = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen
                }
            }
        }
    end
end

function InputText:initTextBox()
    local bgcolor, fgcolor = 0.0, self.text == "" and 0.5 or 1.0

    local text_widget = nil
    local show_text = self.text
    if self.text_type == "password" and show_text ~= "" then
        show_text = self.text:gsub("(.-).", function() return "*" end)
        show_text = show_text:gsub("(.)$", function() return self.text:sub(-1) end)
    elseif show_text == "" then
        show_text = self.hint
    end
    if self.scroll then
        text_widget = ScrollTextWidget:new{
            text = show_text,
            face = self.face,
            bgcolor = bgcolor,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
        }
    else
        text_widget = TextBoxWidget:new{
            text = show_text,
            face = self.face,
            bgcolor = bgcolor,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
        }
    end
    self[1] = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = self.margin,
        color = self.focused and 15 or 8,
        text_widget,
    }
    self.dimen = self[1]:getSize()
end

function InputText:initKeyboard()
    local keyboard_layout = 2
    if self.input_type == "number" then
        keyboard_layout = 3
    end
    self.keyboard = VirtualKeyboard:new{
        layout = keyboard_layout,
        inputbox = self,
        width = Screen:getWidth(),
        height = math.max(Screen:getWidth(), Screen:getHeight())*0.33,
    }
end

function InputText:onTapTextBox()
    if self.parent.onSwitchFocus then
        self.parent:onSwitchFocus(self)
    end
end

function InputText:unfocus()
    self.focused = false
    self[1].color = 8
end

function InputText:focus()
    self.focused = true
    self[1].color = 15
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
    self.text = self:CharlistToString()
    self:initTextBox()
    UIManager:setDirty(self.parent, "partial")
end

function InputText:delChar()
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    table.remove(self.charlist, self.charpos)
    self.text = self:CharlistToString()
    self:initTextBox()
    UIManager:setDirty(self.parent, "partial")
end

function InputText:clear()
    self.text = ""
    self:initTextBox()
    UIManager:setDirty(self.parent, "partial")
end

function InputText:getText()
    return self.text
end

function InputText:setText(text)
    self:StringToCharlist(text)
    self:initTextBox()
    UIManager:setDirty(self.parent, "partial")
end

function InputText:StringToCharlist(text)
    if text == nil then return end
    -- clear
    self.charlist = {}
    self.charpos = 1
    local prevcharcode, charcode = 0
    for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
        charcode = util.utf8charcode(uchar)
        if prevcharcode then -- utf8
            self.charlist[#self.charlist+1] = uchar
        end
        prevcharcode = charcode
    end
    self.text = self:CharlistToString()
    self.charpos = #self.charlist+1
end

function InputText:CharlistToString()
    local s, i = ""
    for i=1, #self.charlist do
        s = s .. self.charlist[i]
    end
    return s
end

return InputText
