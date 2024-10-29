--[[--
Widget for taking user input.

Example:

    local InputDialog = require("ui/widget/inputdialog")
    local @{ui.uimanager|UIManager} = require("ui/uimanager")
    local @{logger} = require("logger")
    local @{gettext|_} = require("gettext")

    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = "default value",
        -- A placeholder text shown in the text box.
        input_hint = _("Hint text"),
        -- input_type = nil, -- default for text
        -- A description shown above the input.
        description = _("Some more description."),
        -- text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
                        logger.dbg("Got user input as raw text:", sample_input:getInputText())
                        logger.dbg("Got user input as value:", sample_input:getInputValue())
                    end,
                },
            }
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()

To get a full screen text editor, use:
    fullscreen = true, -- No need to provide any height and width.
    condensed = true,
    allow_newline = true,
    cursor_at_end = false,
    -- and one of these:
    add_scroll_buttons = true,
    add_nav_bar = true,

To add |Save|Close| buttons, use:
    save_callback = function(content, closing)
        -- ...Deal with the edited content...
        if closing then
            UIManager:nextTick(
                -- Stuff to do when InputDialog is closed, if anything.
            )
        end
        return nil -- success, default notification shown
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
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputText = require("ui/widget/inputtext")
local MovableContainer = require("ui/widget/container/movablecontainer")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local T = require("ffi/util").template
local util = require("util")
local _ = require("gettext")

local InputDialog = FocusManager:extend{
    is_always_active = true,
    title = "",
    input = "",
    input_hint = "",
    description = nil,
    buttons = nil,
    input_type = nil,
    deny_keyboard_hiding = false, -- don't hide keyboard on tap outside
    enter_callback = nil,
    strike_callback = nil, -- call this on every keystroke
    inputtext_class = InputText, -- (Terminal plugin provides TermInputText)
    readonly = false, -- don't allow editing, will not show keyboard
    allow_newline = false, -- allow entering new lines (this disables any enter_callback)
    cursor_at_end = true, -- starts with cursor at end of text, ready for appending
    use_available_height = false, -- adjust input box to fill available height on screen
    fullscreen = false, -- adjust to full screen minus keyboard
    condensed = false, -- true will prevent adding air and balance between elements
    add_scroll_buttons = false, -- add scroll Up/Down buttons to first row of buttons
    add_nav_bar = false, -- append a row of page navigation buttons
        -- note that the text widget can be scrolled with Swipe North/South even when no button
    keyboard_visible = true, -- whether we start with the keyboard visible or not (i.e., our caller skipped onShowKeyboard)
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
                          -- (passed true/false if text modified and saved/discarded, nil if closed with text unmodified)
    edited_callback = nil,  -- Called on each text modification

    -- For use by TextEditor plugin:
    view_pos_callback = nil, -- Called with no args on init to retrieve top_line_num/charpos (however the caller chooses to do so, e.g., some will store it in a LuaSettings),
                             -- called with (top_line_num, charpos) on close to let the callback do its thing so that the no args branch spits back useful data..

    -- Set to false if movable gestures conflicts with subwidgets gestures
    is_movable = true,

    width = nil,

    text_width = nil,
    text_height = nil,

    bottom_v_padding = 0,
    input_face = Font:getFace("x_smallinfofont"),
    input_padding = Size.padding.default,
    input_margin = Size.margin.default,
    button_padding = Size.padding.default,
    border_size = Size.border.window,

    -- See TextBoxWidget for details about these options
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = false,
    alignment_strict = false,

    -- for internal use
    _keyboard_was_visible = nil, -- previous kb visibility state
    _text_modified = false, -- previous known modified status
    _top_line_num = nil,
    _charpos = nil,
    _buttons_edit_callback = nil,
    _buttons_scroll_callback = nil,
    _buttons_backup_done = false,
    _buttons_backup = nil,
}

function InputDialog:init()
    self.layout = {{}}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if self.fullscreen then
        self.is_movable = false
        self.border_size = 0
        self.width = self.screen_width - 2*self.border_size
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    else
        self.width = self.width or math.floor(math.min(self.screen_width, self.screen_height) * 0.8)
    end
    if self.condensed then
        self.text_width = self.width - 2*(self.border_size + self.input_padding + self.input_margin)
    else
        self.text_width = self.text_width or math.floor(self.width * 0.9)
    end
    if self.readonly then -- hide keyboard if we can't edit
        self.keyboard_visible = false
    end
    if self.fullscreen or self.add_nav_bar then
        self.deny_keyboard_hiding = true
    end
    if (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:isFalse("virtual_keyboard_enabled") then
        self.keyboard_visible = false
        self.skip_first_show_keyboard = true
    end

    -- Title & description
    self.title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        title_multilines = true,
        bottom_v_padding = self.bottom_v_padding,
        info_text = self.description,
        left_icon = self.title_bar_left_icon,
        left_icon_tap_callback = self.title_bar_left_icon_tap_callback,
        show_parent = self,
    }

    -- Vertical spaces added before and after InputText
    -- (these will be adjusted later to center the input text if needed)
    -- (can be disabled by setting condensed=true)
    local padding_width = self.condensed and 0 or Size.padding.default
    local vspan_before_input_text = VerticalSpan:new{ width = padding_width }
    local vspan_after_input_text = VerticalSpan:new{ width = padding_width }

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

    -- Remember provided text_height if any (to restore it on keyboard height change)
    if self.orig_text_height == nil then
        if self.text_height then
            self.orig_text_height = self.text_height
        else
            self.orig_text_height = false
        end
    end

    -- InputText
    if not self.text_height or self.fullscreen then
        -- We need to find the best height to avoid screen overflow
        -- Create a dummy input widget to get some metrics
        local input_widget = self.inputtext_class:new{
            text = self.fullscreen and "-" or self.input,
            input_type = self.input_type,
            face = self.input_face,
            width = self.text_width,
            padding = self.input_padding,
            margin = self.input_margin,
            lang = self.lang, -- these might influence height
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            for_measurement_only = true, -- flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        local text_height = input_widget:getTextHeight()
        local line_height = input_widget:getLineHeight()
        local input_pad_height = input_widget:getSize().h - text_height
        local keyboard_height = self.keyboard_visible and input_widget:getKeyboardDimen().h or 0
        input_widget:onCloseKeyboard() -- we don't want multiple VKs, as the show/hide tracking assumes there's only one
        input_widget:onCloseWidget() -- free() textboxwidget and keyboard
        -- Find out available height
        local available_height = self.screen_height
                                    - 2*self.border_size
                                    - self.title_bar:getHeight()
                                    - vspan_before_input_text:getSize().h
                                    - input_pad_height
                                    - vspan_after_input_text:getSize().h
                                    - buttons_container:getSize().h
                                    - keyboard_height
        if self.fullscreen or self.use_available_height or text_height > available_height then
            -- Don't leave unusable space in the text widget, as the user could think
            -- it's an empty line: move that space in pads after and below (for centering)
            self.text_height = math.floor(available_height / line_height) * line_height
            local pad_height = available_height - self.text_height
            local pad_before = math.ceil(pad_height / 2)
            local pad_after = pad_height - pad_before
            vspan_before_input_text.width = vspan_before_input_text.width + pad_before
            vspan_after_input_text.width = vspan_after_input_text.width + pad_after
            if text_height > available_height then
                self.cursor_at_end = false -- stay at start if overflowed
            end
        else
            -- Don't leave unusable space in the text widget
            self.text_height = text_height
        end
    end
    if self.view_pos_callback then
        -- Retrieve cursor position and top line num from our callback.
        -- Mainly used for runtime re-inits.
        -- c.f., our onClose handler for the other end of this.
        -- *May* return nils, in which case, we do *not* want to override our caller's values!
        local top_line_num, charpos = self.view_pos_callback()
        if top_line_num and charpos then
            self._top_line_num, self._charpos = top_line_num, charpos
        end
    end
    self.enter_callback = self.enter_callback or function()
        for _, btn_row in ipairs(self.buttons) do
            for _, btn in ipairs(btn_row) do
                if btn.is_enter_default then
                    btn.callback()
                    return
                end
            end
        end
    end
    -- In case of reinit, murder our previous input widget to prevent stale VK instances from lingering
    if self._input_widget then
        self._input_widget:onCloseWidget()
    end
    self._input_widget = self.inputtext_class:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
        width = self.text_width,
        height = self.text_height or nil,
        padding = self.input_padding,
        margin = self.input_margin,
        input_type = self.input_type,
        text_type = self.text_type,
        enter_callback = not self.allow_newline and self.enter_callback,
        strike_callback = self.strike_callback,
        edit_callback = self._buttons_edit_callback or self.edited_callback, -- self._buttons_edit_callback is nil if no Save/Close buttons
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
    table.insert(self.layout[1], self._input_widget)
    self:mergeLayoutInVertical(self.button_table)
    -- NOTE: Never send a Focus event, as, on hasDPad device, InputText's onFocus *will* call onShowKeyboard,
    --       and that will wreak havoc on toggleKeyboard...
    --       Plus, the widget at (1, 1) will not have changed, so we don't actually need to change the visual focus anyway?
    -- If it turns out something actually needed this, make this conditional on a new `reinit` arg passed to `init`, for toggleKeyboard & co.
    self:refocusWidget(FocusManager.RENDER_NOW, FocusManager.NOT_FOCUS)
    -- Complementary setup for some of our added buttons
    if self.save_callback then
        local save_button = self.button_table:getButtonById("save")
        if self.readonly then
            save_button:setText(_("Read only"), save_button.width)
        elseif not self._input_widget:isTextEditable() then
            save_button:setText(_("Not editable"), save_button.width)
        end
    end
    if self.add_nav_bar then
        self.curr_line_num = self._input_widget:getLineNums()
        self.go_button = self.button_table:getButtonById("go")
        self.go_button:setText("\u{250B}\u{202F}" .. self.curr_line_num, self.go_button.width)
    end

    -- Combine all
    self.vgroup = VerticalGroup:new{
        align = "left",
        self.title_bar,
        vspan_before_input_text,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = self._input_widget:getSize().h,
            },
            self._input_widget,
        },
        -- added widgets may be inserted here
        vspan_after_input_text,
        buttons_container,
    }

    -- Final widget
    self.dialog_frame = FrameContainer:new{
        radius = self.fullscreen and 0 or Size.radius.window,
        padding = 0,
        margin = 0,
        bordersize = self.border_size,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
    }
    local frame = self.dialog_frame
    if self.is_movable then
        self.movable = MovableContainer:new{ -- (UIManager expects this as 'self.movable')
            self.dialog_frame,
        }
        frame = self.movable
    end
    local keyboard_height = self.keyboard_visible and self._input_widget:getKeyboardDimen().h or 0
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = self.screen_width,
            h = self.screen_height - keyboard_height,
        },
        ignore_if_over = "height",
        frame,
    }
    if Device:isTouchDevice() then -- is used to hide the keyboard with a tap outside of inputbox
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    w = self.screen_width,
                    h = self.screen_height,
                },
            },
        }
    end
    if Device:hasKeys() then
        self.key_events.CloseDialog = { { Device.input.group.Back } }
    end
    if self._added_widgets then
        for _, widget in ipairs(self._added_widgets) do
            self:addWidget(widget, true)
        end
    end

    -- If we're fullscreen without the virtual keyboard, make sure only the toggle button can bring back the keyboard...
    if self.fullscreen and not self.keyboard_visible then
        self:lockKeyboard(true)
    end
end

function InputDialog:reinit()
    local visible = self:isKeyboardVisible()
    self.input = self:getInputText() -- re-init with up-to-date text
    self:onClose() -- will close keyboard and save view position
    self._input_widget:onCloseWidget() -- proper cleanup of InputText and its keyboard
    if self._added_widgets then
        -- prevent these externally added widgets from being freed as :init() will re-add them
        for i = 1, #self._added_widgets do
            table.remove(self.vgroup, #self.vgroup-2)
        end
    end
    self:free()
    -- Restore original text_height (or reset it if none to force recomputing it)
    self.text_height = self.orig_text_height or nil

    -- Same deal as in toggleKeyboard...
    self.keyboard_visible = visible and true or false
    self:init()
    if self.keyboard_visible then
        self:onShowKeyboard()
    end
    -- Our position on screen has probably changed, so have the full screen refreshed
    UIManager:setDirty("all", "flashui")
end

function InputDialog:addWidget(widget, re_init)
    table.insert(self.layout, #self.layout, {widget})
    if not re_init then -- backup widget for re-init
        widget = CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget:getSize().h,
            },
            widget,
        }
        if not self._added_widgets then
            self._added_widgets = {}
        end
        table.insert(self._added_widgets, widget)
    end
    -- insert widget before the bottom buttons and their previous vspan
    table.insert(self.vgroup, #self.vgroup-1, widget)
end

function InputDialog:getAddedWidgetAvailableWidth()
    return self._input_widget.width
end

-- Tap outside of inputbox to hide the keyboard (inside the inputbox it is caught via InputText:onTapTextBox).
-- If the keyboard is hidden, tap outside of the dialog to close the dialog.
function InputDialog:onTap(arg, ges)
    -- This is slightly more fine-grained than VK's own visibility lock, hence the duplication...
    if self.deny_keyboard_hiding then
        return
    end
    if self:isKeyboardVisible() then
        -- NOTE: While VirtualKey will attempt to cover the gap between keys in its hitbox (i.e., the grey border),
        --       a tap *may* still fall outside of the ges_events range of a VirtualKey (e.g., on the very edges of the board's frame).
        --       In which case, since we're flagged is_always_active, it goes to us,
        --       so we'll have to double check that it wasn't inside of the whole VirtualKeyboard region,
        --       otherwise we'd risk spuriously closing the keyboard ;p.
        -- Poke at keyboard_frame directly, as the top-level dimen never gets updated coordinates...
        if self._input_widget.keyboard and self._input_widget.keyboard.dimen and ges.pos:notIntersectWith(self._input_widget.keyboard.dimen) then
            self:onCloseKeyboard()
        end
    else
        if ges.pos:notIntersectWith(self.dialog_frame.dimen) then
            self:onCloseDialog()
        end
    end
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

function InputDialog:setInputText(text, edited_state, cursor_at_start_or_end)
    self._input_widget:setText(text)
    if edited_state ~= nil and self._buttons_edit_callback then
        self._buttons_edit_callback(edited_state)
    end
    if cursor_at_start_or_end ~= nil then -- true=start, false=end
        if cursor_at_start_or_end then
            self._input_widget:scrollToTop()
        else
            self._input_widget:scrollToBottom()
        end
    end
end

function InputDialog:addTextToInput(text)
    return self._input_widget:addChars(text)
end

function InputDialog:isTextEditable()
    return self._input_widget:isTextEditable()
end

function InputDialog:isTextEdited()
    return self._input_widget:isTextEdited()
end

function InputDialog:setAllowNewline(allow)
    self.allow_newline = allow
    self._input_widget.enter_callback = not allow and self.enter_callback
end

function InputDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onCloseWidget()
    self:onClose()
    UIManager:setDirty(nil, self.fullscreen and "full" or function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onShowKeyboard(ignore_first_hold_release)
    -- Don't initiate virtual keyboard when user has a physical keyboard and G_setting(vk_enabled) unchecked.
    if self.skip_first_show_keyboard then
        self.skip_first_show_keyboard = nil
        return
    end
    -- NOTE: There's no VirtualKeyboard widget instantiated at all when readonly,
    --       and our input widget handles that itself, so we don't need any guards here.
    --       (In which case, isKeyboardVisible will return `nil`, same as if we had a VK instantiated but *never* shown).
    self._input_widget:onShowKeyboard(ignore_first_hold_release)
    -- There's a bit of a chicken or egg issue in init where we would like to check the actual keyboard's visibility state,
    -- but the widget might not exist or be shown yet, so we'll just have to keep this in sync...
    self.keyboard_visible = self._input_widget:isKeyboardVisible()
end

function InputDialog:onCloseKeyboard()
    self._input_widget:onCloseKeyboard()
    self.keyboard_visible = self._input_widget:isKeyboardVisible()
end

function InputDialog:isKeyboardVisible()
    return self._input_widget:isKeyboardVisible()
end

function InputDialog:lockKeyboard(toggle)
    if (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:isFalse("virtual_keyboard_enabled") then
        -- do not lock the virtual keyboard when user is hiding it, we still *might* want to activate it via shortcuts ("Shift" + "Home") when in need of special characters or symbols
        return
    end
    return self._input_widget:lockKeyboard(toggle)
end

-- NOTE: Only called by fullscreen and/or add_nav_bar codepaths
--       We do not currently have !fullscreen add_nav_bar callers...
function InputDialog:toggleKeyboard(force_toggle)
    -- Remember the *current* visibility, as the following close will reset it
    local visible = self:isKeyboardVisible()

    -- When we forcibly close the keyboard, remember its current visiblity state, so that we can properly restore it later.
    -- (This is used by some buttons in fullscreen mode, where we might want to keep the original keyboard hidden when popping up a new one for another InputDialog).
    if force_toggle == false then
        -- NOTE: visible will be nil between our own init and a show of the keyboard, which is precisely what happens when we *hide* the keyboard.
        self._keyboard_was_visible = visible == true
    end

    self.input = self:getInputText() -- re-init with up-to-date text
    self:onClose() -- will close keyboard and save view position
    self:free()

    if force_toggle == false and not visible then
        -- Already hidden, bye!
        return
    end

    -- Init needs to know the keyboard's visibility state *before* the widget is actually shown...
    if force_toggle == true then
        self.keyboard_visible = true
    elseif force_toggle == false then
        self.keyboard_visible = false
    elseif self._keyboard_was_visible ~= nil then
        self.keyboard_visible = self._keyboard_was_visible
        self._keyboard_was_visible = nil
    else
        self.keyboard_visible = not visible
    end
    self:init()

    -- NOTE: If we ever have non-fullscreen add_nav_bar callers, it might make sense *not* to lock the keyboard there?
    if self.keyboard_visible then
        self:lockKeyboard(false)
        self:onShowKeyboard()
    else
        self:onCloseKeyboard()
        -- Prevent InputText:onTapTextBox from opening the keyboard back up on top of our buttons
        self:lockKeyboard(true)
    end

    -- Clear the FocusManager highlight, because that gets lost in the mess somehow...
    self.button_table:getButtonById("keyboard"):onUnfocus()

    -- Make sure we refresh the nav bar, as it will have moved, and it belongs to us, not to VK or our input widget...
    self:refreshButtons()
end

-- fullscreen mode & add_nav_bar breaks some of our usual assumptions about what should happen on "Back" input events...
function InputDialog:onKeyboardClosed()
    if self.add_nav_bar and self.fullscreen then
        -- If the keyboard was closed via a key event (Back), make sure we reinit properly like in toggleKeyboard...
        self.input = self:getInputText()
        self:onClose()
        self:free()

        self:init()

        self:refreshButtons()
    end
end

InputDialog.onKeyboardHeightChanged = InputDialog.reinit

function InputDialog:onCloseDialog()
    local close_button = self.button_table:getButtonById("close")
    if close_button and close_button.enabled then
        close_button.callback()
        return true
    end
    return false
end

function InputDialog:onClose()
    -- Tell our input widget to poke its text widget so that we'll pickup up to date values
    self._input_widget:resyncPos()
    -- Remember current view & position in case of re-init
    self._top_line_num = self._input_widget.top_line_num
    self._charpos = self._input_widget.charpos
    if self.view_pos_callback then
        -- This lets the caller store/process the current top line num and cursor position via this callback
        self.view_pos_callback(self._top_line_num, self._charpos)
    end
    self:onCloseKeyboard()
end

function InputDialog:onSetRotationMode(mode)
    if self.rotation_enabled and mode ~= nil then -- Text editor only
        self.rotation_mode_backup = self.rotation_mode_backup or Screen:getRotationMode() -- backup only initial mode
        Screen:setRotationMode(mode)
        self:reinit()
        return true -- we are the upper widget, stop event propagation
    end
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
            if self.reset_callback then button("reset"):disable() end
            self:refreshButtons()
        elseif edited and not self._text_modified then
            self._text_modified = true
            button("save"):enable()
            if self.reset_callback then button("reset"):enable() end
            self:refreshButtons()
        end
        if self.edited_callback then
            self.edited_callback(edited)
        end
    end
    if self.reset_callback then
        -- if reset_callback provided, add button to restore
        -- text to some previous state
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
                        if self.close_callback then self.close_callback(false) end
                        UIManager:close(self)
                        UIManager:show(Notification:new{
                            text = self.close_discarded_notif_text or _("Changes discarded"),
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
                                if self.close_callback then self.close_callback(true) end
                                UIManager:close(self)
                                UIManager:show(Notification:new{
                                    text = msg or _("Saved"),
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
                text = self.keyboard_visible and "↓⌨" or "↑⌨",
                id = "keyboard",
                callback = function()
                    self:toggleKeyboard()
                end,
            })
        end
        if self.fullscreen then
            -- Add a button to search for a string in the edited text
            table.insert(row, {
                text = _("Find"),
                callback = function()
                    self:toggleKeyboard(false) -- hide text editor keyboard
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter text to search for"),
                        stop_events_propagation = true, -- avoid interactions with upper InputDialog
                        input = self.search_value,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                        self:toggleKeyboard()
                                    end,
                                },
                                {
                                    text = _("Find first"),
                                    callback = function()
                                        self:findCallback(input_dialog, true)
                                    end,
                                },
                                {
                                    text = _("Find next"),
                                    is_enter_default = true,
                                    callback = function()
                                        self:findCallback(input_dialog)
                                    end,
                                },
                            },
                        },
                    }

                    self.check_button_case = CheckButton:new{
                        text = _("Case sensitive"),
                        checked = self.case_sensitive,
                        parent = input_dialog,
                        callback = function()
                            self.case_sensitive = self.check_button_case.checked
                        end,
                    }
                    input_dialog:addWidget(self.check_button_case)

                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            })
            -- Add a button to go to the line by its number in the file
            table.insert(row, {
                text = "", -- current line number
                font_bold = false,
                id = "go",
                callback = function()
                    self:toggleKeyboard(false) -- hide text editor keyboard
                    local curr_line_num, last_line_num = self._input_widget:getLineNums()
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter line number"),
                        -- @translators %1 is the current line number, %2 is the last line number
                        input_hint = T(_("%1 (1 - %2)"), curr_line_num, last_line_num),
                        input_type = "number",
                        stop_events_propagation = true, -- avoid interactions with upper InputDialog
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                        self:toggleKeyboard()
                                    end,
                                },
                                {
                                    text = _("Go to line"),
                                    is_enter_default = true,
                                    callback = function()
                                        local new_line_num = input_dialog:getInputValue()
                                        if new_line_num and new_line_num >= 1 and new_line_num <= last_line_num then
                                            UIManager:close(input_dialog)
                                            self:toggleKeyboard()
                                            self._input_widget:moveCursorToCharPos(self._input_widget:getLineCharPos(new_line_num))
                                        end
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            })
        end
        table.insert(row, {
            text = "⇱",
            id = "top",
            vsync = true,
            callback = function()
                self._input_widget:scrollToTop()
            end,
        })
        table.insert(row, {
            text = "⇲",
            id = "bottom",
            vsync = true,
            callback = function()
                self._input_widget:scrollToBottom()
            end,
        })
        self.strike_callback = function()
            if self._input_widget then
                local curr_line_num = self._input_widget:getLineNums()
                if self.curr_line_num ~= curr_line_num then
                    self.curr_line_num = curr_line_num
                    self.go_button:setText("\u{250B}\u{202F}" .. curr_line_num, self.go_button.width)
                    self.go_button:refresh()
                end
            end
        end
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
            if nav_bar then button("top"):enable() end
            prev_at_top = false
            changed = true
        elseif not prev_at_top and low <= 0 then
            button("up"):disable()
            if nav_bar then button("top"):disable() end
            prev_at_top = true
            changed = true
        end
        if prev_at_bottom and high < 1 then
            button("down"):enable()
            if nav_bar then button("bottom"):enable() end
            prev_at_bottom = false
            changed = true
        elseif not prev_at_bottom and high >= 1 then
            button("down"):disable()
            if nav_bar then button("bottom"):disable() end
            prev_at_bottom = true
            changed = true
        end
        if changed then
            self:refreshButtons()
        end
    end
end

function InputDialog:findCallback(input_dialog, find_first)
    self.search_value = input_dialog:getInputText()
    if self.search_value == "" then return end
    UIManager:close(input_dialog)
    self:toggleKeyboard()
    local start_pos = find_first and 1 or self._charpos + 1
    local char_pos = util.stringSearch(self.input, self.search_value, self.case_sensitive, start_pos)
    local msg
    if char_pos > 0 then
        self._input_widget:moveCursorToCharPos(char_pos)
        msg = T(_("Found in line %1."), self.curr_line_num)
    else
        msg = _("Not found.")
    end
    UIManager:show(Notification:new{
        text = msg,
    })
end

return InputDialog
