local BD = require("ui/bidi")
local BlitBuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local logger = require("logger")
local util = require("util")
local Size = require("ui/size")
local ffiUtil = require("ffi/util")
local time = require("ui/time")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = ffiUtil.template
local Screen = Device.screen

local ReaderHighlight = InputContainer:extend{
    -- Matches what is available in BlitBuffer.HIGHLIGHT_COLORS
    highlight_colors = {
        {_("Red"), "red"},
        {_("Orange"), "orange"},
        {_("Yellow"), "yellow"},
        {_("Green"), "green"},
        {_("Olive"), "olive"},
        {_("Cyan"), "cyan"},
        {_("Blue"), "blue"},
        {_("Purple"), "purple"},
        {_("Gray"), "gray"},
    },
}

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
end

function ReaderHighlight:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.select_mode = false -- extended highlighting
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self._previous_indicator_pos = nil
    self._last_indicator_move_args = {dx = 0, dy = 0, distance = 0, time = time:now()}
    self._fallback_drawer = self.view.highlight.saved_drawer -- "lighten"
    self._fallback_color = self.view.highlight.saved_color -- "yellow" or "gray"

    self:registerKeyEvents()

    self._highlight_buttons = {
        -- highlight and add_note are for the document itself,
        -- so we put them first.
        ["01_select"] = function(this)
            return {
                text = _("Select"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:startSelection()
                    this:onClose()
                end,
            }
        end,
        ["02_highlight"] = function(this)
            return {
                text = _("Highlight"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:saveHighlight(true)
                    this:onClose()
                end,
            }
        end,
        ["03_copy"] = function(this)
            return {
                text = C_("Text", "Copy"),
                enabled = Device:hasClipboard(),
                callback = function()
                    Device.input.setClipboardText(util.cleanupSelectedText(this.selected_text.text))
                    this:onClose()
                    UIManager:show(Notification:new{
                        text = _("Selection copied to clipboard."),
                    })
                end,
            }
        end,
        ["04_add_note"] = function(this)
            return {
                text = _("Add note"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:addNote()
                    this:onClose()
                end,
            }
        end,
        -- then information lookup functions, putting on the left those that
        -- depend on an internet connection.
        ["05_wikipedia"] = function(this)
            return {
                text = _("Wikipedia"),
                callback = function()
                    UIManager:scheduleIn(0.1, function()
                        this:lookupWikipedia()
                        -- We don't call this:onClose(), we need the highlight
                        -- to still be there, as we may Highlight it from the
                        -- dict lookup widget.
                    end)
                end,
            }
        end,
        ["06_dictionary"] = function(this)
            return {
                text = _("Dictionary"),
                callback = function()
                    this:onHighlightDictLookup()
                    -- We don't call this:onClose(), same reason as above
                end,
            }
        end,
        ["07_translate"] = function(this, index)
            return {
                text = _("Translate"),
                callback = function()
                    this:translate(index)
                    -- We don't call this:onClose(), so one can still see
                    -- the highlighted text when moving the translated
                    -- text window, and also if NetworkMgr:promptWifiOn()
                    -- is needed, so the user can just tap again on this
                    -- button and does not need to select the text again.
                end,
            }
        end,
        -- buttons 08-11 are conditional ones, so the number of buttons can be even or odd
        -- let the Search button be the last, occasionally narrow or wide, less confusing
        ["12_search"] = function(this)
            return {
                text = _("Search"),
                callback = function()
                    this:onHighlightSearch()
                    -- We don't call this:onClose(), crengine will highlight
                    -- search matches on the current page, and self:clear()
                    -- would redraw and remove crengine native highlights
                end,
            }
        end,
    }

    -- Android devices
    if Device:canShareText() then
        local action = _("Share Text")
        self:addToHighlightDialog("08_share_text", function(this)
            return {
                text = action,
                callback = function()
                    local text = util.cleanupSelectedText(this.selected_text.text)
                    -- call self:onClose() before calling the android framework
                    this:onClose()
                    Device:doShareText(text, action)
                end,
            }
        end)
    end

    -- cre documents only
    if not self.document.info.has_pages then
        self:addToHighlightDialog("09_view_html", function(this)
            return {
                text = _("View HTML"),
                callback = function()
                    this:viewSelectionHTML()
                end,
            }
        end)
    end

    -- User hyphenation dict
    self:addToHighlightDialog("10_user_dict", function(this)
        return {
            text= _("Hyphenate"),
            show_in_highlight_dialog_func = function()
                return this.ui.userhyph and this.ui.userhyph:isAvailable()
                    and not this.selected_text.text:find("[ ,;-%.\n]")
            end,
            callback = function()
                this.ui.userhyph:modifyUserEntry(this.selected_text.text)
                this:onClose()
            end,
        }
    end)

    -- Links
    self:addToHighlightDialog("11_follow_link", function(this)
        return {
            text = _("Follow Link"),
            show_in_highlight_dialog_func = function()
                return this.selected_link ~= nil
            end,
            callback = function()
                local link = this.selected_link.link or this.selected_link
                this.ui.link:onGotoLink(link)
                this:onClose()
            end,
        }
    end)

    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)

    -- delegate gesture listener to readerui, NOP our own
    self.ges_events = nil
end

function ReaderHighlight:onSetDimensions(dimen)
    self.screen_w, self.screen_h = dimen.w, dimen.h
end

function ReaderHighlight:onGesture() end

function ReaderHighlight:registerKeyEvents()
    if Device:hasDPad() then
        self.key_events.StopHighlightIndicator  = { { Device.input.group.Back }, args = true } -- true: clear highlight selection
        self.key_events.UpHighlightIndicator    = { { "Up" },    event = "MoveHighlightIndicator", args = {0, -1} }
        self.key_events.DownHighlightIndicator  = { { "Down" },  event = "MoveHighlightIndicator", args = {0, 1} }
        -- let hasFewKeys device move the indicator left
        self.key_events.LeftHighlightIndicator  = { { "Left" },  event = "MoveHighlightIndicator", args = {-1, 0} }
        self.key_events.RightHighlightIndicator = { { "Right" }, event = "MoveHighlightIndicator", args = {1, 0} }
        self.key_events.HighlightPress          = { { "Press" } }
    end
    if Device:hasKeyboard() then
        -- Used for text selection with dpad/keys
        local QUICK_INDICATOR_MOVE = true
        self.key_events.QuickUpHighlightIndicator    = { { "Shift", "Up" },    event = "MoveHighlightIndicator", args = {0, -1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickDownHighlightIndicator  = { { "Shift", "Down" },  event = "MoveHighlightIndicator", args = {0, 1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickLeftHighlightIndicator  = { { "Shift", "Left" },  event = "MoveHighlightIndicator", args = {-1, 0, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickRightHighlightIndicator = { { "Shift", "Right" }, event = "MoveHighlightIndicator", args = {1, 0, QUICK_INDICATOR_MOVE} }
        self.key_events.StartHighlightIndicator      = { { "H" } }
    elseif Device:hasScreenKB() then
        local QUICK_INDICATOR_MOVE = true
        self.key_events.QuickUpHighlightIndicator    = { { "ScreenKB", "Up" },    event = "MoveHighlightIndicator", args = {0, -1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickDownHighlightIndicator  = { { "ScreenKB", "Down" },  event = "MoveHighlightIndicator", args = {0, 1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickLeftHighlightIndicator  = { { "ScreenKB", "Left" },  event = "MoveHighlightIndicator", args = {-1, 0, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickRightHighlightIndicator = { { "ScreenKB", "Right" }, event = "MoveHighlightIndicator", args = {1, 0, QUICK_INDICATOR_MOVE} }
    end
end

ReaderHighlight.onPhysicalKeyboardConnected = ReaderHighlight.registerKeyEvents

function ReaderHighlight:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate")
    if not hold_pan_rate then
        hold_pan_rate = Screen.low_pan_rate and 5.0 or 30.0
    end
    local DTAP_ZONE_TOP_LEFT = G_defaults:readSetting("DTAP_ZONE_TOP_LEFT")
    self.ui:registerTouchZones({
        {
            id = "readerhighlight_tap_select_mode",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_TOP_LEFT.x, ratio_y = DTAP_ZONE_TOP_LEFT.y,
                ratio_w = DTAP_ZONE_TOP_LEFT.w, ratio_h = DTAP_ZONE_TOP_LEFT.h,
            },
            overrides = {
                "readerhighlight_tap",
                "tap_top_left_corner",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTapSelectModeIcon() end
        },
        {
            id = "readerhighlight_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            overrides = {
                -- Tap on existing highlights have priority over
                -- everything but tap on links (as links can be
                -- part of some highlighted text)
                "tap_top_left_corner",
                "tap_top_right_corner",
                "tap_left_bottom_corner",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTap(nil, ges) end
        },
        {
            id = "readerhighlight_hold",
            ges = "hold",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHold(nil, ges) end
        },
        {
            id = "readerhighlight_hold_release",
            ges = "hold_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function() return self:onHoldRelease() end
        },
        {
            id = "readerhighlight_hold_pan",
            ges = "hold_pan",
            rate = hold_pan_rate,
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHoldPan(nil, ges) end
        },
    })
end

function ReaderHighlight:onReaderReady()
    self:setupTouchZones()
    if self.ui.paging and G_reader_settings:isTrue("highlight_write_into_pdf_notify") then
        UIManager:show(Notification:new{
            text = T(_("Write highlights into PDF: %1"), self.highlight_write_into_pdf and _("on") or _("off")),
        })
    end
end

local highlight_style = {
    {_("Lighten"), "lighten"},
    {_("Underline"), "underscore"},
    {_("Strikethrough"), "strikeout"},
    {_("Invert"), "invert"},
}

local note_mark = {
    {_("None"), "none"},
    {_("Underline"), "underline"},
    {_("Side line"), "sideline"},
    {_("Side mark"), "sidemark"},
}

local long_press_action = {
    {_("Ask with popup dialog"), "ask"},
    {_("Do nothing"), "nothing"},
    {_("Highlight"), "highlight"},
    {_("Select and highlight"), "select"},
    {_("Add note"), "note"},
    {_("Translate"), "translate"},
    {_("Wikipedia"), "wikipedia"},
    {_("Dictionary"), "dictionary"},
    {_("Fulltext search"), "search"},
}

local highlight_dialog_position = {
    {_("Top"), "top"},
    {_("Center"), "center"},
    {_("Bottom"), "bottom"},
    {_("Gesture position"), "gesture"},
}

function ReaderHighlight:addToMainMenu(menu_items)
    -- insert table to main reader menu
    if not Device:isTouchDevice() and Device:hasDPad() and not Device:useDPadAsActionKeys() then
        menu_items.start_content_selection = {
            text = _("Start content selection"),
            callback = function()
                self:onStartHighlightIndicator()
            end,
        }
    end

    -- main menu Typeset
    local star = "   ★"
    local hl_sub_item_table = {}
    menu_items.highlight_options = {
        text = _("Highlights"),
        sub_item_table = hl_sub_item_table,
    }
    for _, v in ipairs(highlight_style) do
        local style_text, style = unpack(v)
        table.insert(hl_sub_item_table, {
            text_func = function()
                return style == (G_reader_settings:readSetting("highlight_drawing_style") or self._fallback_drawer)
                    and style_text .. star or style_text
            end,
            checked_func = function()
                return self.view.highlight.saved_drawer == style
            end,
            radio = true,
            callback = function()
                self.view.highlight.saved_drawer = style
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("highlight_drawing_style", style)
                touchmenu_instance:updateItems()
            end,
        })
    end
    hl_sub_item_table[#highlight_style].separator = true
    table.insert(hl_sub_item_table, {
        text_func = function()
            local saved_color = self.view.highlight.saved_color
            local text
            for _, v in ipairs(self.highlight_colors) do
                if v[2] == saved_color then
                    text = v[1]:lower()
                    break
                end
            end
            text = text or saved_color -- nonstandard color
            local default_color = G_reader_settings:readSetting("highlight_color") or self._fallback_color
            if saved_color == default_color then
                text = text .. star
            end
            return T(_("Highlight color: %1"), text)
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer ~= "invert"
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance) -- set color for new highlights in this book
            local function apply_color(color)
                self.view.highlight.saved_color = color
                touchmenu_instance:updateItems()
            end
            self:showHighlightColorDialog(apply_color)
        end,
        hold_callback = function(touchmenu_instance) -- set color for new highlights in new books
            G_reader_settings:saveSetting("highlight_color", self.view.highlight.saved_color)
            touchmenu_instance:updateItems()
        end,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            return T(_("Gray highlight opacity: %1"), G_reader_settings:readSetting("highlight_lighten_factor", 0.2))
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer == "lighten"
        end,
        callback = function(touchmenu_instance)
            local spin_widget = SpinWidget:new{
                value = G_reader_settings:readSetting("highlight_lighten_factor"),
                value_min = 0,
                value_max = 1,
                precision = "%.2f",
                value_step = 0.1,
                value_hold_step = 0.2,
                default_value = 0.2,
                keep_shown_on_apply = true,
                title_text =  _("Gray highlight opacity"),
                info_text = _("The higher the value, the darker the gray."),
                callback = function(spin)
                    G_reader_settings:saveSetting("highlight_lighten_factor", spin.value)
                    self.view.highlight.lighten_factor = spin.value
                    UIManager:setDirty(self.dialog, "ui")
                    touchmenu_instance:updateItems()
                end,
            }
            UIManager:show(spin_widget)
        end,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            local notemark = self.view.highlight.note_mark or "none"
            for __, v in ipairs(note_mark) do
                if v[2] == notemark then
                    return T(_("Note marker: %1"), v[1]:lower())
                end
            end
        end,
        callback = function(touchmenu_instance)
            local notemark = self.view.highlight.note_mark or "none"
            local radio_buttons = {}
            for _, v in ipairs(note_mark) do
                table.insert(radio_buttons, {
                    {
                        text = v[1],
                        checked = v[2] == notemark,
                        provider = v[2],
                    },
                })
            end
            UIManager:show(RadioButtonWidget:new{
                title_text = _("Note marker"),
                width_factor = 0.5,
                keep_shown_on_apply = true,
                radio_buttons = radio_buttons,
                callback = function(radio)
                    if radio.provider == "none" then
                        self.view.highlight.note_mark = nil
                        G_reader_settings:delSetting("highlight_note_marker")
                    else
                        self.view.highlight.note_mark = radio.provider
                        G_reader_settings:saveSetting("highlight_note_marker", radio.provider)
                    end
                    self.view:setupNoteMarkPosition()
                    UIManager:setDirty(self.dialog, "ui")
                    touchmenu_instance:updateItems()
                end,
            })
        end,
        separator = true,
    })
    table.insert(hl_sub_item_table, {
        text = _("Apply current style and color to all highlights"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to update all highlights?"),
                icon = "texture-box",
                ok_callback = function()
                    local count = 0
                    for _, item in ipairs(self.ui.annotation.annotations) do
                        if item.drawer then
                            count = count + 1
                            item.drawer = self.view.highlight.saved_drawer
                            item.color = self.view.highlight.saved_color
                        end
                    end
                    if count > 0 then
                        UIManager:setDirty(self.dialog, "ui")
                        UIManager:show(Notification:new{
                            text = T(N_("Applied style and color to 1 highlight",
                                "Applied style and color to %1 highlights", count), count),
                        })
                    end
                end,
            })
        end,
        separator = self.ui.paging and true,
    })
    if self.document.is_pdf then
        table.insert(hl_sub_item_table, {
            text_func = function()
                local text = self.highlight_write_into_pdf and _("on") or _("off")
                if (not self.highlight_write_into_pdf) == (not G_reader_settings:isTrue("highlight_write_into_pdf")) then
                    text = text .. star
                end
                return T(_("Write highlights into PDF: %1"), text)
            end,
            sub_item_table = {
                {
                    text_func = function()
                        local text = _("On")
                        return G_reader_settings:isTrue("highlight_write_into_pdf") and text .. star or text
                    end,
                    checked_func = function()
                        return self.highlight_write_into_pdf
                    end,
                    radio = true,
                    callback = function()
                        if self.document:_checkIfWritable() then
                            self.highlight_write_into_pdf = true
                            if G_reader_settings:readSetting("document_metadata_folder") == "hash" then
                                UIManager:show(InfoMessage:new{
                                    text = _("Warning: Book metadata location is set to hash-based storage. Writing highlights into a PDF modifies the file which may change the partial hash, resulting in its metadata (e.g., highlights and progress) being unlinked and lost."),
                                    icon = "notice-warning",
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                            text = _([[
Highlights in this document will be saved in the settings file, but they won't be written in the document itself because the file is in a read-only location.

If you wish your highlights to be saved in the document, just move it to a writable directory first.]]),
                            })
                        end
                    end,
                    hold_callback = function(touchmenu_instance)
                        G_reader_settings:makeTrue("highlight_write_into_pdf")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function()
                        local text = _("Off")
                        return G_reader_settings:hasNot("highlight_write_into_pdf") and text .. star or text
                    end,
                    checked_func = function()
                        return not self.highlight_write_into_pdf
                    end,
                    radio = true,
                    callback = function()
                        self.highlight_write_into_pdf = false
                    end,
                    hold_callback = function(touchmenu_instance)
                        G_reader_settings:delSetting("highlight_write_into_pdf")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = _("Show reminder on book opening"),
                    checked_func = function()
                        return G_reader_settings:isTrue("highlight_write_into_pdf_notify")
                    end,
                    callback = function()
                        G_reader_settings:flipNilOrFalse("highlight_write_into_pdf_notify")
                    end,
                    separator = true,
                },
                {
                    text = _("Write all highlights into PDF file"),
                    enabled_func = function()
                        return self.highlight_write_into_pdf and self.ui.annotation:getNumberOfHighlightsAndNotes() > 0
                    end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to write all KOReader highlights into PDF file?"),
                            icon = "texture-box",
                            ok_callback = function()
                                local count = 0
                                for _, item in ipairs(self.ui.annotation.annotations) do
                                    if item.drawer then
                                        count = count + 1
                                        self:writePdfAnnotation("delete", item)
                                        self:writePdfAnnotation("save", item)
                                        if item.note then
                                            self:writePdfAnnotation("content", item, item.note)
                                        end
                                    end
                                end
                                UIManager:show(Notification:new{
                                    text = T(N_("1 highlight written into PDF file",
                                        "%1 highlights written into PDF file", count), count),
                                })
                            end,
                        })
                    end,
                },
                {
                    text = _("Delete all highlights from PDF file"),
                    enabled_func = function()
                        return self.highlight_write_into_pdf and self.ui.annotation:getNumberOfHighlightsAndNotes() > 0
                    end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to delete all KOReader highlights from PDF file?"),
                            icon = "texture-box",
                            ok_callback = function()
                                local count = 0
                                for _, item in ipairs(self.ui.annotation.annotations) do
                                    if item.drawer then
                                        count = count + 1
                                        self:writePdfAnnotation("delete", item)
                                    end
                                end
                                UIManager:show(Notification:new{
                                    text = T(N_("1 highlight deleted from PDF file",
                                        "%1 highlights deleted from PDF file", count), count),
                                })
                            end,
                        })
                    end,
                },
            },
        })
    end

    if self.ui.paging then
        menu_items.panel_zoom_options = {
            text = _("Panel zoom (manga/comic)"),
            sub_item_table = self:genPanelZoomMenu(),
        }
    end

    -- main menu Settings
    menu_items.long_press = {
        text = _("Long-press on text"),
        sub_item_table = {
            {
                text = _("Dictionary on single word selection"),
                checked_func = function()
                    return not self.view.highlight.disabled and G_reader_settings:nilOrFalse("highlight_action_on_single_word")
                end,
                enabled_func = function()
                    return not self.view.highlight.disabled
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("highlight_action_on_single_word")
                end,
                separator = true,
            },
        },
    }
    -- actions
    for i, v in ipairs(long_press_action) do
        table.insert(menu_items.long_press.sub_item_table, {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("default_highlight_action", "ask") == v[2]
            end,
            radio = true,
            callback = function()
                self:onSetHighlightAction(i, true) -- no notification
            end,
        })
    end
    -- highlight dialog position
    local sub_item_table = {}
    for i, v in ipairs(highlight_dialog_position) do
        table.insert(sub_item_table, {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("highlight_dialog_position", "center") == v[2]
            end,
            callback = function()
                G_reader_settings:saveSetting("highlight_dialog_position", v[2])
            end,
        })
    end
    table.insert(menu_items.long_press.sub_item_table, {
        text_func = function()
            local position = G_reader_settings:readSetting("highlight_dialog_position", "center")
            for __, v in ipairs(highlight_dialog_position) do
                if v[2] == position then
                    return T(_("Highlight dialog position: %1"), v[1]:lower())
                end
            end
        end,
        sub_item_table = sub_item_table,
    })
    if Device:isTouchDevice() then
        -- highlight very-long-press interval
        table.insert(menu_items.long_press.sub_item_table, {
            text_func = function()
                return T(_("Highlight very-long-press interval: %1 s"),
                    G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local items = SpinWidget:new{
                    title_text = _("Highlight very-long-press interval"),
                    info_text = _("If a long-press is not released in this interval, it is considered a very-long-press. On document text, single word selection will not be triggered."),
                    width = math.floor(self.screen_w * 0.75),
                    value = G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3),
                    value_min = 2.5,
                    value_max = 20,
                    value_step = 0.1,
                    value_hold_step = 0.5,
                    unit = C_("Time", "s"),
                    precision = "%0.1f",
                    ok_text = _("Set interval"),
                    default_value = 3,
                    callback = function(spin)
                        G_reader_settings:saveSetting("highlight_long_hold_threshold_s", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(items)
            end,
        })
    end

    table.insert(menu_items.long_press.sub_item_table, {
        text = _("Auto-scroll when selection reaches a corner"),
        help_text = _([[
Auto-scroll to show part of the previous page when your text selection reaches the top left corner, or of the next page when it reaches the bottom right corner.
Except when in two columns mode, where this is limited to showing only the previous or next column.]]),
        separator = true,
        checked_func = function()
            if self.ui.paging then return false end
            return not self.view.highlight.disabled and G_reader_settings:nilOrTrue("highlight_corner_scroll")
        end,
        enabled_func = function()
            if self.ui.paging then return false end
            return not self.view.highlight.disabled
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("highlight_corner_scroll")
            self.allow_corner_scroll = G_reader_settings:nilOrTrue("highlight_corner_scroll")
        end,
    })

    -- we allow user to select the rate at which the content selection tool moves through screen
    if not Device:isTouchDevice() and Device:hasDPad() then
        table.insert(menu_items.long_press.sub_item_table, {
            text_func = function()
                return T(_("Rate of movement in content selection: %1"), G_reader_settings:readSetting("highlight_non_touch_factor") or 4)
            end,
            callback = function(touchmenu_instance)
                local curr_val = G_reader_settings:readSetting("highlight_non_touch_factor") or 4
                local spin_widget = SpinWidget:new{
                    value = curr_val,
                    value_min = 0.25,
                    value_max = 5,
                    precision = "%.2f",
                    value_step = 0.25,
                    default_value = 4,
                    title_text = _("Rate of movement"),
                    info_text = _("Select a decimal value from 0.25 to 5. A smaller value results in a larger travel distance per keystroke. Font size and this value are inversely correlated, meaning a smaller font size requires a larger value and vice versa."),
                    callback = function(spin)
                        G_reader_settings:saveSetting("highlight_non_touch_factor", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end
                }
                UIManager:show(spin_widget)
            end,
        })
        table.insert(menu_items.long_press.sub_item_table, {
            text = _("Speed-up rate on multiple keystrokes"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("highlight_non_touch_spedup")
            end,
            enabled_func = function()
                return not self.view.highlight.disabled
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("highlight_non_touch_spedup")
            end,
        })
        table.insert(menu_items.long_press.sub_item_table, {
            text_func = function()
                local highlight_non_touch_interval = G_reader_settings:readSetting("highlight_non_touch_interval") or 1
                return T(N_("Speed-up rate interval: 1 second", "Speed-up rate interval: %1 seconds", highlight_non_touch_interval), highlight_non_touch_interval)
            end,
            enabled_func = function()
                return not self.view.highlight.disabled and G_reader_settings:nilOrTrue("highlight_non_touch_spedup")
            end,
            callback = function(touchmenu_instance)
                local curr_val = G_reader_settings:readSetting("highlight_non_touch_interval") or 1
                local spin_widget = SpinWidget:new{
                    value = curr_val,
                    value_min = 0.1,
                    value_max = 1,
                    precision = "%.1f",
                    value_step = 0.1,
                    default_value = 1,
                    title_text = _("Time interval"),
                    info_text = _("Select a decimal value up to 1 second. This is the period of time within which multiple keystrokes will speed-up rate of travel."),
                    callback = function(spin)
                        G_reader_settings:saveSetting("highlight_non_touch_interval", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end
                }
                UIManager:show(spin_widget)
            end,
        })

        -- long_press setting is under taps_and_gestures menu which is not available for non-touch devices
        -- Clone long_press setting and change its label, making it much more meaningful for non-touch device users.
        menu_items.selection_text = menu_items.long_press
        menu_items.selection_text.text = _("Selection on text")
        menu_items.long_press = nil
    end

    -- main menu Search
    menu_items.translation_settings = Translator:genSettingsMenu()
    menu_items.translate_current_page = {
        text = _("Translate current page"),
        callback = function()
            self:onTranslateCurrentPage()
        end,
    }
end

function ReaderHighlight:genPanelZoomMenu()
    return {
        {
            text = _("Allow panel zoom"),
            checked_func = function()
                return self.panel_zoom_enabled
            end,
            callback = function()
                self:onTogglePanelZoomSetting()
            end,
            hold_callback = function()
                local ext = util.getFileNameSuffix(self.ui.document.file)
                local curr_val = G_reader_settings:getSettingForExt("panel_zoom_enabled", ext)
                G_reader_settings:saveSettingForExt("panel_zoom_enabled", not curr_val, ext)
            end,
            separator = true,
        },
        {
            text = _("Fall back to text selection"),
            checked_func = function()
                return self.panel_zoom_fallback_to_text_selection
            end,
            callback = function()
                self:onToggleFallbackTextSelection()
            end,
            hold_callback = function()
                local ext = util.getFileNameSuffix(self.ui.document.file)
                G_reader_settings:saveSettingForExt("panel_zoom_fallback_to_text_selection", self.panel_zoom_fallback_to_text_selection, ext)
            end,
            separator = true,
        },
    }
end

-- Returns a unique id, that can be provided on delayed call to :clear(id)
-- to ensure current highlight has not already been cleared, and that we
-- are not going to clear a new highlight
function ReaderHighlight:getClearId()
    self.clear_id = UIManager:getTime() -- can act as a unique id
    return self.clear_id
end

function ReaderHighlight:clear(clear_id)
    if clear_id then -- should be provided by delayed call to clear()
        if clear_id ~= self.clear_id then
            -- if clear_id is no longer valid, highlight has already been
            -- cleared since this clear_id was given
            return
        end
    end
    self.clear_id = nil -- invalidate id
    if not self.ui.document then
        -- might happen if scheduled and run after document is closed
        return
    end
    if self.ui.paging then
        self.view.highlight.temp = {}
    else
        self.ui.document:clearSelection()
    end
    if self.restore_page_mode_func then
        self.restore_page_mode_func()
        self.restore_page_mode_func = nil
    end
    self.is_word_selection = false
    self.selected_text_start_xpointer = nil
    self.gest_pos = nil
    if self.hold_pos then
        self.hold_pos = nil
        self.selected_text = nil
        UIManager:setDirty(self.dialog, "ui")
        return true
    end
end

function ReaderHighlight:onClearHighlight()
    self:clear()
    return true
end

function ReaderHighlight:onTapSelectModeIcon()
    if not self.select_mode then return end
    UIManager:show(ConfirmBox:new{
        text = _("You are currently in SELECT mode.\nTo finish highlighting, long press where the highlight should end and press the HIGHLIGHT button.\nYou can also exit select mode by tapping on the start of the highlight."),
        icon = "texture-box",
        ok_text = _("Exit select mode"),
        cancel_text = _("Close"),
        ok_callback = function()
            self.select_mode = false
            self:deleteHighlight(self.highlight_idx)
        end,
    })
    return true
end

function ReaderHighlight:onTap(_, ges)
    -- We only actually need to clear if we have something to clear in the first place.
    -- (We mainly want to avoid CRe's clearSelection,
    -- which may incur a redraw as it invalidates the cache, c.f., #6854)
    -- ReaderHighlight:clear can only return true if self.hold_pos was set anyway.
    local cleared = self.hold_pos and self:clear()
    -- We only care about potential taps on existing highlights, not on taps that closed a highlight menu.
    if not cleared and ges and self.ui.annotation:hasAnnotations() then
        if self.ui.paging then
            return self:onTapPageSavedHighlight(ges)
        else
            return self:onTapXPointerSavedHighlight(ges)
        end
    end
end

function ReaderHighlight:onTapPageSavedHighlight(ges)
    local pages = self.view:getCurrentPageList()
    local pos = self.view:screenToPageTransform(ges.pos)
    local highlights_tapped = {}
    for _, page in ipairs(pages) do
        local items, idx_offset = self:getPageSavedHighlights(page)
        for i, item in ipairs(items) do
            local boxes = self.ui.document:getPageBoxesFromPositions(page, item.pos0, item.pos1)
            if boxes then
                for __, box in ipairs(boxes) do
                    if inside_box(pos, box) then
                        logger.dbg("Tap on highlight")
                        local hl_i = item.parent or (i + idx_offset) -- parent exists in multi-page highlight only
                        if self.select_mode then
                            if hl_i == self.highlight_idx then
                                -- tap on the first fragment: abort select mode, clear highlight
                                self.select_mode = false
                                self:deleteHighlight(hl_i)
                                return true
                            end
                        else
                            table.insert(highlights_tapped, hl_i)
                            break
                        end
                    end
                end
            end
        end
    end
    if #highlights_tapped > 0 then
        return self:showChooseHighlightDialog(highlights_tapped)
    end
end

function ReaderHighlight:onTapXPointerSavedHighlight(ges)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    local pos = self.view:screenToPageTransform(ges.pos)
    -- NOTE: By now, pos.page is set, but if a highlight spans across multiple pages,
    --       it's stored under the hash of its *starting* point,
    --       so we can't just check the current page, hence the giant hashwalk of death...
    --       We can't even limit the walk to page <= pos.page,
    --       because pos.page isn't super accurate in continuous mode
    --       (it's the page number for what's it the topleft corner of the screen,
    --       i.e., often a bit earlier)...
    -- Even in page mode, it's safer to use pos and ui.dimen.h
    -- than pages' xpointers pos, even if ui.dimen.h is a bit
    -- larger than pages' heights
    local cur_view_top = self.document:getCurrentPos()
    local cur_view_bottom
    if self.view.view_mode == "page" and self.document:getVisiblePageCount() > 1 then
        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
    else
        cur_view_bottom = cur_view_top + self.ui.dimen.h
    end
    local highlights_tapped = {}
    for hl_i, item in ipairs(self.ui.annotation.annotations) do
        if item.drawer then
            -- document:getScreenBoxesFromPositions() is expensive, so we
            -- first check this item is on current page
            local start_pos = self.document:getPosFromXPointer(item.pos0)
            local end_pos = self.document:getPosFromXPointer(item.pos1)
            if start_pos <= cur_view_bottom and end_pos >= cur_view_top then
                local boxes = self.ui.document:getScreenBoxesFromPositions(item.pos0, item.pos1, true) -- get_segments=true
                if boxes then
                    for _, box in ipairs(boxes) do
                        if inside_box(pos, box) then
                            logger.dbg("Tap on highlight")
                            if self.select_mode then
                                if hl_i == self.highlight_idx then
                                    -- tap on the first fragment: abort select mode, clear highlight
                                    self.select_mode = false
                                    self:deleteHighlight(hl_i)
                                    return true
                                end
                            else
                                table.insert(highlights_tapped, hl_i)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if #highlights_tapped > 0 then
        return self:showChooseHighlightDialog(highlights_tapped)
    end
end

function ReaderHighlight:updateHighlight(index, side, direction, move_by_char)
    local highlight = self.ui.annotation.annotations[index]
    local highlight_before = util.tableDeepCopy(highlight)
    local highlight_beginning = highlight.pos0
    local highlight_end = highlight.pos1
    if side == 0 then -- we move pos0
        local updated_highlight_beginning
        if direction == 1 then -- move highlight to the right
            if move_by_char then
                updated_highlight_beginning = self.ui.document:getNextVisibleChar(highlight_beginning)
            else
                updated_highlight_beginning = self.ui.document:getNextVisibleWordStart(highlight_beginning)
            end
         else -- move highlight to the left
            if move_by_char then
                updated_highlight_beginning = self.ui.document:getPrevVisibleChar(highlight_beginning)
            else
                updated_highlight_beginning = self.ui.document:getPrevVisibleWordStart(highlight_beginning)
            end
        end
        if updated_highlight_beginning then
            local order = self.ui.document:compareXPointers(updated_highlight_beginning, highlight_end)
            if order and order > 0 then -- only if beginning did not go past end
                highlight.pos0 = updated_highlight_beginning
                highlight.page = updated_highlight_beginning
                highlight.chapter = self.ui.toc:getTocTitleByPage(updated_highlight_beginning)
                highlight.pageno = self.document:getPageFromXPointer(updated_highlight_beginning)
            end
        end
    else -- we move pos1
        local updated_highlight_end
        if direction == 1 then -- move highlight to the right
            if move_by_char then
                updated_highlight_end = self.ui.document:getNextVisibleChar(highlight_end)
            else
                updated_highlight_end = self.ui.document:getNextVisibleWordEnd(highlight_end)
            end
        else -- move highlight to the left
            if move_by_char then
                updated_highlight_end = self.ui.document:getPrevVisibleChar(highlight_end)
            else
                updated_highlight_end = self.ui.document:getPrevVisibleWordEnd(highlight_end)
            end
        end
        if updated_highlight_end then
            local order = self.ui.document:compareXPointers(highlight_beginning, updated_highlight_end)
            if order and order > 0 then -- only if end did not go back past beginning
                highlight.pos1 = updated_highlight_end
            end
        end
    end

    local new_beginning = highlight.pos0
    local new_end = highlight.pos1
    local new_text = self.ui.document:getTextFromXPointers(new_beginning, new_end)
    highlight.text = util.cleanupSelectedText(new_text)
    self.ui:handleEvent(Event:new("AnnotationsModified", { highlight, highlight_before }))
    if side == 0 then
        -- Ensure we show the page with the new beginning of highlight
        if not self.ui.document:isXPointerInCurrentPage(new_beginning) then
            self.ui:handleEvent(Event:new("GotoXPointer", new_beginning))
        end
    else
        -- Ensure we show the page with the new end of highlight
        if not self.ui.document:isXPointerInCurrentPage(new_end) then
            if self.view.view_mode == "page" then
                self.ui:handleEvent(Event:new("GotoXPointer", new_end))
            else
                -- Not easy to get the y that would show the whole line
                -- containing new_end. So, we scroll so that new_end
                -- is at 2/3 of the screen.
                local end_y = self.ui.document:getPosFromXPointer(new_end)
                local top_y = end_y - math.floor(self.screen_h * 2/3)
                self.ui.rolling:_gotoPos(top_y)
            end
        end
    end
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:showChooseHighlightDialog(highlights)
    if #highlights == 1 then
        self:showHighlightNoteOrDialog(highlights[1])
    else -- overlapped highlights
        local dialog
        local buttons = {}
        for i, index in ipairs(highlights) do
            local item = self.ui.annotation.annotations[index]
            buttons[i] = {{
                text = (item.note and self.ui.bookmark.display_prefix["note"]
                                   or self.ui.bookmark.display_prefix["highlight"]) .. item.text,
                align = "left",
                avoid_text_truncation = false,
                font_face = "smallinfofont",
                font_size = 22,
                font_bold = false,
                callback = function()
                    UIManager:close(dialog)
                    self:showHighlightNoteOrDialog(index)
                end,
            }}
        end
        dialog = ButtonDialog:new{
            buttons = buttons,
        }
        UIManager:show(dialog)
    end
    return true
end

function ReaderHighlight:showHighlightNoteOrDialog(index)
    local bookmark_note = self.ui.annotation.annotations[index].note
    if bookmark_note then
        local textviewer
        textviewer = TextViewer:new{
            title = _("Note"),
            show_menu = false,
            text = bookmark_note,
            width = math.floor(math.min(self.screen_w, self.screen_h) * 0.8),
            height = math.floor(math.max(self.screen_w, self.screen_h) * 0.4),
            buttons_table = {
                {
                    {
                        text = _("Delete highlight"),
                        callback = function()
                            UIManager:close(textviewer)
                            self:deleteHighlight(index)
                        end,
                    },
                    {
                        text = _("Edit highlight"),
                        callback = function()
                            UIManager:close(textviewer)
                            self:onShowHighlightDialog(index)
                        end,
                    },
                },
            },
        }
        UIManager:show(textviewer)
    else
        self:onShowHighlightDialog(index)
    end
end

function ReaderHighlight:onShowHighlightDialog(index)
    local item = self.ui.annotation.annotations[index]
    local buttons = {
        {
            {
                text = "\u{F48E}", -- Trash can (icon to prevent confusion of Delete/Details buttons)
                callback = function()
                    self:deleteHighlight(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = C_("Highlight", "Style"),
                callback = function()
                    self:editHighlightStyle(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = C_("Highlight", "Color"),
                enabled = item.drawer ~= "invert",
                callback = function()
                    self:editHighlightColor(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = _("Note"),
                callback = function()
                    self:editHighlight(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = _("Details"),
                callback = function()
                    self.ui.bookmark:showBookmarkDetails(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = "…",
                callback = function()
                    self.selected_text = util.tableDeepCopy(item)
                    self:onShowHighlightMenu(index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
        },
    }

    if self.ui.rolling then
        local enabled = not item.text_edited
        local start_prev = "◁▒▒"
        local start_next = "▷▒▒"
        local end_prev = "▒▒◁"
        local end_next = "▒▒▷"
        if BD.mirroredUILayout() then
            -- BiDi will mirror the arrows, and this just works
            start_prev, start_next = start_next, start_prev
            end_prev, end_next = end_next, end_prev
        end
        table.insert(buttons, {
            {
                text = start_prev,
                enabled = enabled,
                callback = function()
                    self:updateHighlight(index, 0, -1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(index, 0, -1, true)
                    return true
                end,
            },
            {
                text = start_next,
                enabled = enabled,
                callback = function()
                    self:updateHighlight(index, 0, 1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(index, 0, 1, true)
                    return true
                end,
            },
            {
                text = end_prev,
                enabled = enabled,
                callback = function()
                    self:updateHighlight(index, 1, -1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(index, 1, -1, true)
                end,
            },
            {
                text = end_next,
                enabled = enabled,
                callback = function()
                    self:updateHighlight(index, 1, 1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(index, 1, 1, true)
                end,
            }
        })
    end
    self.edit_highlight_dialog = ButtonDialog:new{ -- in self for unit tests
        buttons = buttons,
        anchor = function()
            return self:_getDialogAnchor(self.edit_highlight_dialog, item)
        end,
    }
    UIManager:show(self.edit_highlight_dialog)
    return true
end

function ReaderHighlight:addToHighlightDialog(idx, fn_button)
    -- fn_button is a function that takes the ReaderHighlight instance
    -- as argument, and returns a table describing the button to be added.
    self._highlight_buttons[idx] = fn_button
end

function ReaderHighlight:removeFromHighlightDialog(idx)
    local button = self._highlight_buttons[idx]
    self._highlight_buttons[idx] = nil
    return button
end

function ReaderHighlight:onShowHighlightMenu(index)
    if not self.selected_text then
        return
    end

    local highlight_buttons = {{}}

    local columns = 2
    for idx, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
        local button = fn_button(self, index)
        if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
            if #highlight_buttons[#highlight_buttons] >= columns then
                table.insert(highlight_buttons, {})
            end
            table.insert(highlight_buttons[#highlight_buttons], button)
            logger.dbg("ReaderHighlight", idx..": line "..#highlight_buttons..", col "..#highlight_buttons[#highlight_buttons])
        end
    end

    self.highlight_dialog = ButtonDialog:new{
        buttons = highlight_buttons,
        anchor = function()
            return self:_getDialogAnchor(self.highlight_dialog, not self.gest_pos and self.ui.annotation.annotations[index])
        end,
        tap_close_callback = function() self:handleEvent(Event:new("Tap")) end,
    }
    -- NOTE: Disable merging for this update,
    --       or the buggy Sage kernel may alpha-blend it into the page (with a bogus alpha value, to boot)...
    UIManager:show(self.highlight_dialog, "[ui]")
end
dbg:guard(ReaderHighlight, "onShowHighlightMenu",
    function(self)
        assert(self.selected_text ~= nil,
            "onShowHighlightMenu must not be called with nil self.selected_text!")
    end)

function ReaderHighlight:_getDialogAnchor(dialog, item)
    local position = G_reader_settings:readSetting("highlight_dialog_position", "center")
    if position == "center" then return end
    local dialog_box = dialog:getContentSize()
    local anchor_x = math.floor((self.screen_w - dialog_box.w) / 2) -- center by width
    local anchor_y, prefers_pop_down
    if position == "top" then
        anchor_y = Size.padding.small -- do not stick to the edge
        prefers_pop_down = true
    elseif position == "bottom" then
        anchor_y = self.screen_h - Size.padding.small
    else -- "gesture"
        local pos0, pos1
        if item then -- highlight
            if self.ui.rolling then
                local y, x = self.ui.document:getScreenPositionFromXPointer(item.pos0)
                pos0 = x ~= nil and y ~= nil and { x = x, y = y } or nil
                y, x = self.ui.document:getScreenPositionFromXPointer(item.pos1)
                pos1 = x ~= nil and y ~= nil and { x = x, y = y } or nil
            else
                pos0, pos1 = item.pos0, item.pos1
            end
        else -- gesture
            pos0, pos1 = unpack(self.gest_pos)
            self.gest_pos = nil
        end
        if pos0 == nil or pos1 == nil then return end -- fallback to "center"
        if pos0.y > pos1.y then -- try to show the dialog below the highlight
            pos1 = pos0
        end
        local text_box = self.ui.document:getWordFromPosition(pos1, true)
        if text_box then
            text_box = text_box.sbox
            if text_box and self.ui.paging then
                text_box = self.view:pageToScreenTransform(self.ui.paging.current_page, text_box)
            end
        end
        if text_box == nil then return end -- fallback to "center"
        anchor_y = text_box.y + text_box.h + Size.padding.small -- do not stick to the box
        if anchor_y + dialog_box.h <= self.screen_h - Size.padding.small then -- enough room below box with gest_pos
            prefers_pop_down = true
        else -- above box with gest_pos
            anchor_y = text_box.y - Size.padding.small
        end
    end
    return { x = anchor_x, y = anchor_y, h = 0, w = 0 }, prefers_pop_down
end

function ReaderHighlight:_resetHoldTimer(clear)
    if not self.long_hold_reached_action then
        self.long_hold_reached_action = function()
            self.long_hold_reached = true
            -- Have ReaderView redraw and refresh ReaderFlipping and our state icon, avoiding flashes
            UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
        end
    end
    -- Unschedule if already set
    UIManager:unschedule(self.long_hold_reached_action)

    if not clear then
        -- We don't need to handle long-hold and show its icon in some configurations
        -- where it would not change the behaviour from the normal-hold one (but we still
        -- need to go through the checks below to clear any long_hold_reached set when in
        -- the word->multiwords selection transition).
        -- (It feels we don't need to care about default_highlight_action="nothing" here.)
        local handle_long_hold = true
        if self.is_word_selection then
            -- Single word normal-hold defaults to dict lookup, and long-hold defaults to "ask".
            -- If normal-hold is set to use the highlight action, and this action is still "ask",
            -- no need to handle long-hold.
            if G_reader_settings:isTrue("highlight_action_on_single_word") and
                   G_reader_settings:readSetting("default_highlight_action", "ask") == "ask" then
                handle_long_hold = false
            end
        else
            -- Multi words selection uses default_highlight_action, and no need for long-hold
            -- if it is already "ask".
            if G_reader_settings:readSetting("default_highlight_action", "ask") == "ask" then
                handle_long_hold = false
            end
        end
        if handle_long_hold then
            -- (Default delay is 3 seconds as in the menu items)
            UIManager:scheduleIn(G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3), self.long_hold_reached_action)
        end
    end
    -- Unset flag and icon
    if self.long_hold_reached then
        self.long_hold_reached = false
        -- Have ReaderView redraw and refresh ReaderFlipping with our state icon removed
        UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
    end
end

function ReaderHighlight:onTogglePanelZoomSetting(arg, ges)
    if self.ui.rolling then return end
    self.panel_zoom_enabled = not self.panel_zoom_enabled
end

function ReaderHighlight:onToggleFallbackTextSelection(arg, ges)
    if self.ui.rolling then return end
    self.panel_zoom_fallback_to_text_selection = not self.panel_zoom_fallback_to_text_selection
end

function ReaderHighlight:onPanelZoom(arg, ges)
    self:clear()
    local hold_pos = self.view:screenToPageTransform(ges.pos)
    if not hold_pos then return false end -- outside page boundary
    local rect = self.ui.document:getPanelFromPage(hold_pos.page, hold_pos)
    if not rect then return false end -- panel not found, return
    local image, rotate = self.ui.document:drawPagePart(hold_pos.page, rect, 0)

    if image then
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            image_disposable = false, -- It's a TileCache item
            with_title_bar = false,
            fullscreen = true,
            rotated = rotate,
        }
        UIManager:show(imgviewer)
        return true
    end
    return false
end

function ReaderHighlight:onHold(arg, ges)
    if self.ui.paging and self.panel_zoom_enabled then
        local res = self:onPanelZoom(arg, ges)
        if res or not self.panel_zoom_fallback_to_text_selection then
            return res
        end
    end

    self:clear() -- clear previous highlight (delayed clear may not have done it yet)
    self.hold_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("hold position in page", self.hold_pos)
    if not self.hold_pos then
        logger.dbg("not inside page area")
        return false
    end
    self.gest_pos = { self.hold_pos, self.hold_pos }

    self.allow_hold_pan_corner_scroll = false -- reset this, don't allow that yet

    -- check if we were holding on an image
    -- we provide want_frames=true, so we get a list of images for
    -- animated GIFs (supported by ImageViewer)
    -- We provide accept_cre_scalable_image=true to get, if the image is a SVG image,
    -- a function that ImageViewer can use to get a perfect bb at any scale factor.
    local image = self.ui.document:getImageFromPosition(self.hold_pos, true, true)
    if image then
        logger.dbg("hold on image")
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            -- title_text = _("Document embedded image"),
            -- No title, more room for image
            with_title_bar = false,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
        self:onStopHighlightIndicator()
        return true
    end

    -- otherwise, we must be holding on text
    if self.view.highlight.disabled then return false end -- Long-press action "Do nothing" checked
    local ok, word = pcall(self.ui.document.getWordFromPosition, self.ui.document, self.hold_pos)
    if ok and word then
        logger.dbg("selected word:", word)
        -- Convert "word selection" table to "text selection" table because we
        -- use text selections throughout readerhighlight in order to allow the
        -- highlight to be corrected by language-specific plugins more easily.
        self.is_word_selection = true
        self.selected_text = {
            text = word.word or "",
            pos0 = word.pos0 or word.pos,
            pos1 = word.pos1 or word.pos,
            sboxes = word.sbox and { word.sbox },
            pboxes = word.pbox and { word.pbox },
        }
        local link = self.ui.link:getLinkFromGes(ges)
        self.selected_link = nil
        if link then
            logger.dbg("link:", link)
            self.selected_link = link
        end

        if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
            -- If this is a language where pan-less word selection needs some
            -- extra work above and beyond what the document engine gives us
            -- from getWordFromPosition, call the relevant language-specific
            -- plugin.
            local new_selected_text = self.ui.languagesupport:improveWordSelection(self.selected_text)
            if new_selected_text then
                self.selected_text = new_selected_text
            end
        end

        if self.ui.paging then
            self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
            -- Unfortunately, getWordFromPosition() may not return good coordinates,
            -- so refresh the whole page
            UIManager:setDirty(self.dialog, "ui")
        else
            -- With crengine, getWordFromPosition() does return good coordinates.
            UIManager:setDirty(self.dialog, "ui", Geom.boundingBox(self.selected_text.sboxes))
        end
        self:_resetHoldTimer()
        if word.pos0 then
            -- Remember original highlight start position, so we can show
            -- a marker when back from across-pages text selection, which
            -- is handled in onHoldPan()
            self.selected_text_start_xpointer = word.pos0
        end
        return true
    end
    return false
end

function ReaderHighlight:onHoldPan(_, ges)
    if self.view.highlight.disabled then return false end -- Long-press action "Do nothing" checked
    if self.hold_pos == nil then
        logger.dbg("no previous hold position")
        self:_resetHoldTimer(true)
        return true
    end
    local page_area = self.view:getScreenPageArea(self.hold_pos.page)
    if ges.pos:notIntersectWith(page_area) then
        logger.dbg("not inside page area", ges, page_area)
        self:_resetHoldTimer()
        return true
    end

    self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("holdpan position in page", self.holdpan_pos)

    if self.ui.rolling and self.allow_corner_scroll and self.selected_text_start_xpointer then
        -- With CreDocuments, allow text selection across multiple pages
        -- by (temporarily) switching to scroll mode when panning to the
        -- top left or bottom right corners.
        local mirrored_reading = BD.mirroredUILayout()
        if self.view.inverse_reading_order then
            mirrored_reading = not mirrored_reading
        end
        local is_in_prev_page_corner, is_in_next_page_corner
        if mirrored_reading then
            -- Note: this might not be really usable, as crengine native selection
            -- is not adapted to RTL text
            -- top right corner
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*self.screen_h
                                      and self.holdpan_pos.x > 7/8*self.screen_w
            -- bottom left corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*self.screen_h
                                          and self.holdpan_pos.x < 1/8*self.screen_w
        else -- default in LTR UI with no inverse_reading_order
            -- top left corner
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*self.screen_h
                                      and self.holdpan_pos.x < 1/8*self.screen_w
            -- bottom right corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*self.screen_h
                                      and self.holdpan_pos.x > 7/8*self.screen_w
        end
        if not self.allow_hold_pan_corner_scroll then
            if not is_in_prev_page_corner and not is_in_next_page_corner then
                -- We expect the user to come from a non-corner zone into a corner
                -- to enable this; this allows normal highlighting without scrolling
                -- if the selection is started in the corner: the user will have to
                -- move out from and go back in to trigger a scroll.
                self.allow_hold_pan_corner_scroll = true
            end
        elseif is_in_prev_page_corner or is_in_next_page_corner then
            self:_resetHoldTimer()
            if self.was_in_some_corner then
                -- Do nothing, wait for the user to move his finger out of that corner
                return true
            end
            self.was_in_some_corner = true
            if self.ui.document:getVisiblePageCount() == 1 then -- single page mode
                -- We'll adjust hold_pos.y after the mode switch and the scroll
                -- so it's accurate in the new screen coordinates
                local orig_y = self.ui.document:getScreenPositionFromXPointer(self.selected_text_start_xpointer)
                if self.view.view_mode ~= "scroll" then
                    -- Switch from page mode to scroll mode
                    local restore_page_mode_xpointer = self.ui.document:getXPointer() -- top of current page
                    self.restore_page_mode_func = function()
                        self.ui:handleEvent(Event:new("SetViewMode", "page"))
                        self.ui.rolling:onGotoXPointer(restore_page_mode_xpointer, self.selected_text_start_xpointer)
                    end
                    self.ui:handleEvent(Event:new("SetViewMode", "scroll"))
                end
                -- (using rolling:onGotoViewRel(1/3) has some strange side effects)
                local scroll_distance = math.floor(self.screen_h * 1/3)
                local move_y = is_in_next_page_corner and scroll_distance or -scroll_distance
                self.ui.rolling:_gotoPos(self.ui.document:getCurrentPos() + move_y)
                local new_y = self.ui.document:getScreenPositionFromXPointer(self.selected_text_start_xpointer)
                self.hold_pos.y = self.hold_pos.y - orig_y + new_y
                UIManager:setDirty(self.dialog, "ui")
                return true
            else -- two pages mode
                -- We don't switch to scroll mode: we just turn 1 page to
                -- allow continuing the selection.
                -- Unlike in 1-page mode, we have a limitation here: we can't adjust
                -- the selection to further than current page and prev/next one.
                -- So don't handle another corner if we already handled one:
                -- Note that this feature won't work well with the RTL UI or
                -- if inverse_reading_order as crengine currently always displays
                -- the first page on the left and the second on the right in
                -- dual page mode.
                if self.restore_page_mode_func then
                    return true
                end
                -- Also, we are not able to move hold_pos.x out of screen,
                -- so if we started on the right page, ignore top left corner,
                -- and if we started on the left page, ignore bottom right corner.
                local screen_half_width = math.floor(self.screen_w * 0.5)
                if self.hold_pos.x >= screen_half_width and is_in_prev_page_corner then
                    return true
                elseif self.hold_pos.x <= screen_half_width and is_in_next_page_corner then
                    return true
                end
                -- To be able to browse half-page when 2 visible pages as 1 page number,
                -- we must work with internal page numbers
                local cur_page = self.ui.document:getCurrentPage(true)
                local restore_page_mode_xpointer = self.ui.document:getXPointer() -- top of current page
                self.ui.document.no_page_sync = true -- avoid CreDocument:drawCurrentViewByPage() to resync page
                self.restore_page_mode_func = function()
                    self.ui.document.no_page_sync = nil
                    self.ui.rolling:onGotoXPointer(restore_page_mode_xpointer, self.selected_text_start_xpointer)
                end
                if is_in_next_page_corner then -- bottom right corner in LTR UI
                    self.ui.rolling:_gotoPage(cur_page + 1, true, true) -- no odd left page enforcement
                    self.hold_pos.x = self.hold_pos.x - screen_half_width
                else -- top left corner in RTL UI
                    self.ui.rolling:_gotoPage(cur_page - 1, true, true) -- no odd left page enforcement
                    self.hold_pos.x = self.hold_pos.x + screen_half_width
                end
                UIManager:setDirty(self.dialog, "ui")
                return true
            end
        else
            self.was_in_some_corner = nil
        end
    end

    local old_text = self.selected_text and self.selected_text.text
    self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.holdpan_pos)
    self.gest_pos = { self.hold_pos, self.holdpan_pos }
    self.is_word_selection = false

    if self.selected_text and self.selected_text.pos0 then
        if not self.selected_text_start_xpointer then
            -- This should have been set in onHold(), where we would get
            -- a precise pos0 on the first word selected.
            -- Do it here too in case onHold() missed it, but it could be
            -- less precise (getTextFromPositions() does order pos0 and pos1,
            -- so it's not certain pos0 is where we started from; we get
            -- the ones from the first pan, and if it is not small enough
            -- and spans quite some height, the marker could point away
            -- from the start position)
            self.selected_text_start_xpointer = self.selected_text.pos0
        end
    end

    if self.selected_text and old_text and old_text == self.selected_text.text then
        -- no modification
        return
    end
    self:_resetHoldTimer() -- selection updated
    logger.dbg("selected text:", self.selected_text)
    if self.selected_text then
        self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
    end
    UIManager:setDirty(self.dialog, "ui")
end

local info_message_ocr_text = _([[
No OCR results or no language data.

KOReader has a built-in OCR engine for recognizing words in scanned PDF and DjVu documents. In order to use OCR in scanned pages, you need to install tesseract trained data for your document language.

You can download language data files for Tesseract version 5.3.4 from https://tesseract-ocr.github.io/tessdoc/Data-Files

Copy the language data files (e.g., eng.traineddata for English and spa.traineddata for Spanish) into koreader/data/tessdata]])

function ReaderHighlight:lookup(selected_text, selected_link)
    -- convert sboxes to word boxes
    local word_boxes = {}
    for i, sbox in ipairs(selected_text.sboxes) do
        word_boxes[i] = self.view:pageToScreenTransform(self.hold_pos.page, sbox)
    end

    -- if we extracted text directly
    if #selected_text.text > 0 and self.hold_pos then
        self.ui:handleEvent(Event:new("LookupWord", selected_text.text, false, word_boxes, self, selected_link))
    -- or we will do OCR
    elseif selected_text.sboxes and self.hold_pos then
        local text = self.ui.document:getOCRText(self.hold_pos.page, selected_text.sboxes)
        if not text then
            -- getOCRText is not implemented in some document backends, but
            -- getOCRWord is implemented everywhere. As such, fall back to
            -- getOCRWord.
            text = ""
            for _, sbox in ipairs(selected_text.sboxes) do
                local word = self.ui.document:getOCRWord(self.hold_pos.page, { sbox = sbox })
                logger.dbg("OCRed word:", word)
                --- @fixme This might produce incorrect results on RTL text.
                if word and word ~= "" then
                    text = text .. word
                end
            end
        end
        logger.dbg("OCRed text:", text)
        if text and text ~= "" then
            self.ui:handleEvent(Event:new("LookupWord", text, false, word_boxes, self, selected_link))
        else
            UIManager:show(InfoMessage:new{
                text = info_message_ocr_text,
            })
        end
    end
end
dbg:guard(ReaderHighlight, "lookup",
    function(self, selected_text, selected_link)
        assert(selected_text ~= nil,
            "lookup must not be called with nil selected_text!")
    end)

function ReaderHighlight:getSelectedWordContext(nb_words)
    if not self.selected_text then return end
    local ok, prev_context, next_context = pcall(self.ui.document.getSelectedWordContext, self.ui.document,
                                                 self.selected_text.text, nb_words, self.selected_text.pos0, self.selected_text.pos1, true)
    if ok then
        return prev_context, next_context
    end
end

function ReaderHighlight:viewSelectionHTML(debug_view, no_css_files_buttons)
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local ViewHtml = require("ui/viewhtml")
        ViewHtml:viewSelectionHTML(self.ui.document, self.selected_text)
    end
end

function ReaderHighlight:translate(index)
    if self.ui.rolling then
        -- Extend the selected text to include any punctuation at start or end,
        -- which may give a better translation with the added context.
        local extended_text = self.ui.document:extendXPointersToSentenceSegment(self.selected_text.pos0, self.selected_text.pos1)
        if extended_text then
            self.selected_text = extended_text
        end
    end
    if #self.selected_text.text > 0 then
        self:onTranslateText(self.selected_text.text, index)
    -- or we will do OCR
    elseif self.hold_pos then
        local text = self.ui.document:getOCRText(self.hold_pos.page, self.selected_text)
        logger.dbg("OCRed text:", text)
        if text and text ~= "" then
            self:onTranslateText(text)
        else
            UIManager:show(InfoMessage:new{
                text = info_message_ocr_text,
            })
        end
    end
end

function ReaderHighlight:onTranslateText(text, index)
    Translator:showTranslation(text, true, nil, nil, true, index)
end

function ReaderHighlight:onTranslateCurrentPage()
    local x0, y0, x1, y1, page, is_reflow
    if self.ui.rolling then
        x0 = 0
        y0 = 0
        x1 = self.screen_w
        y1 = self.screen_h
    else
        page = self.ui:getCurrentPage()
        is_reflow = self.ui.document.configurable.text_wrap
        self.ui.document.configurable.text_wrap = 0
        local page_boxes = self.ui.document:getTextBoxes(page)
        if page_boxes and page_boxes[1][1].word then
            x0 = page_boxes[1][1].x0
            y0 = page_boxes[1][1].y0
            x1 = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1
            y1 = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1
        end
    end
    local res = x0 and self.ui.document:getTextFromPositions({x = x0, y = y0, page = page}, {x = x1, y = y1}, true)
    if self.ui.paging then
        self.ui.document.configurable.text_wrap = is_reflow
    end
    if res and res.text then
        Translator:showTranslation(res.text, false, self.ui.doc_props.language)
    end
end

function ReaderHighlight:onHoldRelease()
    if self.clear_id then
        -- Something has requested a clear id and is about to clear
        -- the highlight: it may be a onHoldClose() that handled
        -- "hold" and was closed, and can't handle "hold_release":
        -- ignore this "hold_release" event.
        return true
    end

    local long_final_hold = self.long_hold_reached
    self:_resetHoldTimer(true) -- clear state

    local default_highlight_action = G_reader_settings:readSetting("default_highlight_action", "ask")

    if self.select_mode then -- extended highlighting, ending fragment
        if self.selected_text then
            self.select_mode = false
            self:extendSelection()
            if default_highlight_action == "select" then
                self:saveHighlight(true)
                self:clear()
            else
                self:onShowHighlightMenu()
            end
        end
        return true
    end

    if self.is_word_selection then -- single-word selection
        if long_final_hold or G_reader_settings:isTrue("highlight_action_on_single_word") then
            self.is_word_selection = false
        end
    end

    if self.selected_text then
        if self.is_word_selection then
            self:lookup(self.selected_text, self.selected_link)
        else
            if long_final_hold or default_highlight_action == "ask" then
                -- bypass default action and show popup if long final hold
                self:onShowHighlightMenu()
            elseif default_highlight_action == "highlight" then
                self:saveHighlight(true)
                self:onClose()
            elseif default_highlight_action == "select" then
                self:startSelection()
                self:onClose()
            elseif default_highlight_action == "note" then
                self:addNote()
                self:onClose()
            elseif default_highlight_action == "translate" then
                self:translate()
            elseif default_highlight_action == "wikipedia" then
                self:lookupWikipedia()
                self:onClose()
            elseif default_highlight_action == "dictionary" then
                self:onHighlightDictLookup()
                self:onClose()
            elseif default_highlight_action == "search" then
                self:onHighlightSearch()
                -- No self:onClose() to not remove the selected text
                -- which will have been the first search result
            end
        end
    end
    return true
end

function ReaderHighlight:getHighlightActions() -- for Dispatcher
    local action_nums, action_texts = {}, {}
    for i, v in ipairs(long_press_action) do
        table.insert(action_nums, i)
        table.insert(action_texts, v[1])
    end
    return action_nums, action_texts
end

function ReaderHighlight:onSetHighlightAction(action_num, no_notification)
    local v = long_press_action[action_num]
    G_reader_settings:saveSetting("default_highlight_action", v[2])
    self.view.highlight.disabled = v[2] == "nothing"
    if not no_notification then -- fired with a gesture
        UIManager:show(Notification:new{
            text = T(_("Default highlight action changed to '%1'."), v[1]),
        })
    end
    return true
end

function ReaderHighlight:onCycleHighlightAction()
    local current_action = G_reader_settings:readSetting("default_highlight_action", "ask")
    local next_action_num
    for i, v in ipairs(long_press_action) do
        if v[2] == current_action then
            next_action_num = i + 1
            break
        end
    end
    if next_action_num > #long_press_action then
        next_action_num = 1
    end
    self:onSetHighlightAction(next_action_num)
    return true
end

function ReaderHighlight.getHighlightStyles()
    return highlight_style
end

function ReaderHighlight:getHighlightStyleString(style) -- for bookmark list
    for _, v in ipairs(highlight_style) do
        if v[2] == style then
            return v[1]
        end
    end
end

function ReaderHighlight:onCycleHighlightStyle()
    local current_style = self.view.highlight.saved_drawer
    local next_style_num
    for i, v in ipairs(highlight_style) do
        if v[2] == current_style then
            next_style_num = i + 1
            break
        end
    end
    if next_style_num > #highlight_style then
        next_style_num = 1
    end
    self.view.highlight.saved_drawer = highlight_style[next_style_num][2]
    UIManager:show(Notification:new{
        text = T(_("Default highlight style changed to '%1'."), highlight_style[next_style_num][1]),
    })
    return true
end

function ReaderHighlight:highlightFromHoldPos()
    if self.hold_pos then
        if not self.selected_text then
            self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.hold_pos)
            if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
                -- Match language-specific expansion you'd get from self:onHold().
                local new_selected_text = self.ui.languagesupport:improveWordSelection(self.selected_text)
                if new_selected_text then
                    self.selected_text = new_selected_text
                end
            end
            logger.dbg("selected text:", self.selected_text)
        end
    end
end

function ReaderHighlight:saveHighlight(extend_to_sentence)
    logger.dbg("save highlight")
    if self.hold_pos and not self.selected_text then
        self:highlightFromHoldPos()
    end
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local pg_or_xp
        if self.ui.rolling then
            if extend_to_sentence then
                local extended_text = self.ui.document:extendXPointersToSentenceSegment(self.selected_text.pos0, self.selected_text.pos1)
                if extended_text then
                    self.selected_text = extended_text
                end
            end
            pg_or_xp = self.selected_text.pos0
        else
            pg_or_xp = self.selected_text.pos0.page
        end
        local item = {
            page = self.ui.paging and self.selected_text.pos0.page or self.selected_text.pos0,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            text = util.cleanupSelectedText(self.selected_text.text),
            drawer = self.view.highlight.saved_drawer,
            color = self.view.highlight.saved_color,
            chapter = self.ui.toc:getTocTitleByPage(pg_or_xp),
        }
        if self.ui.paging then
            item.pboxes = self.selected_text.pboxes
            item.ext = self.selected_text.ext
            self:writePdfAnnotation("save", item)
        end
        local index = self.ui.annotation:addItem(item)
        self.view.footer:maybeUpdateFooter()
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1 }))
        return index
    end
end

function ReaderHighlight:writePdfAnnotation(action, item, content)
    if self.ui.rolling or not self.highlight_write_into_pdf then
        return
    end
    logger.dbg("write to pdf document", action, item)
    local function doAction(action_, page_, item_, content_)
        if action_ == "save" then
            self.document:saveHighlight(page_, item_)
        elseif action_ == "delete" then
            self.document:deleteHighlight(page_, item_)
        elseif action_ == "content" then
            self.document:updateHighlightContents(page_, item_, content_)
        end
    end
    if item.pos0.page == item.pos1.page then -- single-page highlight
        doAction(action, item.pos0.page, item, content)
    else -- multi-page highlight
        for hl_page = item.pos0.page, item.pos1.page do
            local hl_part = self:getSavedExtendedHighlightPage(item, hl_page)
            doAction(action, hl_page, hl_part, content)
            if action == "save" then -- update pboxes from quadpoints
                item.ext[hl_page].pboxes = hl_part.pboxes
            end
        end
    end
end

function ReaderHighlight:lookupWikipedia()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWikipedia", util.cleanupSelectedText(self.selected_text.text)))
    end
end

function ReaderHighlight:onHighlightSearch()
    logger.dbg("search highlight")
    -- First, if our dialog is still shown, close it.
    if self.highlight_dialog then
        UIManager:close(self.highlight_dialog)
        self.highlight_dialog = nil
    end
    self:highlightFromHoldPos()
    if self.selected_text then
        local text = util.stripPunctuation(util.cleanupSelectedText(self.selected_text.text))
        self.ui.search:searchText(text)
    end
end

function ReaderHighlight:onHighlightDictLookup()
    logger.dbg("dictionary lookup highlight")
    self:highlightFromHoldPos()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWord", util.cleanupSelectedText(self.selected_text.text)))
    end
end

function ReaderHighlight:deleteHighlight(index)
    logger.dbg("delete highlight", index)
    local item = self.ui.annotation.annotations[index]
    self:writePdfAnnotation("delete", item)
    self.ui.bookmark:removeItemByIndex(index)
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:addNote(text)
    local index = self:saveHighlight(true)
    if text then -- called from Translator to save translation to note
        self:clear()
    end
    self:editHighlight(index, true, text)
end

function ReaderHighlight:editHighlight(index, is_new_note, text)
    local note_updated_callback = function()
        if self.view.highlight.note_mark then -- refresh note marker
            UIManager:setDirty(self.dialog, "ui")
        end
    end
    self.ui.bookmark:setBookmarkNote(index, is_new_note, text, note_updated_callback)
end

function ReaderHighlight:editHighlightStyle(index)
    local item = self.ui.annotation.annotations[index]
    local apply_drawer = function(drawer)
        self:writePdfAnnotation("delete", item)
        item.drawer = drawer
        if self.ui.paging then
            self:writePdfAnnotation("save", item)
            if item.note then
                self:writePdfAnnotation("content", item, item.note)
            end
        end
        UIManager:setDirty(self.dialog, "ui")
        self.ui:handleEvent(Event:new("AnnotationsModified", { item }))
    end
    self:showHighlightStyleDialog(apply_drawer, item.drawer, index)
end

function ReaderHighlight:editHighlightColor(index)
    local item = self.ui.annotation.annotations[index]
    local apply_color = function(color)
        self:writePdfAnnotation("delete", item)
        item.color = color
        if self.ui.paging then
            self:writePdfAnnotation("save", item)
            if item.note then
                self:writePdfAnnotation("content", item, item.note)
            end
        end
        UIManager:setDirty(self.dialog, "ui")
        self.ui:handleEvent(Event:new("AnnotationsModified", { item }))
    end
    self:showHighlightColorDialog(apply_color, item)
end

function ReaderHighlight:showHighlightStyleDialog(caller_callback, item_drawer)
    local default_drawer, keep_shown_on_apply
    if item_drawer then -- called from ReaderHighlight:editHighlightStyle()
        default_drawer = self.view.highlight.saved_drawer
        keep_shown_on_apply = true
    end
    local radio_buttons = {}
    for _, v in ipairs(highlight_style) do
        table.insert(radio_buttons, {
            {
                text = v[1],
                checked = item_drawer == v[2],
                provider = v[2],
            },
        })
    end
    UIManager:show(RadioButtonWidget:new{
        title_text = _("Highlight style"),
        width_factor = 0.5,
        keep_shown_on_apply = keep_shown_on_apply,
        radio_buttons = radio_buttons,
        default_provider = default_drawer,
        callback = function(radio)
            caller_callback(radio.provider)
        end,
    })
end

function ReaderHighlight:showHighlightColorDialog(caller_callback, item)
    local default_color, curr_color, keep_shown_on_apply
    if item then -- called from ReaderHighlight:editHighlightColor()
        default_color = self.view.highlight.saved_color
        curr_color = item.color or default_color
        keep_shown_on_apply = true
    else
        default_color = G_reader_settings:readSetting("highlight_color") or self._fallback_color
        curr_color = self.view.highlight.saved_color
    end
    local radio_buttons = {}
    for _, v in ipairs(self.highlight_colors) do
        table.insert(radio_buttons, {
            {
                text = v[1],
                checked = curr_color == v[2],
                bgcolor = BlitBuffer.colorFromName(v[2])
                       or BlitBuffer.Color8(bit.bxor(0xFF * self.view.highlight.lighten_factor, 0xFF)),
                provider = v[2],
            },
        })
    end
    UIManager:show(RadioButtonWidget:new{
        title_text = _("Highlight color"),
        width_factor = 0.5,
        keep_shown_on_apply = keep_shown_on_apply,
        radio_buttons = radio_buttons,
        default_provider = default_color,
        callback = function(radio)
            caller_callback(radio.provider)
        end,
        -- This ensures the waveform mode will be upgraded to a Kaleido wfm on compatible devices
        colorful = true,
        dithered = true,
    })
end

function ReaderHighlight:startSelection()
    self.highlight_idx = self:saveHighlight()
    self.select_mode = true
end

function ReaderHighlight:extendSelection()
    -- item1 - starting fragment (saved), item2 - ending fragment (currently selected)
    -- new extended highlight includes item1, item2 and the text between them
    local item1 = self.ui.annotation.annotations[self.highlight_idx]
    local item2_pos0, item2_pos1 = self.selected_text.pos0, self.selected_text.pos1
    -- getting starting and ending positions, text and pboxes of extended highlight
    local new_pos0, new_pos1, new_text, new_pboxes, ext
    if self.ui.paging then
        local cur_page = self.hold_pos.page
        local is_reflow = self.ui.document.configurable.text_wrap
        -- pos0 and pos1 are not in order within highlights, hence sorting all
        local function comparePositions (pos1, pos2)
            return self.ui.document:comparePositions(pos1, pos2) == 1
        end
        local positions = {item1.pos0, item1.pos1, item2_pos0, item2_pos1}
        self.ui.document.configurable.text_wrap = 0 -- native positions
        table.sort(positions, comparePositions)
        new_pos0 = positions[1]
        new_pos1 = positions[4]
        local temp_pos0, temp_pos1
        if new_pos0.page == new_pos1.page then -- single-page highlight
            local text_boxes = self.ui.document:getTextFromPositions(new_pos0, new_pos1)
            new_text = text_boxes.text
            new_pboxes = text_boxes.pboxes
            temp_pos0, temp_pos1 = new_pos0, new_pos1
        else -- multi-page highlight
            new_text = ""
            ext = {}
            for page = new_pos0.page, new_pos1.page do
                local item = self:getExtendedHighlightPage(new_pos0, new_pos1, page)
                new_text = new_text .. item.text
                ext[page] = { -- for every page of multi-page highlight
                    pos0 = item.pos0,
                    pos1 = item.pos1,
                    pboxes = item.pboxes,
                }
                if page == cur_page then
                    temp_pos0, temp_pos1 = item.pos0, item.pos1
                end
            end
        end
        self.ui.document.configurable.text_wrap = is_reflow -- restore reflow
        -- draw
        self.view.highlight.temp[cur_page] = self.ui.document:getPageBoxesFromPositions(cur_page, temp_pos0, temp_pos1)
    else
        -- pos0 and pos1 are in order within highlights
        new_pos0 = self.ui.document:compareXPointers(item1.pos0, item2_pos0) == 1 and item1.pos0 or item2_pos0
        new_pos1 = self.ui.document:compareXPointers(item1.pos1, item2_pos1) == 1 and item2_pos1 or item1.pos1
        -- true to draw
        new_text = self.ui.document:getTextFromXPointers(new_pos0, new_pos1, true)
    end
    self:deleteHighlight(self.highlight_idx) -- starting fragment
    self.selected_text = {
        text = new_text,
        pos0 = new_pos0,
        pos1 = new_pos1,
        pboxes = new_pboxes,
        ext = ext,
    }
    UIManager:setDirty(self.dialog, "ui")
end

-- Calculates positions, text, pboxes of one page of selected multi-page highlight
-- (For pdf documents only, reflow mode must be off)
function ReaderHighlight:getExtendedHighlightPage(pos0, pos1, cur_page)
    local item = {}
    for page = pos0.page, pos1.page do
        if page == cur_page then
            local page_boxes = self.ui.document:getTextBoxes(page)
            if page == pos0.page then
                -- first page (from the start of highlight to the end of the page)
                item.pos0 = {
                    x = pos0.x,
                    y = pos0.y,
                }
                item.pos1 = {
                    x = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1,
                    y = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1,
                }
            elseif page ~= pos1.page then
                -- middle pages (full pages)
                item.pos0 = {
                    x = page_boxes[1][1].x0,
                    y = page_boxes[1][1].y0,
                }
                item.pos1 = {
                    x = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1,
                    y = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1,
                }
            else
                -- last page (from the start of the page to the end of highlight)
                item.pos0 = {
                    x = page_boxes[1][1].x0,
                    y = page_boxes[1][1].y0,
                }
                item.pos1 = {
                    x = pos1.x,
                    y = pos1.y,
                }
            end
            item.pos0.page = page
            item.pos1.page = page
            local text_boxes = self.ui.document:getTextFromPositions(item.pos0, item.pos1)
            item.text = text_boxes.text
            item.pboxes = text_boxes.pboxes
        end
    end
    return item
end

-- Returns the list of highlights in page.
-- The list includes full single-page highlights and parts of multi-page highlights.
-- (For pdf documents only)
function ReaderHighlight:getPageSavedHighlights(page)
    local idx_offset
    local highlights = {}
    for index, highlight in ipairs(self.ui.annotation.annotations) do
        if highlight.drawer and highlight.pos0.page <= page and page <= highlight.pos1.page then
            if idx_offset == nil then
                idx_offset = index - 1
            end
            if highlight.ext then -- multi-page highlight
                local item = self:getSavedExtendedHighlightPage(highlight, page, index)
                table.insert(highlights, item)
            else
                table.insert(highlights, highlight)
            end
        end
    end
    return highlights, idx_offset
end

-- Returns one page of saved multi-page highlight
-- (For pdf documents only)
function ReaderHighlight:getSavedExtendedHighlightPage(highlight, page, index)
    local item = {
        datetime = highlight.datetime,
        drawer   = highlight.drawer,
        color    = highlight.color or self.view.highlight.saved_color,
        text     = highlight.text,
        note     = highlight.note,
        page     = highlight.page,
        pos0     = highlight.ext[page].pos0,
        pos1     = highlight.ext[page].pos1,
        pboxes   = highlight.ext[page].pboxes,
        parent   = index,
    }
    item.pos0.zoom     = highlight.pos0.zoom
    item.pos0.rotation = highlight.pos0.rotation
    item.pos1.zoom     = highlight.pos0.zoom
    item.pos1.rotation = highlight.pos0.rotation
    return item
end

function ReaderHighlight:onReadSettings(config)
    self.view.highlight.saved_drawer = config:readSetting("highlight_drawer")
        or G_reader_settings:readSetting("highlight_drawing_style") or self.view.highlight.saved_drawer
    self.view.highlight.saved_color = config:readSetting("highlight_color")
        or G_reader_settings:readSetting("highlight_color") or self.view.highlight.saved_color
    self.view.highlight.disabled = G_reader_settings:readSetting("default_highlight_action") == "nothing"

    self.allow_corner_scroll = G_reader_settings:nilOrTrue("highlight_corner_scroll")

    -- panel zoom settings isn't supported in EPUB
    if self.ui.paging then
        if self.document.is_pdf and self.document:_checkIfWritable() then
            if config:has("highlight_write_into_pdf") then
                self.highlight_write_into_pdf = config:isTrue("highlight_write_into_pdf") -- true or false
            else
                self.highlight_write_into_pdf = G_reader_settings:readSetting("highlight_write_into_pdf") -- true or nil
            end
        end
        local ext = util.getFileNameSuffix(self.ui.document.file)
        G_reader_settings:initializeExtSettings("panel_zoom_enabled", {cbz = true, cbt = true})
        G_reader_settings:initializeExtSettings("panel_zoom_fallback_to_text_selection", {pdf = true})
        if config:has("panel_zoom_enabled") then
            self.panel_zoom_enabled = config:isTrue("panel_zoom_enabled")
        else
            self.panel_zoom_enabled = G_reader_settings:getSettingForExt("panel_zoom_enabled", ext) or false
        end
        if config:has("panel_zoom_fallback_to_text_selection") then
            self.panel_zoom_fallback_to_text_selection = config:isTrue("panel_zoom_fallback_to_text_selection")
        else
            self.panel_zoom_fallback_to_text_selection = G_reader_settings:getSettingForExt("panel_zoom_fallback_to_text_selection", ext) or false
        end
    end
end

function ReaderHighlight:onUpdateHoldPanRate()
    self:setupTouchZones()
end

function ReaderHighlight:onSaveSettings()
    self.ui.doc_settings:saveSetting("highlight_drawer", self.view.highlight.saved_drawer)
    self.ui.doc_settings:saveSetting("highlight_color", self.view.highlight.saved_color)
    self.ui.doc_settings:saveSetting("highlight_write_into_pdf", self.highlight_write_into_pdf)
    self.ui.doc_settings:saveSetting("panel_zoom_enabled", self.panel_zoom_enabled)
end

function ReaderHighlight:onClose()
    if self.highlight_dialog then
        UIManager:close(self.highlight_dialog)
        self.highlight_dialog = nil
    end
    -- clear highlighted text
    self:clear()
end

-- dpad/keys support

function ReaderHighlight:onHighlightPress()
    if self._current_indicator_pos then
        if not self._start_indicator_highlight then
            -- try a tap at current indicator position to open any existing highlight
            if not self:onTap(nil, self:_createHighlightGesture("tap")) then
                -- no existing highlight at current indicator position: start hold
                self._start_indicator_highlight = true
                self:onHold(nil, self:_createHighlightGesture("hold"))
                -- With crengine, selected_text.sboxes does return good coordinates.
                if self.ui.rolling and self.selected_text and self.selected_text.sboxes and #self.selected_text.sboxes > 0 then
                    local pos = self.selected_text.sboxes[1]
                    -- set hold_pos to center of selected_test to make center selection more stable, not jitted at edge
                    self.hold_pos = self.view:screenToPageTransform({
                        x = pos.x + pos.w / 2,
                        y = pos.y + pos.h / 2
                    })
                    -- move indicator to center selected text making succeed same row selection much accurate.
                    UIManager:setDirty(self.dialog, "ui", self._current_indicator_pos)
                    self._current_indicator_pos.x = pos.x + pos.w / 2 - self._current_indicator_pos.w / 2
                    self._current_indicator_pos.y = pos.y + pos.h / 2 - self._current_indicator_pos.h / 2
                    UIManager:setDirty(self.dialog, "ui", self._current_indicator_pos)
                end
            else
                self:onStopHighlightIndicator(true) -- need_clear_selection=true
            end
        else
            self:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
            self:onStopHighlightIndicator()
        end
        return true
    end
    return false
end

function ReaderHighlight:onStartHighlightIndicator()
    -- disable long-press icon (poke-ball), as it is triggered constantly due to NT devices needing a workaround for text selection to work.
    self.long_hold_reached_action = function() end
    if self.view.visible_area and not self._current_indicator_pos then
        -- set start position to centor of page
        local rect = self._previous_indicator_pos
        if not rect then
            rect = Geom:new()
            rect.x = self.view.visible_area.w / 2
            rect.y = self.view.visible_area.h / 2
            rect.w = Size.item.height_default
            rect.h = rect.w
        end
        self._current_indicator_pos = rect
        self.view.highlight.indicator = rect
        UIManager:setDirty(self.dialog, "ui", rect)
        return true
    end
    return false
end

function ReaderHighlight:onStopHighlightIndicator(need_clear_selection)
    if self._current_indicator_pos then
        local rect = self._current_indicator_pos
        self._previous_indicator_pos = rect
        self._start_indicator_highlight = false
        self._current_indicator_pos = nil
        self.view.highlight.indicator = nil
        UIManager:setDirty(self.dialog, "ui", rect)
        if need_clear_selection then
            self:clear()
        end
        return true
    end
    return false
end

function ReaderHighlight:onMoveHighlightIndicator(args)
    if self.view.visible_area and self._current_indicator_pos then
        local dx, dy, quick_move = unpack(args)
        local quick_move_distance_dx = self.view.visible_area.w * (1/5) -- quick move distance: fifth of visible_area
        local quick_move_distance_dy = self.view.visible_area.h * (1/5)
        -- single move distance, user adjustable, default value (4) capable to move on word with small font size and narrow line height
        local move_distance = Size.item.height_default / (G_reader_settings:readSetting("highlight_non_touch_factor") or 4)
        local rect = self._current_indicator_pos:copy()
        if quick_move then
            rect.x = rect.x + quick_move_distance_dx * dx
            rect.y = rect.y + quick_move_distance_dy * dy
        else
            local now = time:now()
            if dx == self._last_indicator_move_args.dx and dy == self._last_indicator_move_args.dy then
                local diff = now - self._last_indicator_move_args.time
                -- if user presses same arrow key within 1 second (default, user adjustable), speed up
                -- double press: 4 single move distances, usually move to next word or line
                -- triple press: 16 single distances, usually skip several words or lines
                -- quadruple press: 64 single distances, almost move to screen edge
                if G_reader_settings:nilOrTrue("highlight_non_touch_spedup") then
                    -- user selects whether to use 'constant' or [this] 'sped up' rate (speed-up on by default)
                    local t_inter = G_reader_settings:readSetting("highlight_non_touch_interval") or 1
                    if diff < time.s( t_inter ) then
                        move_distance = self._last_indicator_move_args.distance * 4
                    end
                end
            end
            rect.x = rect.x + move_distance * dx
            rect.y = rect.y + move_distance * dy
            self._last_indicator_move_args.distance = move_distance
            self._last_indicator_move_args.dx = dx
            self._last_indicator_move_args.dy = dy
            self._last_indicator_move_args.time = now
        end
        if rect.x < 0 then
            rect.x = 0
        end
        if rect.x + rect.w > self.view.visible_area.w then
            rect.x = self.view.visible_area.w - rect.w
        end
        if rect.y < 0 then
            rect.y = 0
        end
        if rect.y + rect.h > self.view.visible_area.h then
            rect.y = self.view.visible_area.h - rect.h
        end
        UIManager:setDirty(self.dialog, "ui", self._current_indicator_pos)
        self._current_indicator_pos = rect
        self.view.highlight.indicator = rect
        UIManager:setDirty(self.dialog, "ui", rect)
        if self._start_indicator_highlight then
            self:onHoldPan(nil, self:_createHighlightGesture("hold_pan"))
        end
        return true
    end
    return false
end

function ReaderHighlight:_createHighlightGesture(gesture)
    local point = self._current_indicator_pos:copy()
    point.x = point.x + point.w / 2
    point.y = point.y + point.h / 2
    point.w = 0
    point.h = 0
    return {
        ges = gesture,
        pos = point,
        time = time.realtime(),
    }
end

return ReaderHighlight
