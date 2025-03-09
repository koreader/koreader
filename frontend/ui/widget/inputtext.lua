local Blitbuffer = require("ffi/blitbuffer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
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
local dbg = require("dbg")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local Keyboard -- Conditional instantiation
local FocusManagerInstance -- Delayed instantiation

local InputText = InputContainer:extend{
    text = "",
    hint = "",
    input_type = nil, -- "number" or anything else
    text_type = nil, -- "password" or anything else
    show_password_toggle = true,
    cursor_at_end = true, -- starts with cursor at end of text, ready for appending
    scroll = false, -- whether to allow scrolling (will be set to true if no height provided)
    focused = true,
    parent = nil, -- parent dialog that will be set dirty
    edit_callback = nil, -- called with true when text modified, false on init or text re-set
    scroll_callback = nil, -- called with (low, high) when view is scrolled (c.f., ScrollTextWidget)
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

    readonly = nil, -- will not support a Keyboard widget if true

    -- for internal use
    keyboard = nil, -- Keyboard widget (either VirtualKeyboard or PhysicalKeyboard)
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
}

-- These may be (internally) overloaded as needed, depending on Device capabilities.
function InputText:initEventListener() end
function InputText:onFocus() end
function InputText:onUnfocus() end

-- Resync our position state with our text widget's actual state
function InputText:resyncPos()
    self.charpos, self.top_line_num = self.text_widget:getCharPos()
    if self.strike_callback and self.min_buffer_size == nil then -- not Terminal plugin input
        self.strike_callback()
    end
end

local function initTouchEvents()
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
                HoldReleaseTextBox = {
                    GestureRange:new{
                        ges = "hold_release",
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
                if self.keyboard then
                    self.keyboard:showKeyboard()
                end
                -- Make sure we're flagged as in focus again.
                -- NOTE: self:focus() does a full free/reinit cycle, which is completely unnecessary to begin with,
                --       *and* resets cursor position, which is problematic when tapping on an already in-focus field (#12444).
                --       So, just flip our own focused flag, that's the only thing we need ;).
                self.focused = true
            end
            if self._frame_textwidget.dimen ~= nil -- zh keyboard with candidates shown here has _frame_textwidget.dimen = nil
                    and #self.charlist > 0 then -- do not move cursor within a hint
                local textwidget_offset = self.margin + self.bordersize + self.padding
                local x = ges.pos.x - self._frame_textwidget.dimen.x - textwidget_offset
                local y = ges.pos.y - self._frame_textwidget.dimen.y - textwidget_offset
                self.text_widget:moveCursorToXY(x, y, true) -- restrict_to_view=true
                self:resyncPos()
            end
            return true
        end

        function InputText:onHoldTextBox(arg, ges)
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            end
            -- clipboard dialog
            self._hold_handled = nil
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
                        self:initTextBox()
                    else -- select start
                        self.selection_start_pos = self.charpos
                        UIManager:show(Notification:new{
                            text = _("Set cursor to end of selection, then long-press in text box."),
                        })
                    end
                    self._hold_handled = true
                    return true
                end
                local clipboard_value = Device.input.getClipboardText()
                local is_clipboard_empty = clipboard_value == ""
                local clipboard_dialog
                clipboard_dialog = require("ui/widget/textviewer"):new{
                    title = _("Clipboard"),
                    show_menu = false,
                    text = is_clipboard_empty and _("(empty)") or clipboard_value,
                    fgcolor = is_clipboard_empty and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
                    width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8),
                    height = math.floor(math.max(Screen:getWidth(), Screen:getHeight()) * 0.4),
                    justified = false,
                    modal = true,
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
                                    local txt = table.concat(self.charlist, "", self:getStringPos())
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
                                    local txt = table.concat(self.charlist, "", self:getStringPos(true))
                                    Device.input.setClipboardText(txt)
                                    UIManager:show(Notification:new{
                                        text = _("Word copied to clipboard."),
                                    })
                                end,
                            },
                        },
                        {
                            {
                                text = _("Delete all"),
                                enabled = #self.charlist > 0,
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    self:delAll()
                                end,
                            },
                            {
                                text = _("Select"),
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    UIManager:show(Notification:new{
                                        text = _("Set cursor to start of selection, then long-press in text box."),
                                    })
                                    self.do_select = true
                                    self:initTextBox()
                                end,
                            },
                            {
                                text = _("Paste"),
                                enabled = not is_clipboard_empty,
                                callback = function()
                                    UIManager:close(clipboard_dialog)
                                    self:addChars(clipboard_value)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(clipboard_dialog)
            end
            self._hold_handled = true
            return true
        end

        function InputText:onHoldReleaseTextBox(arg, ges)
            if self._hold_handled then
                self._hold_handled = nil
                return true
            end
            return false
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
end

local function initDPadEvents()
    if Device:hasDPad() then
        function InputText:onFocus()
            -- Event sent by focusmanager
            if self.parent.onSwitchFocus then
                self.parent:onSwitchFocus(self)
            elseif (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:isFalse("virtual_keyboard_enabled") then
                do end -- luacheck: ignore 541
            else
                if not self:isKeyboardVisible() then
                    self:onShowKeyboard()
                end
            end
            self:focus()
            return true
        end

        function InputText:onUnfocus()
            -- Event called by the focusmanager
            self:unfocus()
            return true
        end
    end
end

-- only use PhysicalKeyboard if the device does not support touch input
function InputText.initInputEvents()
    FocusManagerInstance = nil

    if Device:isTouchDevice() or Device:hasDPad() then
        Keyboard = require("ui/widget/virtualkeyboard")
        initTouchEvents()
        initDPadEvents()
    else
        Keyboard = require("ui/widget/physicalkeyboard")
    end
end

InputText.initInputEvents()

function InputText:checkTextEditability()
    -- The split of the 'text' string to a table of utf8 chars may not be
    -- reversible to the same string, if 'text' comes from a binary file
    -- (it looks like it does not necessarily need to be proper UTF8 to
    -- be reversible, some text with latin1 chars is reversible).
    -- As checking that may be costly, we do that only in init() and setText().
    -- When not reversible, we prevent adding and deleting chars to not
    -- corrupt the original self.text.
    self.is_text_editable = true
    if self.text then
        -- We check that the text obtained from the UTF8 split done
        -- in :initTextBox(), when concatenated back to a string, matches
        -- the original text. (If this turns out too expensive, we could
        -- just compare their lengths)
        self.is_text_editable = table.concat(self.charlist) == self.text
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
    if Device:isTouchDevice() then
        if self.text_type == "password" then
            -- text_type changes from "password" to "text" when we toggle password
            self.is_password_type = true
        end
    else
        -- focus move does not work with textbox and show password checkbox
        -- force show password for non-touch device
        self.text_type = "text"
        self.is_password_type = false
    end
    -- Beware other cases where implicit conversion to text may be done
    -- at some point, but checkTextEditability() would say "not editable".
    if self.input_type == "number" then
        if type(self.text) == "number" then
            -- checkTextEditability() fails if self.text stays not a string
            self.text = tostring(self.text)
        end
        if type(self.hint) == "number" then
            self.hint = tostring(self.hint)
        end
    end
    self.charlist = util.splitToChars(self.text)
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
        self.text_widget:free(true)
    end

    -- 'text' is passed in init() and setText() only, to check editability;
    -- other methods modify and provide self.charlist
    self.text = text or table.concat(self.charlist)
    local show_charlist, show_text, fgcolor
    if self.text == "" then
        -- no preset value, use hint text if set
        show_text = self.hint
        fgcolor = Blitbuffer.COLOR_DARK_GRAY
        self.charlist = {}
        self.charpos = 1
    else
        fgcolor = Blitbuffer.COLOR_BLACK
        if self.text_type == "password" then
            show_charlist = {}
            for i = 1, #self.charlist do
                if char_added and i == self.charpos - 1 then -- show last entered char
                    show_charlist[i] = self.charlist[i]
                else
                    show_charlist[i] = "*"
                end
            end
            show_text = table.concat(show_charlist)
        else
            show_charlist = self.charlist
            show_text = self.text
        end
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
            parent = self,
            width = self.width,
            callback = function()
                self.text_type = self._check_button.checked and "text" or "password"
                self:setText(self:getText(), true)
            end,
        }
        self._password_toggle = FrameContainer:new{
            bordersize = 0,
            padding = self.padding,
            padding_top = 0,
            padding_bottom = 0,
            margin = self.margin + self.bordersize,
            self._check_button,
        }
    else
        self._password_toggle = nil
    end

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
        text_widget:free(true)
    end
    if self.scroll then
        self.text_widget = ScrollTextWidget:new{
            text = show_text,
            charlist = show_charlist,
            charpos = self.charpos,
            top_line_num = self.top_line_num,
            editable = self.focused,
            select_mode = self.do_select,
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
            select_mode = self.do_select,
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
    self:resyncPos()

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
    self.key_events = {}
    self.keyboard = Keyboard:new{
        keyboard_layer = self.input_type == "number" and 4 or 2,
        inputbox = self,
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

-- NOTE: This key_map can be used for keyboards without numeric keys, such as on Kindles with keyboards. It is loosely 'inspired' by the symbol layer on the virtual keyboard but,
--       we have taken the liberty of making some adjustments since:
--       * K3 does not have numeric keys (top row) and,
--       * we want to prioritise the most-likely-used characters for "style tweaks" and note taking
--       (in English, sorry everybody else, there are just not enough keys)
local sym_key_map = {
    ["Q"] = "!", ["W"] = "?", ["E"] = "-", ["R"] = "_", ["T"] = "%", ["Y"] = "=", ["U"] = "7", ["I"] = "8",  ["O"] = "9", ["P"] = "0",
    ["A"] = "<", ["S"] = ">", ["D"] = "(", ["F"] = ")", ["G"] = "#", ["H"] = "'", ["J"] = "4", ["K"] = "5",  ["L"] = "6",
    ["Z"] = "{", ["X"] = "}", ["C"] = "[", ["V"] = "]", ["B"] = "1", ["N"] = "2", ["M"] = "3", ["."] = ":", ["AA"] = ";",
}

-- Handle real keypresses from a physical keyboard, even if the virtual keyboard
-- is shown. Mostly likely to be in the emulator, but could be Android + BT
-- keyboard, or a "coder's keyboard" Android input method.
function InputText:onKeyPress(key)
    -- only handle key on focused status, otherwise there are more than one InputText
    -- the first one always handle key pressed
    if not self.focused then
        return false
    end
    local handled = true

    if not key["Ctrl"] and not key["Shift"] and not key["Alt"] and not key["ScreenKB"] then
        if key["Backspace"] then
            self:delChar()
        elseif key["Del"] then
            -- Kindles with physical keyboards only have a "Del" key (no "Backspace").
            if Device:hasSymKey() then
                self:delChar()
            else
                self:delNextChar()
            end
        elseif key["Left"] then
            self:leftChar()
        elseif key["Right"] then
            self:rightChar()
        -- NOTE: When we are not showing the virtual keyboard, let focusmanger handle up/down keys, as they  are used to directly move around the widget
        --       seamlessly in and out of text fields and onto virtual buttons like `[cancel] [search dict]`, no need to unfocus first.
        elseif key["Up"] and G_reader_settings:nilOrTrue("virtual_keyboard_enabled") then
            self:upLine()
        elseif key["Down"] and G_reader_settings:nilOrTrue("virtual_keyboard_enabled") then
            self:downLine()
        elseif key["End"] then
            self:goToEnd()
        elseif key["Home"] then
            self:goToHome()
        elseif key["Press"] then
            self:addChars("\n")
        elseif key["Tab"] then
            self:addChars("    ")
        -- as stated before, we also don't need to unfocus when there is no keyboard, one less key press to exit widgets, yay!
        elseif key["Back"] and G_reader_settings:nilOrTrue("virtual_keyboard_enabled") then
            if self.focused then
                self:unfocus()
            end
        else
            handled = false
        end
    elseif key["Ctrl"] and not key["Shift"] and not key["Alt"] then
        if key["U"] then
            self:delToStartOfLine()
        elseif key["H"] then
            self:delChar()
        else
            handled = false
        end
    else
        handled = false
    end
    -- This primarily targets Kindle. When a virtual keyboard is shown on screen, mod+dpad allows controlling the cursor, as dpad alone
    -- (see previous ‘if’) is now occupied handling the virtual keyboard.
    if not handled and (key["ScreenKB"] or key["Shift"]) then
        handled = true
        if key["Back"] and Device:hasScreenKB() then
            self:delChar()
        elseif key["Back"] and Device:hasSymKey() then
            self:delToStartOfLine()
        elseif key["Del"] and Device:hasSymKey() then
            self:delWord()
        elseif key["Left"] then
            self:leftChar()
        elseif key["Right"] then
            self:rightChar()
        elseif key["Up"] then
            self:upLine()
        elseif key["Down"] then
            self:downLine()
        elseif key["Home"] then
            if self.keyboard:isVisible() then
                self:onCloseKeyboard()
            else
                self:onShowKeyboard()
            end
        elseif key["."] and Device:hasSymKey() then
            -- Kindle does not have a dedicated button for commas
            self:addChars(",")
        else
            handled = false
        end
    end
    if not handled and Device:hasSymKey() then
        handled = true
        local symkey = sym_key_map[key.key]
        -- Do not match Shift + Sym + 'Alphabet keys'
        if symkey and key.modifiers["Sym"] and not key.modifiers["Shift"] then
            self:addChars(symkey)
        else
            handled = false
        end
    end
    if not handled and Device:hasDPad() then
        -- FocusManager may turn on alternative key maps.
        -- These key map maybe single text keys.
        -- It will cause unexpected focus move instead of enter text to InputText
        if not FocusManagerInstance then
            FocusManagerInstance = FocusManager:new{}
        end
        local is_alternative_key = FocusManagerInstance:isAlternativeKey(key)
        if not is_alternative_key and Device:isSDL() then
            -- SDL already insert char via TextInput event
            -- Stop event propagate to FocusManager
            return true
        end
        -- if it is single text char, insert it
        local key_code = key.key -- is in upper case
        if not Device.isSDL() and #key_code == 1 then
            if key["Shift"] and key["Alt"] and key["G"] then
                -- Allow the screenshot keyboard-shortcut to work when focus is on InputText
                return false
            end
            if not key["Shift"] then
                key_code = string.lower(key_code)
            end
            for modifier, flag in pairs(key.modifiers) do
                if modifier ~= "Shift" and flag then -- Other modifier: not a single char insert
                    return true
                end
            end
            self:addChars(key_code)
            return true
        end
        if is_alternative_key then
            return true -- Stop event propagate to FocusManager to void focus move
        end
    end
    return handled
end

-- Handle text coming directly as text from the Device layer (eg. soft keyboard
-- or via SDL's keyboard mapping).
function InputText:onTextInput(text)
    -- for more than one InputText, let the focused one add chars
    if self.focused then
        self:addChars(text)
        return true
    end
    return false
end
dbg:guard(InputText, "onTextInput",
    function(self, text)
        assert(type(text) == "string",
            "Wrong text type (expected string)")
    end)

function InputText:onShowKeyboard(ignore_first_hold_release)
    if self.keyboard then
        self.keyboard:showKeyboard(ignore_first_hold_release)
    end
    return true
end

function InputText:onCloseKeyboard()
    if self.keyboard then
        self.keyboard:hideKeyboard()
    end
end

function InputText:isKeyboardVisible()
    if self.keyboard then
        return self.keyboard:isVisible()
    end
    -- NOTE: Never return `nil`, to avoid inheritance issues in (Multi)InputDialog's keyboard_visible flag.
    return false
end

function InputText:lockKeyboard(toggle)
    if self.keyboard then
        return self.keyboard:lockVisibility(toggle)
    end
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
    return self.readonly and Geom:new{w = 0, h = 0} or self.keyboard.dimen
end

-- calculate current and last (original) line numbers
function InputText:getLineNums()
    local curr_line_num, last_line_num = 1, 1
    for i = 1, #self.charlist do
        if self.text_widget.charlist[i] == "\n" then
            if i < self.charpos then
                curr_line_num = curr_line_num + 1
            end
            last_line_num = last_line_num + 1
        end
    end
    return curr_line_num, last_line_num
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

-- Get start and end positions of a line (or a word) under the cursor.
function InputText:getStringPos(is_word, left_to_cursor)
    local delimiter = is_word and "[\n\r%s.,;:!?–—―]" or "[\n\r]"
    local start_pos, end_pos
    if self.charpos > 1 then
        for i = self.charpos - 1, 1, -1 do
            if self.charlist[i]:find(delimiter) then
                start_pos = i + 1
                break
            end
        end
    end
    if left_to_cursor then
        end_pos = self.charpos - 1
    else
        if self.charpos <= #self.charlist then
            for i = self.charpos, #self.charlist do
                if self.charlist[i]:find(delimiter) then
                    end_pos = i - 1
                    break
                end
            end
        end
    end
    return start_pos or 1, end_pos or #self.charlist
end

--- Return the character at the given offset. If is_absolute is truthy then the
-- offset is the absolute position, otherwise the offset is added to the current
-- cursor position (negative offsets are allowed).
function InputText:getChar(offset, is_absolute)
    local idx = is_absolute and offset or self.charpos + offset
    return self.charlist[idx]
end

function InputText:addChars(chars)
    if self.enter_callback and chars == "\n" then
        UIManager:scheduleIn(0.3, function() self.enter_callback() end)
        return
    end

    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if #self.charlist == 0 then -- widget text is empty or a hint text is displayed
        self.charpos = 1 -- move cursor to the first position
    end
    local added_charlist = util.splitToChars(chars)
    for i = #added_charlist, 1, -1 do
        table.insert(self.charlist, self.charpos, added_charlist[i])
    end
    self.charpos = self.charpos + #added_charlist
    self.is_text_edited = true
    self:initTextBox(nil, true)
end
dbg:guard(InputText, "addChars",
    function(self, chars)
        assert(type(chars) == "string",
            "Wrong chars value type (expected string)!")
    end)

function InputText:delChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end
    self.charpos = self.charpos - 1
    table.remove(self.charlist, self.charpos)
    self.is_text_edited = true
    self:initTextBox()
end

function InputText:delNextChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos > #self.charlist then return end
    table.remove(self.charlist, self.charpos)
    self.is_text_edited = true
    self:initTextBox()
end

function InputText:delWord(left_to_cursor)
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    local start_pos, end_pos = self:getStringPos(true, left_to_cursor)
    start_pos = math.min(start_pos, end_pos)
    for i = end_pos, start_pos, -1 do
        table.remove(self.charlist, i)
    end
    if #self.charlist > 0 then
        local prev_pos = start_pos > 1 and start_pos - 1 or 1
        if not left_to_cursor and self.charlist[prev_pos]:find("[ \t]") then -- remove redundant space
            table.remove(self.charlist, prev_pos)
            self.charpos = prev_pos
        else
            self.charpos = start_pos
        end
    end
    self.is_text_edited = true
    self:initTextBox()
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
    self:initTextBox()
end

function InputText:delAll()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if #self.charlist == 0 then return end
    self.charlist = {}
    self.is_text_edited = true
    self:initTextBox()
end

-- For the following cursor/scroll methods, the text_widget deals
-- itself with setDirty'ing the appropriate regions
function InputText:leftChar()
    if self.charpos == 1 then return end
    self.text_widget:moveCursorLeft()
    self:resyncPos()
end

function InputText:rightChar()
    if self.charpos > #self.charlist then return end
    self.text_widget:moveCursorRight()
    self:resyncPos()
end

function InputText:goToStartOfLine()
    local new_pos = self:getStringPos()
    self.text_widget:moveCursorToCharPos(new_pos)
    self:resyncPos()
end

function InputText:goToEndOfLine()
    local _, new_pos = self:getStringPos()
    self.text_widget:moveCursorToCharPos(new_pos + 1)
    self:resyncPos()
end

function InputText:goToHome()
    self.text_widget:moveCursorHome()
    self:resyncPos()
end

function InputText:goToEnd()
    self.text_widget:moveCursorEnd()
    self:resyncPos()
end

function InputText:moveCursorToCharPos(char_pos)
    self.text_widget:moveCursorToCharPos(char_pos)
    self:resyncPos()
end

function InputText:upLine()
    self.text_widget:moveCursorUp()
    self:resyncPos()
end

function InputText:downLine()
    if #self.charlist == 0 then return end -- Avoid cursor moving within a hint.
    self.text_widget:moveCursorDown()
    self:resyncPos()
end

function InputText:scrollDown()
    self.text_widget:scrollDown()
    self:resyncPos()
end

function InputText:scrollUp()
    self.text_widget:scrollUp()
    self:resyncPos()
end

function InputText:scrollToTop()
    self.text_widget:scrollToTop()
    self:resyncPos()
end

function InputText:scrollToBottom()
    self.text_widget:scrollToBottom()
    self:resyncPos()
end

function InputText:getText()
    return self.text
end

function InputText:setText(text, keep_edited_state)
    -- Keep previous charpos and top_line_num
    self.charlist = util.splitToChars(text)
    self:initTextBox(text)
    if not keep_edited_state then
        -- assume new text is set by caller, and we start fresh
        self.is_text_edited = false
        self:checkTextEditability()
    end
end
dbg:guard(InputText, "setText",
    function(self, text, keep_edited_state)
        assert(type(text) == "string",
            "Wrong text type (expected string)")
    end)

return InputText
