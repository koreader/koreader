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
local Utf8Proc = require("ffi/utf8proc")
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
    scroll_by_pan = false, -- allow scrolling by lines with Pan (needs scroll=true)

    width = nil,
    height = nil, -- when nil, will be set to original text height (possibly
                  -- less if screen would be overflowed) and made scrollable to
                  -- not overflow if some text is appended and add new lines

    face = Font:getFace("smallinfofont"),
    padding = Size.padding.default,
    margin = Size.margin.default,
    bordersize = Size.border.inputtext,

    -- See TextBoxWidget for details about these options
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = false,
    alignment_strict = false,

    -- for internal use
    text_widget = nil, -- Text Widget for cursor movement, possibly a ScrollTextWidget
    charlist = nil, -- table of individual chars from input string
    charpos = nil, -- position of the cursor, where a new char would be inserted
    top_line_num = nil, -- virtual_line_num of the text_widget (index of the displayed top line)
    is_password_type = false, -- set to true if original text_type == "password"
    is_text_editable = true, -- whether text is utf8 reversible and editing won't mess content
    is_text_edited = false, -- whether text has been updated
    for_measurement_only = nil, -- When the widget is a one-off used to compute text height
    do_select = false, -- to start text selection
    selection_start_pos = nil, -- selection start position
    is_keyboard_hidden = false, -- to be able to show the keyboard again when it was hidden
}

-- only use PhysicalKeyboard if the device does not have touch screen
if Device:isTouchDevice() or Device:hasDPad() then
    Keyboard = require("ui/widget/virtualkeyboard")
    if Device:isTouchDevice() then
        function InputText:initEventListener()
            self.ges_events = {
                TapTextBox = {
                    GestureRange:new{
                        ges = "tap",
                        range = function() return self.dimen end
                    }
                },
                HoldTextBox = {
                    GestureRange:new{
                        ges = "hold",
                        range = function() return self.dimen end
                    }
                },
                SwipeTextBox = {
                    GestureRange:new{
                        ges = "swipe",
                        range = function() return self.dimen end
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
            else
                if self.is_keyboard_hidden == true then
                    self:onShowKeyboard()
                    self.is_keyboard_hidden = false
                end
            end
            if #self.charlist > 0 then -- Avoid cursor moving within a hint.
                local textwidget_offset = self.margin + self.bordersize + self.padding
                local x = ges.pos.x - self._frame_textwidget.dimen.x - textwidget_offset
                local y = ges.pos.y - self._frame_textwidget.dimen.y - textwidget_offset
                self.text_widget:moveCursorToXY(x, y, true) -- restrict_to_view=true
                self.charpos, self.top_line_num = self.text_widget:getCharPos()
            end
            return true
        end

        function InputText:onHoldTextBox(arg, ges)
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            end
            -- clipboard dialog
            if Device:hasClipboard() then
                if self.do_select then -- select mode on
                    if self.selection_start_pos then -- select end
                        local selection_end_pos = self.charpos - 1
                        if self.selection_start_pos > selection_end_pos then
                            self.selection_start_pos, selection_end_pos = selection_end_pos + 1, self.selection_start_pos - 1
                        end
                        local txt = table.concat(self.charlist, "", self.selection_start_pos, selection_end_pos)
                        Device.input.setClipboardText(txt)
                        UIManager:show(Notification:new{
                            text = _("Selection copied to clipboard."),
                        })
                        self.selection_start_pos = nil
                        self.do_select = false
                        return true
                    else -- select start
                        self.selection_start_pos = self.charpos
                        UIManager:show(Notification:new{
                            text = _("Set cursor to end of selection, then hold."),
                        })
                        return true
                    end
                end
                local clipboard_value = Device.input.getClipboardText()
                local clipboard_dialog
                clipboard_dialog = require("ui/widget/textviewer"):new{
                    title = (clipboard_value == nil or clipboard_value == "") and _("Clipboard (empty)") or _("Clipboard"),
                    text = clipboard_value,
                    width = math.floor(Screen:getWidth() * 0.8),
                    height = math.floor(Screen:getHeight() * 0.4),
                    justified = false,
                    stop_events_propagation = true,
                    buttons_table = {
                        {
                            {
                                text = _("Copy all"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    Device.input.setClipboardText(table.concat(self.charlist))
                                    UIManager:show(Notification:new{
                                        text = _("All text copied to clipboard."),
                                    })
                                end,
                            },
                            {
                                text = _("Copy line"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    local txt = table.concat(self.charlist, "", self:getStringPos({"\n", "\r"}, {"\n", "\r"}))
                                    Device.input.setClipboardText(txt)
                                    UIManager:show(Notification:new{
                                        text = _("Line copied to clipboard."),
                                    })
                                end,
                            },
                            {
                                text = _("Copy word"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    local txt = table.concat(self.charlist, "", self:getStringPos({"\n", "\r", " "}, {"\n", "\r", " "}))
                                    Device.input.setClipboardText(txt)
                                    UIManager:show(Notification:new{
                                        text = _("Word copied to clipboard."),
                                    })
                                end,
                            },
                        },
                        {
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                end,
                            },
                            {
                                text = _("Select"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    UIManager:show(Notification:new{
                                        text = _("Set cursor to start of selection, then hold."),
                                    })
                                    self.do_select = true
                                end,
                            },
                            {
                                text = _("Paste"),
                                callback = function()
                                    if clipboard_value ~= nil and clipboard_value ~= "" then
                                        UIManager:close(clipboard_dialog)
                                        self:addChars(clipboard_value)
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(clipboard_dialog)
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
    if Device:hasDPad() then
        if not InputText.initEventListener then
            function InputText:initEventListener() end
        end

        function InputText:onFocus()
            -- Event called by the focusmanager
            self.key_events.ShowKeyboard = { {"Press"}, doc = "show keyboard" }
            self:focus()
            return true
        end

        function InputText:onUnfocus()
            -- Event called by the focusmanager
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
    if self.text_widget then
        self.text_widget:free()
    end
    self.text = text
    local fgcolor
    local show_charlist
    local show_text = text
    if show_text == "" or show_text == nil then
        -- no preset value, use hint text if set
        show_text = self.hint
        fgcolor = Blitbuffer.COLOR_DARK_GRAY
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
            lang = self.lang, -- these might influence height
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            for_measurement_only = true, -- flag it as a dummy, so it won't trigger any bogus repaint/refresh...
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
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
            width = self.width,
            height = self.height,
            dialog = self.parent,
            scroll_callback = self.scroll_callback,
            scroll_by_pan = self.scroll_by_pan,
            for_measurement_only = self.for_measurement_only,
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
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
            width = self.width,
            height = self.height,
            dialog = self.parent,
            for_measurement_only = self.for_measurement_only,
        }
    end
    -- Get back possibly modified charpos and virtual_line_num
    self.charpos, self.top_line_num = self.text_widget:getCharPos()

    self._frame_textwidget = FrameContainer:new{
        bordersize = self.bordersize,
        padding = self.padding,
        margin = self.margin,
        color = self.focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
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
    --- @fixme self.parent is not always in the widget stack (BookStatusWidget)
    -- Don't even try to refresh dummy widgets used for text height computations...
    if not self.for_measurement_only then
        UIManager:setDirty(self.parent, function()
            return "ui", self.dimen
        end)
    end
    if self.edit_callback then
        self.edit_callback(self.is_text_edited)
    end
end

function InputText:initKeyboard()
    local keyboard_layer = 2
    if self.input_type == "number" then
        keyboard_layer = 4
    end
    self.key_events = nil
    self.keyboard = Keyboard:new{
        keyboard_layer = keyboard_layer,
        inputbox = self,
        width = Screen:getWidth(),
    }
end

function InputText:unfocus()
    self.focused = false
    self.text_widget:unfocus()
    self._frame_textwidget.color = Blitbuffer.COLOR_DARK_GRAY
end

function InputText:focus()
    self.focused = true
    self.text_widget:focus()
    self._frame_textwidget.color = Blitbuffer.COLOR_BLACK
end

-- Handle real keypresses from a physical keyboard, even if the virtual keyboard
-- is shown. Mostly likely to be in the emulator, but could be Android + BT
-- keyboard, or a "coder's keyboard" Android input method.
function InputText:onKeyPress(key)
    if key["Backspace"] then
        self:delChar()
    elseif key["Del"] then
        self:rightChar()
        self:delChar()
    elseif key["Left"] then
        self:leftChar()
    elseif key["Right"] then
        self:rightChar()
    elseif key["End"] then
        self:goToEnd()
    elseif key["Home"] then
        self:goToHome()
    elseif key["Ctrl"] and not key["Shift"] and not key["Alt"] then
        if key["U"] then
            self:delToStartOfLine()
        elseif key["H"] then
            self:delChar()
        end
    else
        return false
    end

    return true
end

-- Handle text coming directly as text from the Device layer (eg. soft keyboard
-- or via SDL's keyboard mapping).
function InputText:onTextInput(text)
    self:addChars(text)
    return true
end

function InputText:onShowKeyboard(ignore_first_hold_release)
    Device:startTextInput()
    self.keyboard.ignore_first_hold_release = ignore_first_hold_release
    UIManager:show(self.keyboard)
    return true
end

function InputText:onCloseKeyboard()
    UIManager:close(self.keyboard)
    Device:stopTextInput()
    self.is_keyboard_hidden = true
end

function InputText:onCloseWidget()
    if self.keyboard then
        self.keyboard:free()
    end
    self:free()
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

-- calculate current and last (original) line numbers
function InputText:getLineNums()
    local cur_line_num, last_line_num = 1, 1
    for i = 1, #self.charlist do
        if self.text_widget.charlist[i] == "\n" then
            if i < self.charpos then
                cur_line_num = cur_line_num + 1
            end
            last_line_num = last_line_num + 1
        end
    end
    return cur_line_num, last_line_num
end

-- calculate charpos for the beginning of (original) line
function InputText:getLineCharPos(line_num)
    local char_pos = 1
    if line_num > 1 then
        local j = 1
        for i = 1, #self.charlist do
            if self.charlist[i] == "\n" then
                j = j + 1
                if j == line_num then
                    char_pos = i + 1
                    break
                end
            end
        end
    end
    return char_pos
end

-- Get start and end positions of the substring
-- delimited with the delimiters and containing char_pos.
-- If char_pos not set, current charpos assumed.
function InputText:getStringPos(left_delimiter, right_delimiter, char_pos)
    char_pos = char_pos and char_pos or self.charpos
    local start_pos, end_pos = 1, #self.charlist
    local done = false
    if char_pos > 1 then
        for i = char_pos, 2, -1 do
            for j = 1, #left_delimiter do
                if self.charlist[i-1] == left_delimiter[j] then
                    start_pos = i
                    done = true
                    break
                end
            end
            if done then break end
        end
    end
    done = false
    if char_pos < #self.charlist then
        for i = char_pos, #self.charlist do
            for j = 1, #right_delimiter do
                if self.charlist[i] == right_delimiter[j] then
                    end_pos = i - 1
                    done = true
                    break
                end
            end
            if done then break end
        end
    end
    return start_pos, end_pos
end

--- Search for a string.
-- if start_pos not set, starts a search from the next to cursor position
-- returns first found position or 0 if not found
function InputText:searchString(str, case_sensitive, start_pos)
    local str_charlist = util.splitToChars(str)
    local str_len = #str_charlist
    local char_pos, found = 0, 0
    start_pos = start_pos and (start_pos - 1) or self.charpos
    for i = start_pos, #self.charlist - str_len do
        for j = 1, str_len do
            local char_txt = self.charlist[i + j]
            local char_str = str_charlist[j]
            if not case_sensitive then
                char_txt = Utf8Proc.lowercase(util.fixUtf8(char_txt, "?"))
                char_str = Utf8Proc.lowercase(util.fixUtf8(char_str, "?"))
            end
            if char_txt ~= char_str then
                found = 0
                break
            end
            found = found + 1
        end
        if found == str_len then
            char_pos = i + 1
            break
        end
    end
    return char_pos
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
    if #self.charlist == 0 then -- widget text is empty or a hint text is displayed
        self.charpos = 1 -- move cursor to the first position
    end
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

function InputText:goToStartOfLine()
    local new_pos = select(1, self:getStringPos({"\n", "\r"}, {"\n", "\r"}))
    self.text_widget:moveCursorToCharPos(new_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToEndOfLine()
    local new_pos = select(2, self:getStringPos({"\n", "\r"}, {"\n", "\r"})) + 1
    self.text_widget:moveCursorToCharPos(new_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:goToHome()
    self.text_widget:moveCursorToCharPos(1)
end

function InputText:goToEnd()
    self.text_widget:moveCursorToCharPos(0)
end

function InputText:moveCursorToCharPos(char_pos)
    self.text_widget:moveCursorToCharPos(char_pos)
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:upLine()
    self.text_widget:moveCursorUp()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
end

function InputText:downLine()
    if #self.charlist == 0 then return end -- Avoid cursor moving within a hint.
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
