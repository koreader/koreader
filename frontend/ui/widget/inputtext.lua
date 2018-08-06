local Blitbuffer = require("ffi/blitbuffer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
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
    input_type = nil, -- "number" or anything else
    text_type = nil, -- "password" or anything else
    show_password_toggle = true,
    cursor_at_end = true, -- starts with cursor at end of text, ready for appending
    scroll = false, -- whether to allow scrolling (will be set to true if no height provided)
    focused = true,
    parent = nil, -- parent dialog that will be set dirty
    edit_callback = nil, -- called with true when text modified, false on init or text re-set
    scroll_callback = nil, -- called with (low, high) when view is scrolled (cf ScrollTextWidget)

    width = nil,
    height = nil, -- when nil, will be set to original text height (possibly
                  -- less if screen would be overflowed) and made scrollable to
                  -- not overflow if some text is appended and add new lines

    face = Font:getFace("smallinfofont"),
    padding = Size.padding.default,
    margin = Size.margin.default,
    bordersize = Size.border.inputtext,

    -- for internal use
    text_widget = nil, -- Text Widget for cursor movement, possibly a ScrollTextWidget
    charlist = nil, -- table of individual chars from input string
    charpos = nil, -- position of the cursor, where a new char would be inserted
    top_line_num = nil, -- virtual_line_num of the text_widget (index of the displayed top line)
    is_password_type = false, -- set to true if original text_type == "password"
    is_text_editable = true, -- whether text is utf8 reversible and editing won't mess content
    is_text_edited = false, -- whether text has been updated
}

-- only use PhysicalKeyboard if the device does not have touch screen
if Device.isTouchDevice() or Device.hasDPad() then
    Keyboard = require("ui/widget/virtualkeyboard")
    if Device.isTouchDevice() then
        function InputText:initEventListener()
            self.ges_events = {
                TapTextBox = {
                    GestureRange:new{
                        ges = "tap",
                        range = self.dimen
                    }
                },
                HoldTextBox = {
                    GestureRange:new{
                        ges = "hold",
                        range = self.dimen
                    }
                },
                SwipeTextBox = {
                    GestureRange:new{
                        ges = "swipe",
                        range = self.dimen
                    }
                },
                -- These are just to stop propagation of the event to
                -- parents in case there's a MovableContainer among them
                -- Commented for now, as this needs work
                -- HoldPanTextBox = {
                --     GestureRange:new{ ges = "hold_pan", range = self.dimen }
                -- },
                -- HoldReleaseTextBox = {
                --     GestureRange:new{ ges = "hold_release", range = self.dimen }
                -- },
                -- PanTextBox = {
                --     GestureRange:new{ ges = "pan", range = self.dimen }
                -- },
                -- PanReleaseTextBox = {
                --     GestureRange:new{ ges = "pan_release", range = self.dimen }
                -- },
                -- TouchTextBox = {
                --     GestureRange:new{ ges = "touch", range = self.dimen }
                -- },
            }
        end

        -- For MovableContainer to work fully, some of these should
        -- do more check before disabling the event or not
        -- Commented for now, as this needs work
        -- local function _disableEvent() return true end
        -- InputText.onHoldPanTextBox = _disableEvent
        -- InputText.onHoldReleaseTextBox = _disableEvent
        -- InputText.onPanTextBox = _disableEvent
        -- InputText.onPanReleaseTextBox = _disableEvent
        -- InputText.onTouchTextBox = _disableEvent

        function InputText:onTapTextBox(arg, ges)
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            end
            local textwidget_offset = self.margin + self.bordersize + self.padding
            local x = ges.pos.x - self._frame_textwidget.dimen.x - textwidget_offset
            local y = ges.pos.y - self._frame_textwidget.dimen.y - textwidget_offset
            self.text_widget:moveCursorToXY(x, y, true) -- restrict_to_view=true
            self.charpos, self.top_line_num = self.text_widget:getCharPos()
            return true
        end

        function InputText:onHoldTextBox(arg, ges)
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            end
            local textwidget_offset = self.margin + self.bordersize + self.padding
            local x = ges.pos.x - self._frame_textwidget.dimen.x - textwidget_offset
            local y = ges.pos.y - self._frame_textwidget.dimen.y - textwidget_offset
            self.text_widget:moveCursorToXY(x, y, true) -- restrict_to_view=true
            self.charpos, self.top_line_num = self.text_widget:getCharPos()
            if Device:hasClipboard() and Device.input.hasClipboardText() then
                self:addChars(Device.input.getClipboardText())
            end
            return true
        end

        function InputText:onSwipeTextBox(arg, ges)
            -- Allow refreshing the widget (actually, the screen) with the classic
            -- Diagonal Swipe, as we're only using the quick "ui" mode while editing
            if ges.direction == "northeast" or ges.direction == "northwest"
            or ges.direction == "southeast" or ges.direction == "southwest" then
                if self.refresh_callback then self.refresh_callback() end
                -- Trigger a full-screen HQ flashing refresh so
                -- the keyboard can also be fully redrawn
                UIManager:setDirty(nil, "full")
            end
            -- Let it propagate in any case (a long diagonal swipe may also be
            -- used for taking a screenshot)
            return false
        end

    end
    if Device.hasKeys() then
        if not InputText.initEventListener then
            function InputText:initEventListener() end
        end

        function InputText:onFocus()
            --Event called by the focusmanager
            self.key_events.ShowKeyboard = { {"Press"}, doc = "show keyboard" }
            self:focus()
            return true
        end

        function InputText:onUnfocus()
            --Event called by the focusmanager
            self.key_events = {}
            self:unfocus()
            return true
        end
    end
else
    Keyboard = require("ui/widget/physicalkeyboard")
    function InputText:initEventListener() end
end

function InputText:checkTextEditability()
    -- The split of the 'text' string to a table of utf8 chars may not be
    -- reversible to the same string, if 'text'  comes from a binary file
    -- (it looks like it does not necessarily need to be proper UTF8 to
    -- be reversible, some text with latin1 chars is reversible).
    -- As checking that may be costly, we do that only in init(), setText(),
    -- and clear().
    -- When not reversible, we prevent adding and deleting chars to not
    -- corrupt the original self.text.
    self.is_text_editable = true
    if self.text then
        -- We check that the text obtained from the UTF8 split done
        -- in :initTextBox(), when concatenated back to a string, matches
        -- the original text. (If this turns out too expensive, we could
        -- just compare their lengths)
        self.is_text_editable = table.concat(self.charlist, "") == self.text
    end
end

function InputText:isTextEditable(show_warning)
    if show_warning and not self.is_text_editable then
        UIManager:show(Notification:new{
            text = _("Text may be binary content, and is not editable"),
            timeout = 2
        })
    end
    return self.is_text_editable
end

function InputText:isTextEdited()
    return self.is_text_edited
end

function InputText:init()
    if self.text_type == "password" then
        -- text_type changes from "password" to "text" when we toggle password
        self.is_password_type = true
    end
    -- Beware other cases where implicit conversion to text may be done
    -- at some point, but checkTextEditability() would say "not editable".
    if self.input_type == "number" and type(self.text) == "number" then
        -- checkTextEditability() fails if self.text stays not a string
        self.text = tostring(self.text)
    end
    self:initTextBox(self.text)
    self:checkTextEditability()
    if self.readonly ~= true then
        self:initKeyboard()
        self:initEventListener()
    end
end

-- This will be called when we add or del chars, as we need to recreate
-- the text widget to have the new text splittted into possibly different
-- lines than before
function InputText:initTextBox(text, char_added)
    self.text = text
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
        -- keep previous cursor position if charpos not nil
        if self.charpos == nil then
            if self.cursor_at_end then
                self.charpos = #self.charlist + 1
            else
                self.charpos = 1
            end
        end
    end
    if self.is_password_type and self.show_password_toggle then
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
                self:setText(self:getText(), true)
            end,

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

    if not self.height then
        -- If no height provided, measure the text widget height
        -- we would start with, and use a ScrollTextWidget with that
        -- height, so widget does not overflow container if we extend
        -- the text and increase the number of lines.
        local text_width = self.width
        if text_width then
            -- Account for the scrollbar that will be used
            local scroll_bar_width = ScrollTextWidget.scroll_bar_width + ScrollTextWidget.text_scroll_span
            text_width = text_width - scroll_bar_width
        end
        local text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = show_charlist,
            face = self.face,
            width = text_width,
        }
        self.height = text_widget:getTextHeight()
        self.scroll = true
        text_widget:free()
    end
    if self.scroll then
        self.text_widget = ScrollTextWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            top_line_num = self.top_line_num,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
            dialog = self.parent,
            scroll_callback = self.scroll_callback,
        }
    else
        self.text_widget = TextBoxWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            top_line_num = self.top_line_num,
            editable = self.focused,
            face = self.face,
            fgcolor = fgcolor,
            width = self.width,
            height = self.height,
            dialog = self.parent,
        }
    end
    -- Get back possibly modified charpos and virtual_line_num
    self.charpos, self.top_line_num = self.text_widget:getCharPos()

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
    if self.edit_callback then
        self.edit_callback(self.is_text_edited)
    end
end

function InputText:initKeyboard()
    local keyboard_layout = 2
    if self.input_type == "number" then
        keyboard_layout = 4
    end
    self.key_events = nil
    self.keyboard = Keyboard:new{
        keyboard_layout = keyboard_layout,
        inputbox = self,
        width = Screen:getWidth(),
    }
end

function InputText:unfocus()
    self.focused = false
    self.text_widget:unfocus()
    self._frame_textwidget.color = Blitbuffer.COLOR_GREY
end

function InputText:focus()
    self.focused = true
    self.text_widget:focus()
    self._frame_textwidget.color = Blitbuffer.COLOR_BLACK
end

function InputText:onShowKeyboard()
    UIManager:show(self.keyboard)
    return true
end

function InputText:onCloseKeyboard()
    UIManager:close(self.keyboard)
end

function InputText:getTextHeight()
    return self.text_widget:getTextHeight()
end

function InputText:getLineHeight()
    return self.text_widget:getLineHeight()
end

function InputText:getKeyboardDimen()
    if self.readonly then
        return Geom:new{w = 0, h = 0}
    end
    return self.keyboard.dimen
end

function InputText:addChars(chars)
    if not chars then
        -- VirtualKeyboard:addChar(key) gave us 'nil' once (?!)
        -- which would crash table.concat()
        return
    end
    if self.enter_callback and chars == "\n" then
        UIManager:scheduleIn(0.3, function() self.enter_callback() end)
        return
    end
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    self.is_text_edited = true
    table.insert(self.charlist, self.charpos, chars)
    self.charpos = self.charpos + #util.splitToChars(chars)
    self:initTextBox(table.concat(self.charlist), true)
end

function InputText:delChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    self.is_text_edited = true
    table.remove(self.charlist, self.charpos)
    self:initTextBox(table.concat(self.charlist))
end

function InputText:delToStartOfLine()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end
    -- self.charlist[self.charpos] is the char after the cursor
    if self.charlist[self.charpos-1] == "\n" then
        -- If at start of line, just remove the \n and join the previous line
        self.charpos = self.charpos - 1
        table.remove(self.charlist, self.charpos)
    else
        -- If not, remove chars until first found \n (but keeping it)
        while self.charpos > 1 and self.charlist[self.charpos-1] ~= "\n" do
            self.charpos = self.charpos - 1
            table.remove(self.charlist, self.charpos)
        end
    end
    self.is_text_edited = true
    self:initTextBox(table.concat(self.charlist))
end

-- For the following cursor/scroll methods, the text_widget deals
-- itself with setDirty'ing the appropriate regions
function InputText:leftChar()
    if self.charpos == 1 then return end
    self.text_widget:moveCursorLeft()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:rightChar()
    if self.charpos > #self.charlist then return end
    self.text_widget:moveCursorRight()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:upLine()
    self.text_widget:moveCursorUp()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:downLine()
    self.text_widget:moveCursorDown()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollDown()
    self.text_widget:scrollDown()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollUp()
    self.text_widget:scrollUp()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollToTop()
    self.text_widget:scrollToTop()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:scrollToBottom()
    self.text_widget:scrollToBottom()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:clear()
    self.charpos = nil
    self.top_line_num = 1
    self.is_text_edited = true
    self:initTextBox("")
    self:checkTextEditability()
end

function InputText:getText()
    return self.text
end

function InputText:setText(text, keep_edited_state)
    -- Keep previous charpos and top_line_num
    self:initTextBox(text)
    if not keep_edited_state then
        -- assume new text is set by caller, and we start fresh
        self.is_text_edited = false
        self:checkTextEditability()
    end
end

return InputText
