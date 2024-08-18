--[[--
Displays some text in a scrollable view.

@usage
    local textviewer = TextViewer:new{
        title = _("I can scroll!"),
        text = _("I'll need to be longer than this example to scroll."),
    }
    UIManager:show(textviewer)
]]
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification = require("ui/widget/notification")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local TextViewer = InputContainer:extend{
    title = nil,
    text = nil,
    charlist = nil, -- internal
    width = nil,
    height = nil,
    buttons_table = nil,
    -- See TextBoxWidget for details about these options
    -- We default to justified and auto_para_direction to adapt
    -- to any kind of text we are given (book descriptions,
    -- bookmarks' text, translation results...).
    -- When used to display more technical text (HTML, CSS,
    -- application logs...), it's best to reset them to false.
    alignment = "left",
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = true,
    alignment_strict = false,

    title_face = nil, -- use default from TitleBar
    title_multilines = nil, -- see TitleBar for details
    title_shrink_font_to_fit = nil, -- see TitleBar for details

    show_menu = true, -- titlebar left icon
    monospace_font = nil, -- internal
    text_font_size = nil, -- internal
    justified = nil, -- internal

    fgcolor = Blitbuffer.COLOR_BLACK,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
    -- Bottom row with Close, Find buttons. Also added when no caller's buttons defined.
    add_default_buttons = nil,
    default_hold_callback = nil, -- on each default button
    find_centered_lines_count = 5, -- line with find results to be not far from the center

    text_type = "general",
    text_types = {
        general      = { monospace_font = false, font_size = 20, justified = false },
        file_content = { monospace_font = false, font_size = 20, justified = false },
        book_info    = { monospace_font = false, font_size = 20, justified =  true },
        bookmark     = { monospace_font = false, font_size = 20, justified =  true },
        lookup       = { monospace_font = false, font_size = 20, justified = false },
        code         = { monospace_font =  true, font_size = 16, justified = false },
    },
}

function TextViewer:init(reinit)
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    self.align = "center"
    self.region = Geom:new{
        w = screen_w,
        h = screen_h,
    }
    self.width = self.width or screen_w - Screen:scaleBySize(30)
    self.height = self.height or screen_h - Screen:scaleBySize(30)

    if not reinit then
        local text_types = G_reader_settings:readSetting("textviewer_text_types")
        local text_settings = text_types and text_types[self.text_type] or self.text_types[self.text_type]
        self.monospace_font = text_settings.monospace_font
        self.text_font_size = text_settings.font_size
        self.justified      = text_settings.justified
    end
    local text_font_face = self.monospace_font and "smallinfont" or "x_smallinfofont"

    self._find_next = false
    self._find_next_button = false
    self._old_virtual_line_num = 1

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.ShowMenu = { { "Menu" } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new{
            w = screen_w,
            h = screen_h,
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = range,
                },
            },
            MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = range,
                },
            },
            -- Allow selection of one or more words (see textboxwidget.lua):
            HoldStartText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldReleaseText = {
                GestureRange:new{
                    ges = "hold_release",
                    range = range,
                },
                -- callback function when HoldReleaseText is handled as args
                args = function(text, hold_duration, start_idx, end_idx, to_source_index_func)
                    self:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end

    self.titlebar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        title_face = self.title_face,
        title_multilines = self.title_multilines,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        left_icon = self.show_menu and "appbar.menu",
        left_icon_tap_callback = function() self:onShowMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    -- Callback to enable/disable buttons, for at-top/at-bottom feedback
    local prev_at_top = false -- Buttons were created enabled
    local prev_at_bottom = false
    local function button_update(id, enable)
        local button = self.button_table:getButtonById(id)
        if button then
            if enable then
                button:enable()
            else
                button:disable()
            end
            button:refresh()
        end
    end
    self._buttons_scroll_callback = function(low, high)
        if prev_at_top and low > 0 then
            button_update("top", true)
            prev_at_top = false
        elseif not prev_at_top and low <= 0 then
            button_update("top", false)
            prev_at_top = true
        end
        if prev_at_bottom and high < 1 then
            button_update("bottom", true)
            prev_at_bottom = false
        elseif not prev_at_bottom and high >= 1 then
            button_update("bottom", false)
            prev_at_bottom = true
        end
    end

    -- buttons
    local default_buttons =
        {
            {
                text = _("Find"),
                id = "find",
                callback = function()
                    if self._find_next then
                        self:findCallback()
                    else
                        self:findDialog()
                    end
                end,
                hold_callback = function()
                    if self._find_next then
                        self:findDialog()
                    else
                        if self.default_hold_callback then
                            self.default_hold_callback()
                        end
                    end
                end,
            },
            {
                text = "⇱",
                id = "top",
                callback = function()
                    self.scroll_text_w:scrollToTop()
                end,
                hold_callback = self.default_hold_callback,
                allow_hold_when_disabled = true,
            },
            {
                text = "⇲",
                id = "bottom",
                callback = function()
                    self.scroll_text_w:scrollToBottom()
                end,
                hold_callback = self.default_hold_callback,
                allow_hold_when_disabled = true,
            },
            {
                text = _("Close"),
                callback = function()
                    self:onClose()
                end,
                hold_callback = self.default_hold_callback,
            },
        }
    local buttons = self.buttons_table or {}
    if (self.add_default_buttons and not reinit) or not self.buttons_table then
        table.insert(buttons, default_buttons)
    end
    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    -- NT: add titlebar.left_button (hamburger menu) to FocusManager.
    if Device:hasDPad() and not (Device:hasSymKey() or Device:hasScreenKB()) then
        table.insert(self.button_table.layout, 1, { self.titlebar.left_button })
        -- Refocus on the updated layout
        self.button_table:refocusWidget()
    end

    local textw_height = self.height - self.titlebar:getHeight() - self.button_table:getSize().h

    self.scroll_text_w = ScrollTextWidget:new{
        text = self.text,
        face = Font:getFace(text_font_face, self.text_font_size),
        fgcolor = self.fgcolor,
        width = self.width - 2*self.text_padding - 2*self.text_margin,
        height = textw_height - 2*self.text_padding -2*self.text_margin,
        dialog = self,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
        scroll_callback = self._buttons_scroll_callback,
    }
    self.textw = FrameContainer:new{
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w
    }

    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.titlebar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            }
        }
    }
    self.movable = MovableContainer:new{
        -- We'll handle these events ourselves, and call appropriate
        -- MovableContainer's methods when we didn't process the event
        ignore_events = {
            -- These have effects over the text widget, and may
            -- or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            -- These do not have direct effect over the text widget,
            -- but may happen while selecting text: we need to check
            -- a few things before forwarding them
            "touch", "pan", "pan_release",
        },
        self.frame,
    }
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }
end

function TextViewer:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
end

function TextViewer:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    return true
end

function TextViewer:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function TextViewer:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function TextViewer:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function TextViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        else
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
    end
    -- Let our MovableContainer handle swipe outside of text
    return self.movable:onMovableSwipe(arg, ges)
end

-- The following handlers are similar to the ones in DictQuickLookup:
-- we just forward to our MoveableContainer the events that our
-- TextBoxWidget has not handled with text selection.
function TextViewer:onHoldStartText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function TextViewer:onHoldPanText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    -- We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function TextViewer:onHoldReleaseText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

-- These 3 event processors are just used to forward these events
-- to our MovableContainer, under certain conditions, to avoid
-- unwanted moves of the window while we are selecting text in
-- the definition widget.
function TextViewer:onForwardingTouch(arg, ges)
    -- This Touch may be used as the Hold we don't get (for example,
    -- when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.textw.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        -- Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function TextViewer:onForwardingPan(arg, ges)
    -- We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function TextViewer:onForwardingPanRelease(arg, ges)
    -- Allow scrolling with the mousewheel
    if ges.from_mousewheel and ges.relative and ges.relative.y then
        if ges.relative.y < 0 then
            self.scroll_text_w:scrollText(1)
        elseif ges.relative.y > 0 then
            self.scroll_text_w:scrollText(-1)
        end
        return true
    end
    -- We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end

function TextViewer:findDialog()
    local input_dialog, check_button_case
    input_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        input = self.search_value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Find first"),
                    callback = function()
                        self._find_next = false
                        self:findCallback(input_dialog)
                    end,
                },
                {
                    text = _("Find next"),
                    is_enter_default = true,
                    callback = function()
                        self._find_next = true
                        self:findCallback(input_dialog)
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = input_dialog,
        callback = function()
            self.case_sensitive = check_button_case.checked
        end,
    }
    input_dialog:addWidget(check_button_case)

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard(true)
end

function TextViewer:findCallback(input_dialog)
    if input_dialog then
        self.search_value = input_dialog:getInputText()
        if self.search_value == "" then return end
        UIManager:close(input_dialog)
    end
    local start_pos = 1
    if self._find_next then
        local charpos, new_virtual_line_num = self.scroll_text_w:getCharPos()
        if math.abs(new_virtual_line_num - self._old_virtual_line_num) > self.find_centered_lines_count then
            start_pos = self.scroll_text_w:getCharPosAtXY(0, 0) -- first char of the top line
        else
            start_pos = (charpos or 0) + 1 -- previous search result
        end
    end
    local char_pos, search_charlist
    char_pos, self.charlist, search_charlist =
        util.stringSearch(self.charlist or self.text, self.search_value, self.case_sensitive, start_pos)
    local msg
    if char_pos > 0 then
        self:setTextBold(char_pos, #search_charlist)
        self.scroll_text_w:moveCursorToCharPos(char_pos, self.find_centered_lines_count)
        msg = T(_("Found, screen line %1."), self.scroll_text_w:getCharPosLineNum())
        self._find_next = true
        self._old_virtual_line_num = select(2, self.scroll_text_w:getCharPos())
    else
        msg = _("Not found.")
        self._find_next = false
        self._old_virtual_line_num = 1
    end
    UIManager:show(Notification:new{
        text = msg,
    })
    if self._find_next_button ~= self._find_next then
        self._find_next_button = self._find_next
        local button_text = self._find_next and _("Find next") or _("Find")
        local find_button = self.button_table:getButtonById("find")
        find_button:setText(button_text, find_button.width)
        find_button:refresh()
    end
end

function TextViewer:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
    if self.text_selection_callback then
        self.text_selection_callback(text, hold_duration, start_idx, end_idx, to_source_index_func)
        return
    end
    if Device:hasClipboard() then
        Device.input.setClipboardText(text)
        UIManager:show(Notification:new{
            text = start_idx == end_idx and _("Word copied to clipboard.")
                                         or _("Selection copied to clipboard."),
        })
    end
end

function TextViewer:reinit()
    local text_settings = G_reader_settings:readSetting("textviewer_text_types", {})
    text_settings[self.text_type] = { monospace_font = self.monospace_font, font_size = self.text_font_size, justified = self.justified }
    local low, high = self.scroll_text_w.text_widget:getVisibleHeightRatios() -- try to keep position
    local ratio = low == 0 and 0 or (low + high) / 2 -- if we are at the beginning, keep the first line visible
    self:init(true) -- do not add default buttons once more
    UIManager:setDirty("all", "partial", self.frame.dimen)
    self.scroll_text_w:scrollToRatio(ratio, ratio == 0)
end

function TextViewer:setTextBold(start_pos, len)
    local end_pos = start_pos + len
    local text = self.text
    if self.charlist == nil then
        self.charlist = util.splitToChars(text)
    end
    local charlist = { TextBoxWidget.PTF_HEADER }
    for i, char in ipairs(self.charlist) do
        if i == start_pos then
            table.insert(charlist, TextBoxWidget.PTF_BOLD_START)
        elseif i == end_pos then
            table.insert(charlist, TextBoxWidget.PTF_BOLD_END)
        end
        table.insert(charlist, char)
    end
    self.text = table.concat(charlist)
    self:reinit()
    self.text = text -- restore original text
end

function TextViewer:onShowMenu()
    local dialog
    local buttons = {
        {{
            text_func = function()
                return T(_("Font size: %1"), self.text_font_size)
            end,
            align = "left",
            callback = function()
                UIManager:close(dialog)
                local SpinWidget = require("ui/widget/spinwidget")
                local widget = SpinWidget:new{
                    title_text = _("Font size"),
                    value = self.text_font_size,
                    value_min = 12,
                    value_max = 30,
                    default_value = self.monospace_font and 16 or 20,
                    keep_shown_on_apply = true,
                    callback = function(spin)
                        self.text_font_size = spin.value
                        self:reinit()
                    end,
                }
                UIManager:show(widget)
            end,
        }},
        {{
            text = _("Monospace font"),
            checked_func = function()
                return self.monospace_font
            end,
            align = "left",
            callback = function()
                self.monospace_font = not self.monospace_font
                self:reinit()
            end,
        }},
        {{
            text = _("Justify"),
            checked_func = function()
                return self.justified
            end,
            align = "left",
            callback = function()
                self.justified = not self.justified
                self:reinit()
            end,
        }},
    }
    dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.titlebar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

-- Register DocumentRegistry auxiliary provider.
function TextViewer:register(registry)
    registry:addAuxProvider({
        provider_name = _("Text viewer"),
        provider = "textviewer",
        order = 20, -- order in OpenWith dialog
        enabled_func = function()
            return true -- all files
        end,
        callback = TextViewer.openFile,
        disable_file = true,
        disable_type = false,
    })
end

function TextViewer.openFile(file)
    local function _openFile(file_path)
        local file_handle = io.open(file_path, "rb")
        if not file_handle then return end
        local file_content = file_handle:read("*all")
        file_handle:close()
        UIManager:show(TextViewer:new{
            title = file_path,
            title_multilines = true,
            text = file_content,
            text_type = "file_content",
        })
    end
    local attr = lfs.attributes(file)
    if attr then
        if attr.size > 400000 then
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = T(_("This file is %2:\n\n%1\n\nAre you sure you want to open it?\n\nOpening big files may take some time."),
                    BD.filepath(file), util.getFriendlySize(attr.size)),
                ok_text = _("Open"),
                ok_callback = function()
                    _openFile(file)
                end,
            })
        else
            _openFile(file)
        end
    end
end

return TextViewer
