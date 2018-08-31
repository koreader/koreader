--[[--
Widget for taking user input.

Example:

    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = "default value",
        input_hint = "hint text",
        input_type = "string",
        description = "Some more description",
        -- text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(sample_input)
                    end,
                },
                {
                    text = _("Save"),
                    -- button with is_enter_default set to true will be
                    -- triggered after user press the enter key from keyboard
                    is_enter_default = true,
                    callback = function()
                        print('Got user input as raw text:', sample_input:getInputText())
                        print('Got user input as value:', sample_input:getInputValue())
                    end,
                },
            }
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()

To get a full screen text editor, use:
    fullscreen = true, -- no need to provide any height and width
    condensed = true,
    allow_newline = true,
    cursor_at_end = false,
    -- and one of these:
    add_scroll_buttons = true,
    add_nav_bar = true,

To add |Save|Close| buttons, use:
    save_callback = function(content, closing)
        ...deal with the edited content...
        if closing then
            UIManager:nextTick( stuff to do when InputDialog closed if any )
        end
        return nil -- sucess, default notification shown
        return true, success_notif_text
        return false, error_infomsg_text
    end
To additionally add a Reset button and have |Reset|Save|Close|, use:
    reset_callback = function()
        return original_content -- success
        return original_content, success_notif_text
        return nil, error_infomsg_text
    end
If you don't need more buttons than these, use these options for consistency
between dialogs, and don't provide any buttons.
Text used on these buttons and their messages and notifications can be
changed by providing alternative text with these additional options:
    reset_button_text
    save_button_text
    close_button_text
    close_unsaved_confirm_text
    close_cancel_button_text
    close_discard_button_text
    close_save_button_text
    close_discarded_notif_text

If it would take the user more than half a minute to recover from a mistake,
a "Cancel" button <em>must</em> be added to the dialog. The cancellation button
should be kept on the left and the button executing the action on the right.

It is strongly recommended to use a text describing the action to be
executed, as demonstrated in the example above. If the resulting phrase would be
longer than three words it should just read "OK".

]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local InputDialog = InputContainer:new{
    is_always_active = true,
    title = "",
    input = "",
    input_hint = "",
    description = nil,
    buttons = nil,
    input_type = nil,
    enter_callback = nil,
    readonly = false, -- don't allow editing, will not show keyboard
    allow_newline = false, -- allow entering new lines (this disables any enter_callback)
    cursor_at_end = true, -- starts with cursor at end of text, ready for appending
    fullscreen = false, -- adjust to full screen minus keyboard
    condensed = false, -- true will prevent adding air and balance between elements
    add_scroll_buttons = false, -- add scroll Up/Down buttons to first row of buttons
    add_nav_bar = false, -- append a row of page navigation buttons
        -- note that the text widget can be scrolled with Swipe North/South even when no button
    keyboard_hidden = false, -- start with keyboard hidden in full fullscreen mode
                             -- needs add_nav_bar to have a Show keyboard button to get it back
    scroll_by_pan = false, -- allow scrolling by lines with Pan (= Swipe, but wait a bit at end
                           -- of gesture before releasing) (may conflict with movable)

    -- If save_callback provided, a Save and a Close buttons will be added to the first row
    -- if reset_callback provided, a Reset button will be added (before Save) to the first row
    save_callback = nil,  -- Called with the input text content when Save (and true as 2nd arg
                          -- if closing, false if non-closing Save).
                          -- Should return nil or true on success, false on failure.
                          -- (This save_callback can do some syntax check before saving)
    reset_callback = nil, -- Called with no arg, should return the original content on success,
                          -- nil on failure.
                      -- Both these callbacks can return a string as a 2nd return value.
                      -- This string is then shown:
                      -- - on success: as the notification text instead of the default one
                      -- - on failure: in an InfoMessage
    close_callback = nil, -- Called when closing (if discarded or saved, after save_callback if saved)

    -- For use by TextEditor plugin:
    view_pos_callback = nil, -- Called with no arg to get initial top_line_num/charpos,
                             -- called with (top_line_num, charpos) to give back position on close.

    -- movable = true, -- set to false if movable gestures conflicts with subwidgets gestures
    -- for now, too much conflicts between InputText and MovableContainer, and
    -- there's the keyboard to exclude from move area (the InputDialog could
    -- be moved under the keyboard, and the user would be locked)
    movable = false,

    width = nil,

    text_width = nil,
    text_height = nil,

    title_face = Font:getFace("x_smalltfont"),
    description_face = Font:getFace("x_smallinfofont"),
    input_face = Font:getFace("x_smallinfofont"),

    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    desc_padding = Size.padding.default, -- Use the same as title for their
    desc_margin = Size.margin.title,     -- texts to be visually aligned
    input_padding = Size.padding.default,
    input_margin = Size.margin.default,
    button_padding = Size.padding.default,
    border_size = Size.border.window,

    -- for internal use
    _text_modified = false, -- previous known modified status
    _top_line_num = nil,
    _charpos = nil,
    _buttons_edit_callback = nil,
    _buttons_scroll_callback = nil,
    _buttons_backup_done = false,
    _buttons_backup = nil,
}

function InputDialog:init()
    if self.fullscreen then
        self.movable = false
        self.border_size = 0
        self.width = Screen:getWidth() - 2*self.border_size
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    else
        self.width = self.width or Screen:getWidth() * 0.8
    end
    if self.condensed then
        self.text_width = self.width - 2*(self.border_size + self.input_padding + self.input_margin)
    else
        self.text_width = self.text_width or self.width * 0.9
    end
    if self.readonly then -- hide keyboard if we can't edit
        self.keyboard_hidden = true
    end

    -- Title & description
    local title_width = RenderText:sizeUtf8Text(0, self.width,
            self.title_face, self.title, true).x
    if title_width > self.width then
        local indicator = "  >> "
        local indicator_w = RenderText:sizeUtf8Text(0, self.width,
                self.title_face, indicator, true).x
        self.title = RenderText:getSubTextByWidth(self.title, self.title_face,
                self.width - indicator_w, true) .. indicator
    end
    self.title_widget = FrameContainer:new{
        padding = self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        TextWidget:new{
            text = self.title,
            face = self.title_face,
            width = self.width,
        }
    }
    self.title_bar = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    if self.description then
        self.description_widget = FrameContainer:new{
            padding = self.desc_padding,
            margin = self.desc_margin,
            bordersize = 0,
            TextBoxWidget:new{
                text = self.description,
                face = self.description_face,
                width = self.width - 2*self.desc_padding - 2*self.desc_margin,
            }
        }
    else
        self.description_widget = VerticalSpan:new{ width = 0 }
    end

    -- Vertical spaces added before and after InputText
    -- (these will be adjusted later to center the input text if needed)
    local vspan_before_input_text = VerticalSpan:new{ width = 0 }
    local vspan_after_input_text = VerticalSpan:new{ width = 0 }
    -- We add the same vertical space used under description after the input widget
    -- (can be disabled by setting condensed=true)
    if not self.condensed then
        local desc_pad_height = self.desc_margin + self.desc_padding
        if self.description then
            vspan_before_input_text.width = 0 -- already provided by description_widget
            vspan_after_input_text.width = desc_pad_height
        else
            vspan_before_input_text.width = desc_pad_height
            vspan_after_input_text.width = desc_pad_height
        end
    end

    -- Buttons
    -- In case of re-init(), keep backup of original buttons and restore them
    self:_backupRestoreButtons()
    -- If requested, add predefined buttons alongside provided ones
    if self.save_callback then
        -- If save_callback provided, adds (Reset) / Save / Close buttons
        self:_addSaveCloseButtons()
    end
    if self.add_nav_bar then -- Home / End / Up / Down buttons
        self:_addScrollButtons(true)
    elseif self.add_scroll_buttons then -- Up / Down buttons
        self:_addScrollButtons(false)
    end
    -- Buttons Table
    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }
    local buttons_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    }

    -- InputText
    if not self.text_height or self.fullscreen then
        -- We need to find the best height to avoid screen overflow
        -- Create a dummy input widget to get some metrics
        local input_widget = InputText:new{
            text = self.fullscreen and "-" or self.input,
            face = self.input_face,
            width = self.text_width,
            padding = self.input_padding,
            margin = self.input_margin,
        }
        local text_height = input_widget:getTextHeight()
        local line_height = input_widget:getLineHeight()
        local input_pad_height = input_widget:getSize().h - text_height
        local keyboard_height = 0
        if not self.keyboard_hidden then
            keyboard_height = input_widget:getKeyboardDimen().h
        end
        input_widget:free()
        -- Find out available height
        local available_height = Screen:getHeight()
                                    - 2*self.border_size
                                    - self.title_widget:getSize().h
                                    - self.title_bar:getSize().h
                                    - self.description_widget:getSize().h
                                    - vspan_before_input_text:getSize().h
                                    - input_pad_height
                                    - vspan_after_input_text:getSize().h
                                    - buttons_container:getSize().h
                                    - keyboard_height
        if self.fullscreen or text_height > available_height then
            -- Don't leave unusable space in the text widget, as the user could think
            -- it's an empty line: move that space in pads after and below (for centering)
            self.text_height = math.floor(available_height / line_height) * line_height
            local pad_height = available_height - self.text_height
            local pad_before = math.ceil(pad_height / 2)
            local pad_after = pad_height - pad_before
            vspan_before_input_text.width = vspan_before_input_text.width + pad_before
            vspan_after_input_text.width = vspan_after_input_text.width + pad_after
            self.cursor_at_end = false -- stay at start if overflowed
        else
            -- Don't leave unusable space in the text widget
            self.text_height = text_height
        end
    end
    if self.view_pos_callback then
        -- Get initial cursor and top line num from callback
        -- (will work in case of re-init as these are saved by onClose()
        self._top_line_num, self._charpos = self.view_pos_callback()
    end
    self._input_widget = InputText:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        width = self.text_width,
        height = self.text_height or nil,
        padding = self.input_padding,
        margin = self.input_margin,
        input_type = self.input_type,
        text_type = self.text_type,
        enter_callback = self.enter_callback or function()
            for _,btn_row in ipairs(self.buttons) do
                for _,btn in ipairs(btn_row) do
                    if btn.is_enter_default then
                        btn.callback()
                        return
                    end
                end
            end
        end,
        edit_callback = self._buttons_edit_callback, -- nil if no Save/Close buttons
        scroll_callback = self._buttons_scroll_callback, -- nil if no Nav or Scroll buttons
        scroll = true,
        scroll_by_pan = self.scroll_by_pan,
        cursor_at_end = self.cursor_at_end,
        readonly = self.readonly,
        parent = self,
        is_text_edited = self._text_modified,
        top_line_num = self._top_line_num,
        charpos = self._charpos,
    }
    if self.allow_newline then -- remove any enter_callback
        self._input_widget.enter_callback = nil
    end
    if Device:hasKeys() then
        --little hack to piggyback on the layout of the button_table to handle the new InputText
        table.insert(self.button_table.layout, 1, {self._input_widget})
    end
    -- Complementary setup for some of our added buttons
    if self.save_callback then
        local save_button = self.button_table:getButtonById("save")
        if self.readonly then
            save_button:setText(_("Read only"), save_button.width)
        elseif not self._input_widget:isTextEditable() then
            save_button:setText(_("Not editable"), save_button.width)
        end
    end

    -- Final widget
    self.dialog_frame = FrameContainer:new{
        radius = self.fullscreen and 0 or Size.radius.window,
        padding = 0,
        margin = 0,
        bordersize = self.border_size,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_widget,
            self.title_bar,
            self.description_widget,
            vspan_before_input_text,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self._input_widget:getSize().h,
                },
                self._input_widget,
            },
            vspan_after_input_text,
            buttons_container,
        }
    }
    local frame = self.dialog_frame
    if self.movable then
        frame = MovableContainer:new{
            self.dialog_frame,
        }
    end
    local keyboard_height = self.keyboard_hidden and 0
                                or self._input_widget:getKeyboardDimen().h
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - keyboard_height,
        },
        frame
    }
end

function InputDialog:getInputText()
    return self._input_widget:getText()
end

function InputDialog:getInputValue()
    local text = self:getInputText()
    if self.input_type == "number" then
        return tonumber(text)
    else
        return text
    end
end

function InputDialog:setInputText(text)
    self._input_widget:setText(text)
end

function InputDialog:isTextEditable()
    return self._input_widget:isTextEditable()
end

function InputDialog:isTextEdited()
    return self._input_widget:isTextEdited()
end

function InputDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onCloseWidget()
    self:onClose()
    UIManager:setDirty(nil, function()
        return "partial", self.dialog_frame.dimen
    end)
end

function InputDialog:onShowKeyboard()
    if not self.readonly and not self.keyboard_hidden then
        self._input_widget:onShowKeyboard()
    end
end

function InputDialog:onClose()
    -- Remember current view & position in case of re-init
    self._top_line_num = self._input_widget.top_line_num
    self._charpos = self._input_widget.charpos
    if self.view_pos_callback then
        -- Give back top line num and cursor position
        self.view_pos_callback(self._top_line_num, self._charpos)
    end
    self._input_widget:onCloseKeyboard()
end

function InputDialog:refreshButtons()
    -- Using what ought to be enough:
    --   return "ui", self.button_table.dimen
    -- causes 2 non-intersecting refreshes (because if our buttons
    -- change, the text widget did) that may sometimes cause
    -- the button_table to become white.
    -- Safer to refresh the whole widget so the refreshes can
    -- be merged into one.
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:_backupRestoreButtons()
    -- In case of re-init(), keep backup of original buttons and restore them
    if self._buttons_backup_done then
        -- Move backup and override current, and re-create backup from original,
        -- to avoid duplicating the copy code)
        self.buttons = self._buttons_backup -- restore (we may restore 'nil')
    end
    if self.buttons then -- (re-)create backup
        self._buttons_backup = {} -- deep copy, except for the buttons themselves
        for i, row in ipairs(self.buttons) do
            if row then
                local row_copy = {}
                self._buttons_backup[i] = row_copy
                for j, b in ipairs(row) do
                    row_copy[j] = b
                end
            end
        end
    end
    self._buttons_backup_done = true
end

function InputDialog:_addSaveCloseButtons()
    if not self.buttons then
        self.buttons = {{}}
    end
    -- Add them to the end of first row
    local row = self.buttons[1]
    local button = function(id) -- shortcut for more readable code
        return self.button_table:getButtonById(id)
    end
    -- Callback to enable/disable Reset/Save buttons, for feedback when text modified
    self._buttons_edit_callback = function(edited)
        if self._text_modified and not edited then
            self._text_modified = false
            button("save"):disable()
            if button("reset") then button("reset"):disable() end
            self:refreshButtons()
        elseif edited and not self._text_modified then
            self._text_modified = true
            button("save"):enable()
            if button("reset") then button("reset"):enable() end
            self:refreshButtons()
        end
    end
    if self.reset_callback then
        -- if reset_callback provided, add button to restore
        -- test to some previous state
        table.insert(row, {
            text = self.reset_button_text or _("Reset"),
            id = "reset",
            enabled = self._text_modified,
            callback = function()
                -- Wrapped via Trapper, to allow reset_callback to use Trapper
                -- to show progress or ask questions while getting original content
                require("ui/trapper"):wrap(function()
                    local content, msg = self.reset_callback()
                    if content then
                        self:setInputText(content)
                        self._buttons_edit_callback(false)
                        UIManager:show(Notification:new{
                            text = msg or _("Text reset"),
                            timeout = 2
                        })
                    else -- nil content, assume failure and show msg
                        if msg ~= false then -- false allows for no InfoMessage
                            UIManager:show(InfoMessage:new{
                                text = msg or _("Resetting failed."),
                            })
                        end
                    end
                end)
            end,
        })
    end
    table.insert(row, {
        text = self.save_button_text or _("Save"),
        id = "save",
        enabled = self._text_modified,
        callback = function()
            -- Wrapped via Trapper, to allow save_callback to use Trapper
            -- to show progress or ask questions while saving
            require("ui/trapper"):wrap(function()
                if self._text_modified then
                    local success, msg = self.save_callback(self:getInputText())
                    if success == false then
                        if msg ~= false then -- false allows for no InfoMessage
                            UIManager:show(InfoMessage:new{
                                text = msg or _("Saving failed."),
                            })
                        end
                    else -- nil or true
                        self._buttons_edit_callback(false)
                        UIManager:show(Notification:new{
                            text = msg or _("Saved"),
                            timeout = 2
                        })
                    end
                end
            end)
        end,
    })
    table.insert(row, {
        text = self.close_button_text or _("Close"),
        id = "close",
        callback = function()
            if self._text_modified then
                UIManager:show(MultiConfirmBox:new{
                    text = self.close_unsaved_confirm_text or _("You have unsaved changes."),
                    cancel_text = self.close_cancel_button_text or _("Cancel"),
                    choice1_text = self.close_discard_button_text or _("Discard"),
                    choice1_callback = function()
                        if self.close_callback then self.close_callback() end
                        UIManager:close(self)
                        UIManager:show(Notification:new{
                            text = self.close_discarded_notif_text or _("Changes discarded"),
                            timeout = 2
                        })
                    end,
                    choice2_text = self.close_save_button_text or _("Save"),
                    choice2_callback = function()
                        -- Wrapped via Trapper, to allow save_callback to use Trapper
                        -- to show progress or ask questions while saving
                        require("ui/trapper"):wrap(function()
                            local success, msg = self.save_callback(self:getInputText(), true)
                            if success == false then
                                if msg ~= false then -- false allows for no InfoMessage
                                    UIManager:show(InfoMessage:new{
                                        text = msg or _("Saving failed."),
                                    })
                                end
                            else -- nil or true
                                if self.close_callback then self.close_callback() end
                                UIManager:close(self)
                                UIManager:show(Notification:new{
                                    text = msg or _("Saved"),
                                    timeout = 2
                                })
                            end
                        end)
                    end,
                })
            else
                -- Not modified, exit without any message
                if self.close_callback then self.close_callback() end
                UIManager:close(self)
            end
        end,
    })
end

function InputDialog:_addScrollButtons(nav_bar)
    local row
    if nav_bar then -- Add Home / End / Up / Down buttons as a last row
        if not self.buttons then
            self.buttons = {}
        end
        row = {} -- Empty additional buttons row
        table.insert(self.buttons, row)
    else -- Add the Up / Down buttons to the first row
        if not self.buttons then
            self.buttons = {{}}
        end
        row = self.buttons[1]
    end
    if nav_bar then -- Add the Home & End buttons
        -- Also add Keyboard hide/show button if we can
        if self.fullscreen and not self.readonly then
            table.insert(row, {
                text = self.keyboard_hidden and "↑⌨" or "↓⌨",
                id = "keyboard",
                callback = function()
                    self.keyboard_hidden = not self.keyboard_hidden
                    self.input = self:getInputText() -- re-init with up-to-date text
                    self:onClose() -- will close keyboard and save view position
                    self:free()
                    self:init()
                    if not self.keyboard_hidden then
                        self:onShowKeyboard()
                    end
                end,
            })
        end
        table.insert(row, {
            text = "⇱",
            id = "top",
            callback = function()
                self._input_widget:scrollToTop()
            end,
        })
        table.insert(row, {
            text = "⇲",
            id = "bottom",
            callback = function()
                self._input_widget:scrollToBottom()
            end,
        })
    end
    -- Add the Up & Down buttons
    table.insert(row, {
        text = "△",
        id = "up",
        callback = function()
            self._input_widget:scrollUp()
        end,
    })
    table.insert(row, {
        text = "▽",
        id = "down",
        callback = function()
            self._input_widget:scrollDown()
        end,
    })
    -- Callback to enable/disable buttons, for at-top/at-bottom feedback
    local prev_at_top = false -- Buttons were created enabled
    local prev_at_bottom = false
    local button = function(id) -- shortcut for more readable code
        return self.button_table:getButtonById(id)
    end
    self._buttons_scroll_callback = function(low, high)
        local changed = false
        if prev_at_top and low > 0 then
            button("up"):enable()
            if button("top") then button("top"):enable() end
            prev_at_top = false
            changed = true
        elseif not prev_at_top and low <= 0 then
            button("up"):disable()
            if button("top") then button("top"):disable() end
            prev_at_top = true
            changed = true
        end
        if prev_at_bottom and high < 1 then
            button("down"):enable()
            if button("bottom") then button("bottom"):enable() end
            prev_at_bottom = false
            changed = true
        elseif not prev_at_bottom and high >= 1 then
            button("down"):disable()
            if button("bottom") then button("bottom"):disable() end
            prev_at_bottom = true
            changed = true
        end
        if changed then
            self:refreshButtons()
        end
    end
end

return InputDialog
