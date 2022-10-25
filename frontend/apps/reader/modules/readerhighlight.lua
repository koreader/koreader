local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
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
local T = require("ffi/util").template
local Screen = Device.screen

local ReaderHighlight = InputContainer:extend{}

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

local function cleanupSelectedText(text)
    -- Trim spaces and new lines at start and end
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    -- Trim spaces around newlines
    text = text:gsub("%s*\n%s*", "\n")
    -- Trim consecutive spaces (that would probably have collapsed
    -- in rendered CreDocuments)
    text = text:gsub("%s%s+", " ")
    return text
end

function ReaderHighlight:init()
    self.select_mode = false -- extended highlighting
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self._previous_indicator_pos = nil
    self._last_indicator_move_args = {dx = 0, dy = 0, distance = 0, time = time:now()}

    if Device:hasDPad() then
        -- Used for text selection with dpad/keys
        local QUICK_INDICTOR_MOVE = true
        self.key_events.StopHighlightIndicator = { {Device.input.group.Back}, doc = "Stop non-touch highlight", args = true } -- true: clear highlight selection
        self.key_events.UpHighlightIndicator = { {"Up"}, doc = "move indicator up", event = "MoveHighlightIndicator", args = {0, -1} }
        self.key_events.DownHighlightIndicator = { {"Down"}, doc = "move indicator down", event = "MoveHighlightIndicator", args = {0, 1} }
        -- let FewKeys device can move indicator left
        self.key_events.LeftHighlightIndicator = { {"Left"}, doc = "move indicator left", event = "MoveHighlightIndicator", args = {-1, 0} }
        self.key_events.RightHighlightIndicator = { {"Right"}, doc = "move indicator right", event = "MoveHighlightIndicator", args = {1, 0} }
        self.key_events.HighlightPress = { {"Press"}, doc = "highlight start or end" }
        if Device:hasKeys() then
            self.key_events.QuickUpHighlightIndicator = { {"Shift", "Up"}, doc = "quick move indicator up", event = "MoveHighlightIndicator", args = {0, -1, QUICK_INDICTOR_MOVE} }
            self.key_events.QuickDownHighlightIndicator = { {"Shift", "Down"}, doc = "quick move indicator down", event = "MoveHighlightIndicator", args = {0, 1, QUICK_INDICTOR_MOVE} }
            self.key_events.QuickLeftHighlightIndicator = { {"Shift", "Left"}, doc = "quick move indicator left", event = "MoveHighlightIndicator", args = {-1, 0, QUICK_INDICTOR_MOVE} }
            self.key_events.QuickRightHighlightIndicator = { {"Shift", "Right"}, doc = "quick move indicator right", event = "MoveHighlightIndicator", args = {1, 0, QUICK_INDICTOR_MOVE} }
            self.key_events.StartHighlightIndicator = { {"H"}, doc = "start non-touch highlight" }
        end
    end

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
                callback = function()
                    this:saveHighlight(true)
                    this:onClose()
                end,
                enabled = this.hold_pos ~= nil,
            }
        end,
        ["03_copy"] = function(this)
            return {
                text = C_("Text", "Copy"),
                enabled = Device:hasClipboard(),
                callback = function()
                    Device.input.setClipboardText(cleanupSelectedText(this.selected_text.text))
                    this:onClose()
                    UIManager:show(Notification:new{
                        text = _("Selection copied to clipboard."),
                    })
                end,
            }
        end,
        ["04_add_note"] = function(this)
            return {
                text = _("Add Note"),
                callback = function()
                    this:addNote()
                    this:onClose()
                end,
                enabled = this.hold_pos ~= nil,
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
        ["07_translate"] = function(this, page, index)
            return {
                text = _("Translate"),
                callback = function()
                    this:translate(this.selected_text, page, index)
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
                    local text = cleanupSelectedText(this.selected_text.text)
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
end

function ReaderHighlight:setupTouchZones()
    -- deligate gesture listener to readerui
    self.ges_events = {}
    self.onGesture = nil

    if not Device:isTouchDevice() then return end
    local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate")
    if not hold_pan_rate then
        hold_pan_rate = Screen.low_pan_rate and 5.0 or 30.0
    end
    self.ui:registerTouchZones({
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
end

local highlight_style = {
    {_("Lighten"), "lighten"},
    {_("Underline"), "underscore"},
    {_("Strikeout"), "strikeout"},
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
    {_("Translate"), "translate"},
    {_("Wikipedia"), "wikipedia"},
    {_("Dictionary"), "dictionary"},
    {_("Fulltext search"), "search"},
}

function ReaderHighlight:addToMainMenu(menu_items)
    -- insert table to main reader menu
    if not Device:isTouchDevice() and Device:hasDPad() then
        menu_items.start_content_selection = {
            text = _("Start content selection"),
            callback = function()
                self:onStartHighlightIndicator()
            end,
        }
    end
    menu_items.highlight_options = {
        text = _("Highlight style"),
        sub_item_table = {},
    }
    for i, v in ipairs(highlight_style) do
        table.insert(menu_items.highlight_options.sub_item_table, {
            text_func = function()
                local text = v[1]
                if v[2] == G_reader_settings:readSetting("highlight_drawing_style") then
                    text = text .. "   ★"
                end
                return text
            end,
            checked_func = function()
                return self.view.highlight.saved_drawer == v[2]
            end,
            radio = true,
            callback = function()
                self.view.highlight.saved_drawer = v[2]
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("highlight_drawing_style", v[2])
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = i == #highlight_style,
        })
    end
    table.insert(menu_items.highlight_options.sub_item_table, {
        text_func = function()
            return T(_("Highlight opacity: %1"), G_reader_settings:readSetting("highlight_lighten_factor", 0.2))
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer == "lighten"
        end,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_val = G_reader_settings:readSetting("highlight_lighten_factor", 0.2)
            local spin_widget = SpinWidget:new{
                value = curr_val,
                value_min = 0,
                value_max = 1,
                precision = "%.2f",
                value_step = 0.1,
                value_hold_step = 0.25,
                default_value = 0.2,
                keep_shown_on_apply = true,
                title_text =  _("Highlight opacity"),
                info_text = _("The higher the value, the darker the highlight."),
                callback = function(spin)
                    G_reader_settings:saveSetting("highlight_lighten_factor", spin.value)
                    self.view.highlight.lighten_factor = spin.value
                    UIManager:setDirty(self.dialog, "ui")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            }
            UIManager:show(spin_widget)
        end,
    })
    table.insert(menu_items.highlight_options.sub_item_table, {
        text_func = function()
            local notemark = self.view.highlight.note_mark or "none"
            for __, v in ipairs(note_mark) do
                if v[2] == notemark then
                    return T(_("Note marker: %1"), string.lower(v[1]))
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
            UIManager:show(require("ui/widget/radiobuttonwidget"):new{
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
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    })
    if self.document.info.has_pages then
        menu_items.panel_zoom_options = {
            text = _("Panel zoom (manga/comic)"),
            sub_item_table = self:genPanelZoomMenu(),
        }
    end
    menu_items.translation_settings = Translator:genSettingsMenu()

    menu_items.long_press = {
        text = _("Long-press on text"),
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Highlight long-press interval: %1 s"),
                        G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items = SpinWidget:new{
                        title_text = _("Highlight long-press interval"),
                        info_text = _([[
If a touch is not released in this interval, it is considered a long-press. On document text, single word selection will not be triggered.

The interval value is in seconds and can range from 3 to 20 seconds.]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3),
                        value_min = 3,
                        value_max = 20,
                        value_step = 1,
                        value_hold_step = 5,
                        unit = C_("Time", "s"),
                        ok_text = _("Set interval"),
                        default_value = 3,
                        callback = function(spin)
                            G_reader_settings:saveSetting("highlight_long_hold_threshold_s", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items)
                end,
            },
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
    for _, v in ipairs(long_press_action) do
        table.insert(menu_items.long_press.sub_item_table, {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("default_highlight_action", "ask") == v[2]
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("default_highlight_action", v[2])
                self.view.highlight.disabled = v[2] == "nothing"
            end,
        })
    end
    -- long_press menu is under taps_and_gestures menu which is not available for non touch device
    -- Clone long_press menu and change label making much meaning for non touch devices
    if not Device:isTouchDevice() and Device:hasDPad() then
        menu_items.selection_text = util.tableDeepCopy(menu_items.long_press)
        menu_items.selection_text.text = _("Select on text")
    end
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
    if self.ui.document.info.has_pages then
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

function ReaderHighlight:onTap(_, ges)
    -- We only actually need to clear if we have something to clear in the first place.
    -- (We mainly want to avoid CRe's clearSelection,
    -- which may incur a redraw as it invalidates the cache, c.f., #6854)
    -- ReaderHighlight:clear can only return true if self.hold_pos was set anyway.
    local cleared = self.hold_pos and self:clear()
    -- We only care about potential taps on existing highlights, not on taps that closed a highlight menu.
    if not cleared and ges and not self.select_mode then
        if self.ui.document.info.has_pages then
            return self:onTapPageSavedHighlight(ges)
        else
            return self:onTapXPointerSavedHighlight(ges)
        end
    end
end

function ReaderHighlight:onTapPageSavedHighlight(ges)
    local pages = self.view:getCurrentPageList()
    local pos = self.view:screenToPageTransform(ges.pos)
    for key, page in pairs(pages) do
        local items = self.view.highlight.saved[page]
        if items then
            for i = 1, #items do
                local pos0, pos1 = items[i].pos0, items[i].pos1
                local boxes = self.ui.document:getPageBoxesFromPositions(page, pos0, pos1)
                if boxes then
                    for index, box in pairs(boxes) do
                        if inside_box(pos, box) then
                            logger.dbg("Tap on highlight")
                            return self:onShowHighlightNoteOrDialog(page, i)
                        end
                    end
                end
            end
        end
    end
end

function ReaderHighlight:onTapXPointerSavedHighlight(ges)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    local cur_view_top, cur_view_bottom
    local pos = self.view:screenToPageTransform(ges.pos)
    -- NOTE: By now, pos.page is set, but if a highlight spans across multiple pages,
    --       it's stored under the hash of its *starting* point,
    --       so we can't just check the current page, hence the giant hashwalk of death...
    --       We can't even limit the walk to page <= pos.page,
    --       because pos.page isn't super accurate in continuous mode
    --       (it's the page number for what's it the topleft corner of the screen,
    --       i.e., often a bit earlier)...
    for page, items in pairs(self.view.highlight.saved) do
        if items then
            for i = 1, #items do
                local item = items[i]
                local pos0, pos1 = item.pos0, item.pos1
                -- document:getScreenBoxesFromPositions() is expensive, so we
                -- first check this item is on current page
                if not cur_view_top then
                    -- Even in page mode, it's safer to use pos and ui.dimen.h
                    -- than pages' xpointers pos, even if ui.dimen.h is a bit
                    -- larger than pages' heights
                    cur_view_top = self.ui.document:getCurrentPos()
                    if self.view.view_mode == "page" and self.ui.document:getVisiblePageCount() > 1 then
                        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
                    else
                        cur_view_bottom = cur_view_top + self.ui.dimen.h
                    end
                end
                local spos0 = self.ui.document:getPosFromXPointer(pos0)
                local spos1 = self.ui.document:getPosFromXPointer(pos1)
                local start_pos = math.min(spos0, spos1)
                local end_pos = math.max(spos0, spos1)
                if start_pos <= cur_view_bottom and end_pos >= cur_view_top then
                    local boxes = self.ui.document:getScreenBoxesFromPositions(pos0, pos1, true) -- get_segments=true
                    if boxes then
                        for index, box in pairs(boxes) do
                            if inside_box(pos, box) then
                                logger.dbg("Tap on highlight")
                                return self:onShowHighlightNoteOrDialog(page, i)
                            end
                        end
                    end
                end
            end
        end
    end
end

function ReaderHighlight:updateHighlight(page, index, side, direction, move_by_char)
    if self.ui.document.info.has_pages then -- we do this only if it's epub file
        return
    end

    local highlight = self.view.highlight.saved[page][index]
    local highlight_time = highlight.datetime
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
                self.view.highlight.saved[page][index].pos0 = updated_highlight_beginning
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
                self.view.highlight.saved[page][index].pos1 = updated_highlight_end
            end
        end
    end

    local new_beginning = self.view.highlight.saved[page][index].pos0
    local new_end = self.view.highlight.saved[page][index].pos1
    local new_text = self.ui.document:getTextFromXPointers(new_beginning, new_end)
    local new_chapter = self.ui.toc:getTocTitleByPage(new_beginning)
    self.view.highlight.saved[page][index].text = cleanupSelectedText(new_text)
    self.view.highlight.saved[page][index].chapter = new_chapter
    local new_highlight = self.view.highlight.saved[page][index]
    self.ui.bookmark:updateBookmark({
        page = highlight_beginning,
        datetime = highlight_time,
        updated_highlight = new_highlight
    })
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
                local top_y = end_y - math.floor(Screen:getHeight() * 2/3)
                self.ui.rolling:_gotoPos(top_y)
            end
        end
    end
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:onShowHighlightNoteOrDialog(page, index)
    local item = self.view.highlight.saved[page][index]
    local bookmark_note = self.ui.bookmark:getBookmarkNote({
        page = self.ui.document.info.has_pages and item.pos0.page or item.pos0,
        datetime = item.datetime,
    })
    if bookmark_note then
        local textviewer
        textviewer = TextViewer:new{
            title = _("Note"),
            text = bookmark_note,
            width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8),
            height = math.floor(math.max(Screen:getWidth(), Screen:getHeight()) * 0.4),
            justified = G_reader_settings:nilOrTrue("dict_justify"),
            buttons_table = {
                {
                    {
                        text = _("Close"),
                        callback = function()
                            UIManager:close(textviewer)
                        end,
                    },
                    {
                        text = _("Edit highlight"),
                        callback = function()
                            UIManager:close(textviewer)
                            self:onShowHighlightDialog(page, index, false)
                        end,
                    },
                },
            },
        }
        UIManager:show(textviewer)
    else
        self:onShowHighlightDialog(page, index, true)
    end
    return true
end

function ReaderHighlight:onShowHighlightDialog(page, index, is_auto_text)
    local buttons = {
        {
            {
                text = _("Delete"),
                callback = function()
                    self:deleteHighlight(page, index)
                    -- other part outside of the dialog may be dirty
                    UIManager:close(self.edit_highlight_dialog, "ui")
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = C_("Highlight", "Style"),
                callback = function()
                    self:editHighlightStyle(page, index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = is_auto_text and _("Add note") or _("Edit note"),
                callback = function()
                    self:editHighlight(page, index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
            {
                text = "…",
                callback = function()
                    self.selected_text = self.view.highlight.saved[page][index]
                    self:onShowHighlightMenu(page, index)
                    UIManager:close(self.edit_highlight_dialog)
                    self.edit_highlight_dialog = nil
                end,
            },
        }
    }

    if self.ui.rolling then
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
                callback = function()
                    self:updateHighlight(page, index, 0, -1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(page, index, 0, -1, true)
                    return true
                end
            },
            {
                text = start_next,
                callback = function()
                    self:updateHighlight(page, index, 0, 1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(page, index, 0, 1, true)
                    return true
                end
            },
            {
                text = end_prev,
                callback = function()
                    self:updateHighlight(page, index, 1, -1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(page, index, 1, -1, true)
                end
            },
            {
                text = end_next,
                callback = function()
                    self:updateHighlight(page, index, 1, 1, false)
                end,
                hold_callback = function()
                    self:updateHighlight(page, index, 1, 1, true)
                end
            }
        })
    end
    self.edit_highlight_dialog = ButtonDialog:new{
        buttons = buttons
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

function ReaderHighlight:onShowHighlightMenu(page, index)
    if not self.selected_text then
        return
    end

    local highlight_buttons = {{}}

    local columns = 2
    for idx, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
        local button = fn_button(self, page, index)
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

function ReaderHighlight:_resetHoldTimer(clear)
    if clear then
        self.hold_last_time = nil
    else
        self.hold_last_time = UIManager:getTime()
    end
end

function ReaderHighlight:onTogglePanelZoomSetting(arg, ges)
    if not self.document.info.has_pages then return end
    self.panel_zoom_enabled = not self.panel_zoom_enabled
end

function ReaderHighlight:onToggleFallbackTextSelection(arg, ges)
    if not self.document.info.has_pages then return end
    self.panel_zoom_fallback_to_text_selection = not self.panel_zoom_fallback_to_text_selection
end

function ReaderHighlight:onPanelZoom(arg, ges)
    self:clear()
    local hold_pos = self.view:screenToPageTransform(ges.pos)
    if not hold_pos then return false end -- outside page boundary
    local rect = self.ui.document:getPanelFromPage(hold_pos.page, hold_pos)
    if not rect then return false end -- panel not found, return
    local image = self.ui.document:getPagePart(hold_pos.page, rect, 0)

    if image then
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            with_title_bar = false,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
        return true
    end
    return false
end

function ReaderHighlight:onHold(arg, ges)
    if self.document.info.has_pages and self.panel_zoom_enabled then
        local res = self:onPanelZoom(arg, ges)
        if res or not self.panel_zoom_fallback_to_text_selection then
            return res
        end
    end

    self:clear() -- clear previous highlight (delayed clear may not have done it yet)
    self.hold_ges_pos = ges.pos -- remember hold original gesture position
    self.hold_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("hold position in page", self.hold_pos)
    if not self.hold_pos then
        logger.dbg("not inside page area")
        return false
    end

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

        if self.ui.document.info.has_pages then
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

    if self.ui.rolling and self.selected_text_start_xpointer then
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
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*Screen:getHeight()
                                      and self.holdpan_pos.x > 7/8*Screen:getWidth()
            -- bottom left corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*Screen:getHeight()
                                          and self.holdpan_pos.x < 1/8*Screen:getWidth()
        else -- default in LTR UI with no inverse_reading_order
            -- top left corner
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*Screen:getHeight()
                                      and self.holdpan_pos.x < 1/8*Screen:getWidth()
            -- bottom right corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*Screen:getHeight()
                                      and self.holdpan_pos.x > 7/8*Screen:getWidth()
        end
        if is_in_prev_page_corner or is_in_next_page_corner then
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
                local scroll_distance = math.floor(Screen:getHeight() * 1/3)
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
                local screen_half_width = math.floor(Screen:getWidth() * 0.5)
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

KOReader has a build-in OCR engine for recognizing words in scanned PDF and DjVu documents. In order to use OCR in scanned pages, you need to install tesseract trained data for your document language.

You can download language data files for version 3.04 from https://tesseract-ocr.github.io/tessdoc/Data-Files

Copy the language data files for Tesseract 3.04 (e.g., eng.traineddata for English and spa.traineddata for Spanish) into koreader/data/tessdata]])

function ReaderHighlight:lookup(selected_text, selected_link)
    -- convert sboxes to word boxes
    local word_boxes = {}
    for i, sbox in ipairs(selected_text.sboxes) do
        word_boxes[i] = self.view:pageToScreenTransform(self.hold_pos.page, sbox)
    end

    -- if we extracted text directly
    if selected_text.text and self.hold_pos then
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
                                                 self.selected_text.text, nb_words, self.selected_text.pos0, self.selected_text.pos1)
    if ok then
        return prev_context, next_context
    end
end

function ReaderHighlight:viewSelectionHTML(debug_view, no_css_files_buttons)
    if self.ui.document.info.has_pages then
        return
    end
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        -- For available flags, see the "#define WRITENODEEX_*" in crengine/src/lvtinydom.cpp
        -- Start with valid and classic displayed HTML (with only block nodes indented),
        -- including styles found in <HEAD>, linked CSS files content, and misc info.
        local html_flags = 0x6830
        if not debug_view then
            debug_view = 0
        end
        if debug_view == 1 then
            -- Each node on a line, with markers and numbers of skipped chars and siblings shown,
            -- with possibly invalid HTML (text nodes not escaped)
            html_flags = 0x6B5A
        elseif debug_view == 2 then
            -- Additionally see rendering methods of each node
            html_flags = 0x6F5A
        elseif debug_view == 3 then
            -- Or additionally see unicode codepoint of each char
            html_flags = 0x6B5E
        end
        local html, css_files = self.ui.document:getHTMLFromXPointers(self.selected_text.pos0,
                                    self.selected_text.pos1, html_flags, true)
        if html then
            -- Make some invisible chars visible
            if debug_view >= 1 then
                html = html:gsub("\xC2\xA0", "␣")  -- no break space: open box
                html = html:gsub("\xC2\xAD", "⋅") -- soft hyphen: dot operator (smaller than middle dot ·)
                -- Prettify inlined CSS (from <HEAD>, put in an internal
                -- <body><stylesheet> element by crengine (the opening tag may
                -- include some href=, or end with " ~X>" with some html_flags)
                -- (We do that in debug_view mode only: as this may increase
                -- the height of this section, we don't want to have to scroll
                -- many pages to get to the HTML content on the initial view.)
                html = html:gsub("(<stylesheet[^>]*>)%s*(.-)%s*(</stylesheet>)", function(pre, css_text, post)
                    return pre .. "\n" .. util.prettifyCSS(css_text) .. post
                end)
            end
            local Font = require("ui/font")
            local textviewer
            local buttons_hold_callback = function()
                -- Allow hiding css files buttons if there are too many
                -- and the available height for text is too short
                UIManager:close(textviewer)
                self:viewSelectionHTML(debug_view, not no_css_files_buttons)
            end
            local buttons_table = {}
            if css_files and not no_css_files_buttons then
                for i=1, #css_files do
                    local button = {
                        text = T(_("View %1"), BD.filepath(css_files[i])),
                        callback = function()
                            local css_text = self.ui.document:getDocumentFileContent(css_files[i])
                            local cssviewer
                            cssviewer = TextViewer:new{
                                title = css_files[i],
                                text = css_text or _("Failed getting CSS content"),
                                text_face = Font:getFace("smallinfont"),
                                justified = false,
                                para_direction_rtl = false,
                                auto_para_direction = false,
                                add_default_buttons = true,
                                buttons_table = {
                                    {{
                                        text = _("Prettify"),
                                        enabled = css_text and true or false,
                                        callback = function()
                                            UIManager:close(cssviewer)
                                            UIManager:show(TextViewer:new{
                                                title = css_files[i],
                                                text = util.prettifyCSS(css_text),
                                                text_face = Font:getFace("smallinfont"),
                                                justified = false,
                                                para_direction_rtl = false,
                                                auto_para_direction = false,
                                            })
                                        end,
                                    }},
                                }
                            }
                            UIManager:show(cssviewer)
                        end,
                        hold_callback = buttons_hold_callback,
                    }
                    -- One button per row, to make room for the possibly long css filename
                    table.insert(buttons_table, {button})
                end
            end
            local next_debug_text
            local next_debug_view = debug_view + 1
            if next_debug_view == 1 then
                next_debug_text = _("Switch to debug view")
            elseif next_debug_view == 2 then
                next_debug_text = _("Switch to rendering debug view")
            elseif next_debug_view == 3 then
                next_debug_text = _("Switch to unicode debug view")
            else
                next_debug_view = 0
                next_debug_text = _("Switch to standard view")
            end
            table.insert(buttons_table, {{
                text = next_debug_text,
                callback = function()
                    UIManager:close(textviewer)
                    self:viewSelectionHTML(next_debug_view, no_css_files_buttons)
                end,
                hold_callback = buttons_hold_callback,
            }})
            textviewer = TextViewer:new{
                title = _("Selection HTML"),
                text = html,
                text_face = Font:getFace("smallinfont"),
                justified = false,
                para_direction_rtl = false,
                auto_para_direction = false,
                add_default_buttons = true,
                default_hold_callback = buttons_hold_callback,
                buttons_table = buttons_table,
            }
            UIManager:show(textviewer)
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed getting HTML for selection"),
            })
        end
    end
end

function ReaderHighlight:translate(selected_text, page, index)
    if self.ui.rolling then
        -- Extend the selected text to include any punctuation at start or end,
        -- which may give a better translation with the added context.
        local extended_text = self.ui.document:extendXPointersToSentenceSegment(selected_text.pos0, selected_text.pos1)
        if extended_text then
            selected_text = extended_text
        end
    end
    if selected_text.text ~= "" then
        self:onTranslateText(selected_text.text, page, index)
    -- or we will do OCR
    elseif self.hold_pos then
        local text = self.ui.document:getOCRText(self.hold_pos.page, selected_text)
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
dbg:guard(ReaderHighlight, "translate",
    function(self, selected_text)
        assert(selected_text ~= nil,
            "translate must not be called with nil selected_text!")
    end)

function ReaderHighlight:onTranslateText(text, page, index)
    Translator:showTranslation(text, false, false, true, page, index)
end

function ReaderHighlight:onHoldRelease()
    if self.clear_id then
        -- Something has requested a clear id and is about to clear
        -- the highlight: it may be a onHoldClose() that handled
        -- "hold" and was closed, and can't handle "hold_release":
        -- ignore this "hold_release" event.
        return true
    end

    local default_highlight_action = G_reader_settings:readSetting("default_highlight_action", "ask")

    if self.select_mode then -- extended highlighting, ending fragment
        if self.selected_text then
            if self.ui.document.info.has_pages and self.ui.paging.current_page ~= self.highlight_page then
                self.ui.paging:_gotoPage(self.highlight_page)
                UIManager:show(Notification:new{
                    text = _("Fragments must be within one page"),
                })
            else
                self.select_mode = false
                self:extendSelection()
                if default_highlight_action == "select" then
                    self:saveHighlight(true)
                    self:clear()
                else
                    self:onShowHighlightMenu()
                end
            end
        end
        return true
    end

    local long_final_hold = false
    if self.hold_last_time then
        local hold_duration = time.now() - self.hold_last_time
        local long_hold_threshold_s = G_reader_settings:readSetting("highlight_long_hold_threshold_s", 3) -- seconds
        if hold_duration > time.s(long_hold_threshold_s) then
            -- We stayed 3 seconds before release without updating selection
            long_final_hold = true
        end
        self.hold_last_time = nil
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
            elseif default_highlight_action == "translate" then
                self:translate(self.selected_text)
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
    G_reader_settings:saveSetting("default_highlight_action", long_press_action[next_action_num][2])
    UIManager:show(Notification:new{
        text = T(_("Default highlight action changed to '%1'."), long_press_action[next_action_num][1]),
    })
    return true
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
    self.ui.doc_settings:saveSetting("highlight_drawer", self.view.highlight.saved_drawer)
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

function ReaderHighlight:onHighlight()
    self:saveHighlight()
end

function ReaderHighlight:onUnhighlight(bookmark_item)
    local page
    local sel_text
    local sel_pos0
    local datetime
    local idx
    if bookmark_item then -- called from Bookmarks menu onHold
        page = bookmark_item.page
        sel_text = bookmark_item.notes
        sel_pos0 = bookmark_item.pos0
        datetime = bookmark_item.datetime
    else -- called from DictQuickLookup Unhighlight button
        --- @fixme: is this self.hold_pos access safe?
        page = self.hold_pos.page
        sel_text = cleanupSelectedText(self.selected_text.text)
        sel_pos0 = self.selected_text.pos0
    end
    if self.ui.document.info.has_pages then -- We can safely use page
        -- As we may have changed spaces and hyphens handling in the extracted
        -- text over the years, check text identities with them removed
        local sel_text_cleaned = sel_text:gsub("[ -]", ""):gsub("\xC2\xAD", "")
        for index = 1, #self.view.highlight.saved[page] do
            local highlight = self.view.highlight.saved[page][index]
            -- pos0 are tables and can't be compared directly, except when from
            -- DictQuickLookup where these are the same object.
            -- If bookmark_item provided, just check datetime
            if ( (datetime == nil and highlight.pos0 == sel_pos0) or
                 (datetime ~= nil and highlight.datetime == datetime) ) then
                if highlight.text:gsub("[ -]", ""):gsub("\xC2\xAD", "") == sel_text_cleaned then
                    idx = index
                    break
                end
            end
        end
    else -- page is a xpointer
        -- The original page could be found in bookmark_item.text, but
        -- no more if it has been renamed: we need to loop through all
        -- highlights on all page slots
        for p, highlights in pairs(self.view.highlight.saved) do
            for index = 1, #highlights do
                local highlight = highlights[index]
                -- pos0 are strings and can be compared directly
                if highlight.text == sel_text and (
                        (datetime == nil and highlight.pos0 == sel_pos0) or
                        (datetime ~= nil and highlight.datetime == datetime)) then
                    page = p -- this is the original page slot
                    idx = index
                    break
                end
            end
            if idx then
                break
            end
        end
    end
    if bookmark_item and not idx then
        logger.warn("unhighlight: bookmark_item not found among highlights", bookmark_item)
        -- Remove it from bookmarks anyway, so we're not stuck with an
        -- unremovable bookmark
        self.ui.bookmark:removeBookmark(bookmark_item)
        return
    end
    logger.dbg("found highlight to delete on page", page, idx)
    self:deleteHighlight(page, idx, bookmark_item)
    return true
end

function ReaderHighlight:getHighlightBookmarkItem()
    if self.hold_pos and not self.selected_text then
        self:highlightFromHoldPos()
    end
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        return {
            page = self.ui.paging and self.hold_pos.page or self.selected_text.pos0,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            notes = cleanupSelectedText(self.selected_text.text),
            highlighted = true,
        }
    end
end

function ReaderHighlight:saveHighlight(extend_to_sentence)
    self.ui:handleEvent(Event:new("AddHighlight"))
    logger.dbg("save highlight")
    if self.hold_pos and self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        if extend_to_sentence and self.ui.rolling then
            local extended_text = self.ui.document:extendXPointersToSentenceSegment(self.selected_text.pos0, self.selected_text.pos1)
            if extended_text then
                self.selected_text = extended_text
            end
        end
        local page = self.hold_pos.page
        if not self.view.highlight.saved[page] then
            self.view.highlight.saved[page] = {}
        end
        local datetime = os.date("%Y-%m-%d %H:%M:%S")
        local pg_or_xp = self.ui.paging and page or self.selected_text.pos0
        local chapter_name = self.ui.toc:getTocTitleByPage(pg_or_xp)
        local hl_item = {
            datetime = datetime,
            text = cleanupSelectedText(self.selected_text.text),
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            pboxes = self.selected_text.pboxes,
            drawer = self.view.highlight.saved_drawer,
            chapter = chapter_name,
        }
        table.insert(self.view.highlight.saved[page], hl_item)
        local bookmark_item = self:getHighlightBookmarkItem()
        if bookmark_item then
            bookmark_item.datetime = datetime
            bookmark_item.chapter = chapter_name
            self.ui.bookmark:addBookmark(bookmark_item)
        end
        if self.selected_text.pboxes then
            self:exportToDocument(page, hl_item)
        end
        return page, #self.view.highlight.saved[page]
    end
end

function ReaderHighlight:exportToDocument(page, item)
    local setting = G_reader_settings:readSetting("save_document")
    if setting == "disable" then return end
    logger.dbg("export highlight to document", item)
    local can_write = self.ui.document:saveHighlight(page, item)
    if can_write == false and not self.warned_once then
        self.warned_once = true
        UIManager:show(InfoMessage:new{
            text = _([[
Highlights in this document will be saved in the settings file, but they won't be written in the document itself because the file is in a read-only location.

If you wish your highlights to be saved in the document, just move it to a writable directory first.]]),
            timeout = 5,
        })
    end
end

function ReaderHighlight:addNote(text)
    local page, index = self:saveHighlight(true)
    if text then self:clear() end
    self:editHighlight(page, index, true, text)
    UIManager:close(self.edit_highlight_dialog)
    self.edit_highlight_dialog = nil
    self.ui:handleEvent(Event:new("AddNote"))
end

function ReaderHighlight:lookupWikipedia()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWikipedia", cleanupSelectedText(self.selected_text.text)))
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
        local text = util.stripPunctuation(cleanupSelectedText(self.selected_text.text))
        self.ui:handleEvent(Event:new("ShowSearchDialog", text))
    end
end

function ReaderHighlight:onHighlightDictLookup()
    logger.dbg("dictionary lookup highlight")
    self:highlightFromHoldPos()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWord", cleanupSelectedText(self.selected_text.text)))
    end
end

function ReaderHighlight:deleteHighlight(page, i, bookmark_item)
    self.ui:handleEvent(Event:new("DelHighlight"))
    logger.dbg("delete highlight", page, i)
    -- The per-page table is a pure array
    local removed = table.remove(self.view.highlight.saved[page], i)
    -- But the main, outer table is a hash, so clear the table for this page if there are no longer any highlights on it
    if #self.view.highlight.saved[page] == 0 then
        self.view.highlight.saved[page] = nil
    end
    if bookmark_item then
        self.ui.bookmark:removeBookmark(bookmark_item)
    else
        self.ui.bookmark:removeBookmark({
            page = self.ui.document.info.has_pages and page or removed.pos0,
            datetime = removed.datetime,
        })
    end
    local setting = G_reader_settings:readSetting("save_document")
    if setting ~= "disable" then
        logger.dbg("delete highlight from document", removed)
        self.ui.document:deleteHighlight(page, removed)
    end
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:editHighlight(page, i, is_new_note, text)
    local item = self.view.highlight.saved[page][i]
    self.ui.bookmark:renameBookmark({
        page = self.ui.document.info.has_pages and page or item.pos0,
        datetime = item.datetime,
        pboxes = item.pboxes
    }, true, is_new_note, text)
end

function ReaderHighlight:editHighlightStyle(page, i)
    local item = self.view.highlight.saved[page][i]
    local save_document = self.ui.paging and G_reader_settings:readSetting("save_document") ~= "disable"
    local radio_buttons = {}
    for _, v in ipairs(highlight_style) do
        table.insert(radio_buttons, {
            {
                text = v[1],
                checked = item.drawer == v[2],
                provider = v[2],
            },
        })
    end
    UIManager:show(require("ui/widget/radiobuttonwidget"):new{
        title_text = _("Highlight style"),
        width_factor = 0.5,
        keep_shown_on_apply = true,
        radio_buttons = radio_buttons,
        default_provider = self.view.highlight.saved_drawer or
            G_reader_settings:readSetting("highlight_drawing_style", "lighten"),
        callback = function(radio)
            if save_document then
                self.ui.document:deleteHighlight(page, item)
            end
            item.drawer = radio.provider
            if save_document then
                self.ui.document:saveHighlight(page, item)
            end
            UIManager:setDirty(self.dialog, "ui")
            self.ui:handleEvent(Event:new("BookmarkUpdated",
                    self.ui.bookmark:getBookmarkForHighlight({
                        page = self.ui.paging and page or item.pos0,
                        datetime = item.datetime,
                    })))
        end,
    })
end

function ReaderHighlight:startSelection()
    self.highlight_page, self.highlight_idx = self:saveHighlight()
    self.select_mode = true
    UIManager:show(Notification:new{
        text = _("Select ending fragment"),
    })
end

function ReaderHighlight:extendSelection()
    -- item1 - starting fragment (saved), item2 - ending fragment (currently selected)
    -- new extended highlight includes item1, item2 and the text between them
    local item1 = self.view.highlight.saved[self.highlight_page][self.highlight_idx]
    local item2_pos0, item2_pos1 = self.selected_text.pos0, self.selected_text.pos1
    -- getting starting and ending positions, text and pboxes of extended highlight
    local new_pos0, new_pos1, new_text, new_pboxes
    if self.ui.document.info.has_pages then
        local is_reflow = self.ui.document.configurable.text_wrap
        local new_page = self.hold_pos.page
        -- reflow mode doesn't set page in positions
        item1.pos0.page = new_page
        item1.pos1.page = new_page
        item2_pos0.page = new_page
        item2_pos1.page = new_page
        -- pos0 and pos1 are not in order within highlights, hence sorting all
        local function comparePositions (pos1, pos2)
            return self.ui.document:comparePositions(pos1, pos2) == 1
        end
        local positions = {item1.pos0, item1.pos1, item2_pos0, item2_pos1}
        self.ui.document.configurable.text_wrap = 0 -- native positions
        table.sort(positions, comparePositions)
        new_pos0 = positions[1]
        new_pos1 = positions[4]
        local text_boxes = self.ui.document:getTextFromPositions(new_pos0, new_pos1)
        new_text = text_boxes.text
        new_pboxes = text_boxes.pboxes
        self.ui.document.configurable.text_wrap = is_reflow -- restore reflow
        -- draw
        self.view.highlight.temp[new_page] = self.ui.document:getPageBoxesFromPositions(new_page, new_pos0, new_pos1)
    else
        -- pos0 and pos1 are in order within highlights
        new_pos0 = self.ui.document:compareXPointers(item1.pos0, item2_pos0) == 1 and item1.pos0 or item2_pos0
        new_pos1 = self.ui.document:compareXPointers(item1.pos1, item2_pos1) == 1 and item2_pos1 or item1.pos1
        self.hold_pos.page = self.ui.document:getPageFromXPointer(new_pos0)
        -- true to draw
        new_text = self.ui.document:getTextFromXPointers(new_pos0, new_pos1, true)
    end
    self:deleteHighlight(self.highlight_page, self.highlight_idx) -- starting fragment
    self.selected_text = {
        text = new_text,
        pos0 = new_pos0,
        pos1 = new_pos1,
        pboxes = new_pboxes,
    }
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:onReadSettings(config)
    self.view.highlight.saved_drawer = config:readSetting("highlight_drawer")
        or G_reader_settings:readSetting("highlight_drawing_style") or self.view.highlight.saved_drawer
    self.view.highlight.disabled = G_reader_settings:has("default_highlight_action")
        and G_reader_settings:readSetting("default_highlight_action") == "nothing"

    -- panel zoom settings isn't supported in EPUB
    if self.document.info.has_pages then
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
    self.ui.doc_settings:saveSetting("panel_zoom_enabled", self.panel_zoom_enabled)
end

function ReaderHighlight:onClose()
    UIManager:close(self.highlight_dialog)
    self.highlight_dialog = nil
    -- clear highlighted text
    self:clear()
end

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
        -- single move distance, small and capable to move on word with small font size and narrow line height
        local move_distance = Size.item.height_default / 4
        local rect = self._current_indicator_pos:copy()
        if quick_move then
            rect.x = rect.x + quick_move_distance_dx * dx
            rect.y = rect.y + quick_move_distance_dy * dy
        else
            local now = time:now()
            if dx == self._last_indicator_move_args.dx and dy == self._last_indicator_move_args.dy then
                local diff = now - self._last_indicator_move_args.time
                -- if press same arrow key in 1 second, speed up
                -- double press: 4 single move distances, usually move to next word or line
                -- triple press: 16 single distances, usually skip several words or lines
                -- quadruple press: 54 single distances, almost move to screen edge
                if diff < time.s(1) then
                    move_distance = self._last_indicator_move_args.distance * 4
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
