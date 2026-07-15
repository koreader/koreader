local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local Screen = Device.screen
local N_ = _.ngettext
local T = ffiUtil.template

-- see https://www.lua.org/gems/sample.pdf for Lua Performance Tips
-- GC Optimisations
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_floor = math.floor

-- Minimal overlay that draws the crosshairs without touching the document
-- render layer. Captures the page as its background on first paint, then
-- restores only the previous indicator region before drawing the new one.
local IndicatorOverlay = InputContainer:extend{
    parent_ui = nil,
    handleEvent = true,
    indicator_rect = nil,
    _prev_rect     = nil,
    _saved_bb      = nil,
    covers_fullscreen = false,
}

local function getIndicatorSaveRect(rect, max_w, max_h)
    if not rect then return nil end
    local save_r = rect:copy()
    local bt2 = math_floor(Size.border.thick / 2)
    save_r.x = math_floor(save_r.x - bt2)
    save_r.y = math_floor(save_r.y - bt2)
    save_r.w = save_r.w + Size.border.thick * 2
    save_r.h = save_r.h + Size.border.thick * 2
    save_r = save_r:intersect(Geom:new{ x = 0, y = 0, w = max_w, h = max_h })
    if not save_r or save_r.w <= 0 or save_r.h <= 0 then
        return nil
    end
    return save_r
end

local function getIndicatorDirtyRect(old_rect, new_rect, max_w, max_h)
    local old_save = getIndicatorSaveRect(old_rect, max_w, max_h)
    local new_save = getIndicatorSaveRect(new_rect, max_w, max_h)
    if old_save and new_save then
        return Geom.boundingBox({ old_save, new_save })
    end
    return old_save or new_save
end

function IndicatorOverlay:freeSavedBB()
    if self._saved_bb then
        self._saved_bb:free()
        self._saved_bb = nil
    end
    self._prev_rect = nil
end

function IndicatorOverlay:handleEvent(event)
    if not event or not event.handler then return false end
    -- Only forward input events that would otherwise be swallowed by us, being
    -- the topmost layer. Broadcast events reach parent_ui directly via UIManager.
    local input_events = {
        onKeyPress = true,
        onKeyRepeat = true,
        onKeyRelease = true,
        onGesture = true,
        onPan = true, -- mouse wheel pan via sendEvent
    }
    if input_events[event.handler] and self.parent_ui then
        return self.parent_ui:handleEvent(event)
    end
    return false
end

function IndicatorOverlay:drawCrosshairs(bb, rect)
    if not rect then return end
    bb:invertRect(
        rect.x,
        math.floor(rect.y + rect.h / 2 - Size.border.thick / 2),
        rect.w,
        Size.border.thick
    )
    bb:invertRect(
        math.floor(rect.x + rect.w / 2 - Size.border.thick / 2),
        rect.y,
        Size.border.thick,
        rect.h
    )
end

function IndicatorOverlay:getSize()
    return self.dimen or Screen:getSize()
end

function IndicatorOverlay:paintTo(bb, x, y, is_dirty)
    -- If is_dirty is nil, the parent ReaderUI painted over us with new content.
    -- The background we saved is now invalid, so we clear it.
    if is_dirty == nil then
        self:freeSavedBB()
    end

    -- Restore previous unblemished page background
    if self._prev_rect and self._saved_bb then
        local r = self._prev_rect
        bb:blitFrom(self._saved_bb, r.x, r.y, 0, 0, r.w, r.h)
    end

    if self.indicator_rect then
        local r = self.indicator_rect
        local save_r = getIndicatorSaveRect(r, bb:getWidth(), bb:getHeight())
        if save_r and self.dimen then
            save_r = save_r:intersect(self.dimen)
        end
        if not save_r or save_r.w <= 0 or save_r.h <= 0 then
            self._prev_rect = nil
            return
        end

        -- Resize the saved Blitbuffer if necessary
        if not self._saved_bb or self._saved_bb:getWidth() < save_r.w or self._saved_bb:getHeight() < save_r.h then
            self:freeSavedBB()
            self._saved_bb = Blitbuffer.new(save_r.w, save_r.h, bb:getType())
        end

        -- Copy clean background from screen
        self._saved_bb:blitFrom(bb, 0, 0, save_r.x, save_r.y, save_r.w, save_r.h)

        -- Draw the crosshair natively overriding the background
        self:drawCrosshairs(bb, self.indicator_rect)
        self._prev_rect = save_r
    else
        self._prev_rect = nil
    end
end

local ReaderKeySelection = InputContainer:extend{}

function ReaderKeySelection:init()
    if Device:isTouchDevice() and not Device:hasDPad() then
        return
    end
    self:registerKeyEvents()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self._previous_indicator_word = nil
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self._previous_indicator_pos = nil
    self._vertical_move_anchor_x = nil
    self._last_move_was_vertical = false
    self._edge_dx = nil
    self._edge_dy = nil
    self._last_move_was_quick_move = nil
    self.mirroredUI = BD.mirroredUILayout()
    if self.ui.postInitCallback then
        -- Register as part of ReaderUI:init().
        self.ui:registerPostInitCallback(function()
            self.ui.menu:registerToMainMenu(self)
            self._registered_to_menu = true
        end)
    elseif not self._registered_to_menu then
        -- A keyboard was connected after init. Register to the menu directly.
        self.ui.menu:registerToMainMenu(self)
        self._registered_to_menu = true
    end
end

function ReaderKeySelection:onSetDimensions(dimen)
    self.screen_w, self.screen_h = dimen.w, dimen.h
    if self._indicator_overlay then
        local overlay_rect = getIndicatorSaveRect(self._current_indicator_pos, dimen.w, dimen.h)
        self._indicator_overlay.dimen = overlay_rect or Geom:new{ x = 0, y = 0, w = dimen.w, h = dimen.h }
        self._indicator_overlay:freeSavedBB()
    end
end

function ReaderKeySelection:registerKeyEvents()
    if Device:hasDPad() then
        self.key_events.StopHighlightIndicator  = { { Device.input.group.Back }, args = true } -- true: clear highlight selection
        local event = Device:useDPadAsActionKeys() and "StartOrMoveHighlightIndicator" or "MoveHighlightIndicator"
        self.key_events.UpHighlightIndicator    = { { "Up" },    event = event, args = {0, -1} }
        self.key_events.DownHighlightIndicator  = { { "Down" },  event = event, args = {0, 1} }
        -- let hasFewKeys device move the indicator left
        self.key_events.LeftHighlightIndicator  = { { "Left" },  event = "MoveHighlightIndicator", args = {-1, 0} }
        self.key_events.RightHighlightIndicator = { { "Right" }, event = "MoveHighlightIndicator", args = {1, 0} }
        self.key_events.HighlightPress          = { { "Press" } }
    end
    if Device:hasScreenKB() or Device:hasKeyboard() then
        local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
        -- Used for text selection with dpad/keys
        local QUICK_INDICATOR_MOVE = true
        self.key_events.QuickUpHighlightIndicator    = { { modifier, "Up" },    event = "MoveHighlightIndicator", args = {0, -1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickDownHighlightIndicator  = { { modifier, "Down" },  event = "MoveHighlightIndicator", args = {0, 1, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickLeftHighlightIndicator  = { { modifier, "Left" },  event = "MoveHighlightIndicator", args = {-1, 0, QUICK_INDICATOR_MOVE} }
        self.key_events.QuickRightHighlightIndicator = { { modifier, "Right" }, event = "MoveHighlightIndicator", args = {1, 0, QUICK_INDICATOR_MOVE} }
        self.key_events.HighlightModifierPress       = { { modifier, "Press" } }
        -- startHighlightIndicator (H) is handled by hotkeys.koplugin
    end
end
ReaderKeySelection.onPhysicalKeyboardConnected = ReaderKeySelection.init

function ReaderKeySelection:addToMainMenu(menu_items)
    if Device:isTouchDevice() or not Device:hasDPad() then return end
    -- insert table to main reader menu
    if not Device:useDPadAsActionKeys() then
        menu_items.start_content_selection = {
            text = _("Start text selection"),
            callback = function()
                self:onStartHighlightIndicator()
            end,
        }
    end
    -- we allow user to select the rate at which the content selection tool moves through screen
    table.insert(menu_items.long_press.sub_item_table, {
        text_func = function()
            local reader_speed = G_reader_settings:readSetting("highlight_non_touch_factor") or 4
            local dict_speed = G_reader_settings:readSetting("highlight_non_touch_factor_dict") or 3
            return T(_("Crosshairs speed (reader/dict): %1 / %2"), reader_speed, dict_speed)
        end,
        callback = function(touchmenu_instance)
            local reader_speed = G_reader_settings:readSetting("highlight_non_touch_factor") or 4
            local dict_speed = G_reader_settings:readSetting("highlight_non_touch_factor_dict") or 3
            local double_spin_widget = DoubleSpinWidget:new{
                left_text = _("Reader") .. " PDF/DjVu",
                left_value = reader_speed,
                left_min = 0.25,
                left_max = 5,
                left_default = 4,
                left_precision = "%.2f",
                left_step = 0.25,
                left_hold_step = 0.05,
                right_text = _("Dictionary"),
                right_value = dict_speed,
                right_min = 0.25,
                right_max = 5,
                right_default = 3,
                right_precision = "%.2f",
                right_step = 0.25,
                right_hold_step = 0.05,
                title_text = _("Crosshairs speed"),
                info_text = _("Select a decimal value from 0.25 to 5. A smaller value increases the travel distance of the crosshairs per keystroke. Font size and this value are inversely correlated, meaning a smaller font size requires a larger value and vice versa."),
                callback = function(left_value, right_value)
                    G_reader_settings:saveSetting("highlight_non_touch_factor", left_value)
                    G_reader_settings:saveSetting("highlight_non_touch_factor_dict", right_value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            }
            UIManager:show(double_spin_widget)
        end,
    })
    table.insert(menu_items.long_press.sub_item_table, {
        text = _("Increase crosshairs speed on consecutive keystrokes"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("highlight_non_touch_spedup")
        end,
        enabled_func = function()
            return not self.view.highlight.disabled and not self.ui.rolling
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("highlight_non_touch_spedup")
        end,
    })
    table.insert(menu_items.long_press.sub_item_table, {
        text_func = function()
            local highlight_non_touch_interval = G_reader_settings:readSetting("highlight_non_touch_interval") or 1
            return T(N_("Interval for crosshairs speed increase: 1 second", "Interval for crosshairs speed increase: %1 seconds", highlight_non_touch_interval), highlight_non_touch_interval)
        end,
        separator = true, -- needed as this is not the last item, readerlink adds another one
        enabled_func = function()
            return not self.ui.rolling and not self.view.highlight.disabled and G_reader_settings:nilOrTrue("highlight_non_touch_spedup")
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
                info_text = _("Select a decimal value up to 1 second. This defines the time period within which multiple keystrokes will trigger an increase in the crosshairs speed."),
                callback = function(spin)
                    G_reader_settings:saveSetting("highlight_non_touch_interval", spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            }
            UIManager:show(spin_widget)
        end,
    })

    if menu_items.long_press then
        local long_press_action = ReaderHighlight.long_press_action
        -- long_press settings are under the taps_and_gestures menu, which is not available for non-touch devices
        -- Clone long_press settings, and change its label, making it much more meaningful for non-touch device users.
        menu_items.selection_text = {
            text = _("Text selection tools"),
            sub_item_table = {
                menu_items.long_press.sub_item_table[1], -- Dictionary on single word selection
                {
                    text_func = function()
                        local multi_word = G_reader_settings:readSetting("default_highlight_action")
                        for __, v in ipairs(long_press_action) do
                            if v[2] == multi_word then
                                return T(_("Multi-word selection: %1"), v[1]:lower())
                            end
                        end
                    end,
                    sub_item_table = { table.unpack(menu_items.long_press.sub_item_table, 2, #long_press_action + 1) }
                }
            }
        }
        local post_long_press_action_index = #menu_items.selection_text.sub_item_table + #long_press_action -- index after long_press_action
        -- Copy remaining items (anything after long_press_action) directly to selection_text's sub_item_table
        for i = post_long_press_action_index, #menu_items.long_press.sub_item_table do
            table.insert(menu_items.selection_text.sub_item_table, menu_items.long_press.sub_item_table[i])
        end
        menu_items.long_press = nil
    end
end

-- for dispatcher and hotkeys
function ReaderKeySelection:onStartHighlightIndicator()
    return self:startHighlightIndicator()
end

function ReaderKeySelection:onStopHighlightIndicator(need_clear_selection)
    return self:stopHighlightIndicator(need_clear_selection)
end

function ReaderKeySelection:onHighlightPress(skip_tap_check)
    return self:highlightPress(skip_tap_check)
end

function ReaderKeySelection:onHighlightModifierPress()
    return self:highlightModifierPress()
end

function ReaderKeySelection:onMoveHighlightIndicator(args)
    return self:moveHighlightIndicator(args)
end

function ReaderKeySelection:onStartOrMoveHighlightIndicator(args)
    if not self._current_indicator_pos then
        self:startHighlightIndicator()
    else
        self:moveHighlightIndicator(args)
    end
    return true
end

function ReaderKeySelection:isActive()
    return self._current_indicator_pos ~= nil
end

function ReaderKeySelection:clearOverlay()
    if not self._indicator_overlay then return end
    self._indicator_overlay:freeSavedBB()
end

function ReaderKeySelection:clearFlashHighlight()
    if not self._flashing_nearest_word then return end
    self.ui.highlight:clear()
    self:clearOverlay()
    self._flashing_nearest_word = nil
end

function ReaderKeySelection:startHighlightIndicator()
    -- disable long-press icon (poke-ball), as it is triggered constantly due to NT devices needing a workaround for text selection to work.
    self.ui.highlight.long_hold_reached_action = function() end
    if self.view.visible_area and not self._current_indicator_pos then
        local rect = self._previous_indicator_pos
        -- set start position to centre of page
        if not rect then
            rect = Geom:new()
            rect.x = self.view.visible_area.w * 0.5
            rect.y = self.view.visible_area.h * 0.5
            rect.w = Size.item.height_default
            rect.h = rect.w
        end
        self._current_indicator_pos = rect

        -- Compute padded saved region (match paintTo padding)
        local max_w = self.screen_w or Screen:getWidth()
        local max_h = self.screen_h or Screen:getHeight()
        local save_r = getIndicatorSaveRect(rect, max_w, max_h)
        -- Fallback to minimal rect if intersection collapsed
        if not save_r then
            save_r = Geom:new{ x = math.floor(rect.x), y = math.floor(rect.y), w = rect.w, h = rect.h }
        end
        self._indicator_overlay = IndicatorOverlay:new{
            dimen = Geom:new{ x = save_r.x, y = save_r.y, w = save_r.w, h = save_r.h },
            parent_ui = self.ui,
        }
        UIManager:show(self._indicator_overlay)
        if self.ui.paging then
            self._last_indicator_move_args = {dx = 0, dy = 0, distance = 0, time = time:now()}
            self._indicator_overlay.indicator_rect = rect
            UIManager:setDirty(self._indicator_overlay, "ui", rect)
            return true
        end
        local center_x = rect.x + rect.w * 0.5
        local center_y = rect.y + rect.h * 0.5
        self.invert_ui_layout = self.view:shouldInvertBiDiLayoutMirroring()
        local nearest_word = self:_getNearestWordFromScreenPoint(center_x, center_y)
        if nearest_word then
            self:_setIndicatorToWord(nearest_word)
            -- Flash nearest_word in case the crosshairs if hard to find.
            local coor = nearest_word.sbox
            if self.ui.highlight:highlightWordAtCoordinates(coor.x + coor.w * 0.5, coor.y + coor.h * 0.5) then
                self._flashing_nearest_word = true
                UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
                    self:clearFlashHighlight()
                end)
            end
        else
            self:stopHighlightIndicator()
        end
        return true
    end
    return false
end

function ReaderKeySelection:stopHighlightIndicator(need_clear_selection)
    if not self._current_indicator_pos then return false end
    -- If we're in select mode and user presses back, end the selection
    if self.ui.highlight.select_mode and self.ui.highlight.highlight_idx then
        self.ui.highlight.select_mode = false
        if self.ui.annotation.annotations[self.ui.highlight.highlight_idx].is_tmp then
            self.ui.highlight:deleteHighlight(self.ui.highlight.highlight_idx) -- temporary highlight, delete it
        else
            UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
        end
        self.ui.highlight.highlight_idx = nil
    end
    local rect = self._current_indicator_pos
    self._previous_indicator_pos = rect
    self._vertical_move_anchor_x = nil
    self._last_move_was_vertical = false
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self.view.highlight.indicator = nil
    self._edge_dx, self._edge_dy = nil, nil
    self._last_move_was_quick_move = nil
    self._previous_indicator_word = nil
    if self._indicator_overlay then
        self._indicator_overlay:freeSavedBB()
        UIManager:close(self._indicator_overlay)
        self._indicator_overlay = nil
    end
    self._last_indicator_move_args = nil
    UIManager:setDirty(self.dialog, "ui", rect)
    if need_clear_selection then
        self.ui.highlight:clear()
    end
    return true
end

function ReaderKeySelection:highlightPress(skip_tap_check)
    if not self._current_indicator_pos then return false end
    self:clearFlashHighlight() -- delay may not have cleared it yet
    if self._start_indicator_highlight then
        self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
        self:stopHighlightIndicator()
        return true
    end
    -- Check if we're in select mode (or extending an existing highlight)
    if self.ui.highlight.select_mode and self.ui.highlight.highlight_idx then
        self.ui.highlight:onHold(nil, self:_createHighlightGesture("hold"))
        self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
        self:stopHighlightIndicator()
        return true
    end
    if not skip_tap_check then
        -- Follow link if there's one at the current indicator position
        if self.ui.link and self.ui.link:onTap(nil, self:_createHighlightGesture("tap")) then
            self:stopHighlightIndicator()
            return true
        end
        -- Attempt to open an existing highlight
        if self.ui.highlight:onTap(nil, self:_createHighlightGesture("tap")) then
            self:stopHighlightIndicator(true) -- need_clear_selection=true
            return true
        end
    end
    -- no existing highlight at current indicator position: start hold
    self._start_indicator_highlight = true
    self.ui.highlight:onHold(nil, self:_createHighlightGesture("hold"))
    return true
end

function ReaderKeySelection:highlightModifierPress()
    if not self._current_indicator_pos then return false end -- let event propagate to hotkeys
    self:clearFlashHighlight() -- delay may not have cleared it yet
    if not self._start_indicator_highlight then
        self:highlightPress(true)
        return true -- don't trigger hotkeys during text selection
    end
    -- Simulate very long-long press by setting the long hold flag. This will trigger the long-press dialog.
    self.ui.highlight.long_hold_reached = true
    self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
    self:stopHighlightIndicator()
    return true
end

function ReaderKeySelection:moveHighlightIndicator(args)
    if not (self.view.visible_area and self._current_indicator_pos) then return false end
    self:clearFlashHighlight() -- delay may not have cleared it yet
    local dx, dy, quick_move = unpack(args)
    if dx == self._edge_dx and dy == self._edge_dy and self._last_move_was_quick_move == quick_move then
        -- don't waste resources trying to move in a direction that we know is blocked
        -- Note: the self._last_move_was_quick_move == quick_move is important because we don't
        --       want a quick_move (which does not wrap around) to block a legitimate wrap around.
        logger.dbg("ReaderKeySelection: Previous boundary hit in this direction, skipping move attempt.")
        return true
    end
    local moved = false

    -- PDF/DjVu uses the old free form text selector mode.
    if self.ui.paging then
        moved = self:_moveIndicatorFreeFormPaging(dx, dy, quick_move)
        if moved and self._start_indicator_highlight then
            self.ui.highlight:onHoldPan(nil, self:_createHighlightGesture("hold_pan"))
        end
        return true
    end

    local is_vertical_move = dx == 0 and dy ~= 0
    self._last_move_was_quick_move = quick_move
    local current_word = self._previous_indicator_word
    logger.dbg("ReaderKeySelection: Current cached word:", current_word and current_word.word or "nil", "| dx:", dx, "| dy:", dy, "| quick_move:", quick_move)
    if not current_word then
        current_word = self:_getCurrentIndicatorWord(dx, dy)
    end

    if is_vertical_move then
        if not self._last_move_was_vertical or not self._vertical_move_anchor_x then
            -- remember x coordinate so subsequent vertical moves can try to stay in the same horizontal "band"
            self._vertical_move_anchor_x = self._current_indicator_pos.x + self._current_indicator_pos.w * 0.5
        end
        if current_word and current_word.pos0 then
            if quick_move then
                local _, current_anchor_y = self:_getWordAnchorCoordinates(current_word)
                local target_y = current_anchor_y + (self.view.visible_area.h * (1/5) * dy)
                if target_y < 0 then
                    target_y = 0
                elseif target_y > self.view.visible_area.h then
                    target_y = self.view.visible_area.h
                end
                local nearest_vertical_word = self:_getQuickVerticalWordRolling(
                    self._vertical_move_anchor_x,
                    target_y,
                    dy,
                    current_word,
                    current_anchor_y
                )
                if nearest_vertical_word then
                    moved = self:_setIndicatorToWord(nearest_vertical_word)
                else -- Keep moving in the requested direction if no target-band word was found.
                    moved = self:_moveIndicatorCreDoc(current_word, 0, dy, 1, false, self._vertical_move_anchor_x)
                end
                if moved and self._edge_dx and self._edge_dy then
                    self._edge_dx, self._edge_dy = nil, nil
                end
            else -- Always move line-by-line vertically in rolling mode.
                moved = self:_moveIndicatorCreDoc(current_word, 0, dy, 1, false, self._vertical_move_anchor_x)
            end
        end -- if current_word
        self._last_move_was_vertical = true
    else
        self._vertical_move_anchor_x = nil
        self._last_move_was_vertical = false
        if current_word and current_word.pos0 then
            local steps = quick_move and 4 or 1
            local no_wrap_horizontal = quick_move and dx ~= 0
            moved = self:_moveIndicatorCreDoc(current_word, dx, dy, steps, no_wrap_horizontal)
        end
    end

    if moved and self._start_indicator_highlight then
        self.ui.highlight:onHoldPan(nil, self:_createHighlightGesture("hold_pan"))
    end
    return true
end

function ReaderKeySelection:pageTurnDuringSelection()
    self:clearFlashHighlight() -- delay may not have cleared it yet
    self._edge_dx, self._edge_dy = nil, nil
    self._previous_indicator_word = nil
    local last_pos = self._current_indicator_pos
    if self._indicator_overlay then
        local old_dirty = getIndicatorSaveRect(last_pos, self.screen_w, self.screen_h)
        self._indicator_overlay:freeSavedBB()
        self._indicator_overlay.indicator_rect = nil
        if old_dirty then
            UIManager:setDirty(self.dialog, "ui", old_dirty)
        end
    end
    local target_x = last_pos.x + last_pos.w * 0.5
    local target_y = last_pos.y + last_pos.h * 0.5

    local new_word = self:_getNearestWordFromScreenPoint(target_x, target_y)
    if new_word then
        self:_setIndicatorToWord(new_word)
        if not self.ui.highlight.select_mode and self._start_indicator_highlight then
            self.ui.highlight:startSelection()
            -- we don't want to HoldPan during moveHighlightIndicator, a following Press
            -- key should close the startSelection loop though.
            self._start_indicator_highlight = nil -- breaks the `if moved and self._ then`
        end
    else
        self:stopHighlightIndicator(true)
    end
end

function ReaderKeySelection:_isSingleWord(word)
    if not word or not word.word then return false end
    local trimmed_word = word.word:match("^%s*(.-)%s*$") or word.word
    if trimmed_word:match("%s") then
        return false
    end
    return true
end

function ReaderKeySelection:_isSplitHyphenatedWord(word)
    if not word or not word.pos0 or not word.pos1 then return false end
    -- A single hyphenated word does not contain spaces in the middle.
    if not self:_isSingleWord(word) then
        return false
    end
    -- Avoid pulling crengine layout data twice if we've already cached it for this word
    if word.segments then
        return #word.segments > 1 and word.segments[1].y ~= word.segments[#word.segments].y
    end
    local segments = self.ui.document:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
    if not segments or #segments == 0 then return false end
    -- Cache the segments directly onto the word object for downstream geometry targeting
    word.segments = segments
    -- A word is deterministically split across a line break if it returns multiple
    -- fragment boxes that exist on completely different vertical coordinates.
    local is_split = #segments > 1 and segments[1].y ~= segments[#segments].y
    if is_split then
        logger.dbg("ReaderKeySelection: Deterministic split word detected:", word.word)
    end
    return is_split
end

-- X-based head/tail logic that manages RTL layout translation
function ReaderKeySelection:_resolveSplitWordFromX(word, x_pos)
    if not self:_isSplitHyphenatedWord(word) then
        return word, word.sbox.y
    end
    local head_box = word.segments[1]
    local tail_box = word.segments[#word.segments]

    local right_half = x_pos > (word.sbox.x + word.sbox.w * 0.5)
    -- LTR: Right side is the end of line 1 (head). RTL: Right side is the start of line 2 (tail).
    local is_head
    if self.mirroredUI then
        is_head = not right_half
    else
        is_head = right_half
    end
    if self.invert_ui_layout then
        is_head = not is_head
    end
    if is_head then
        word.is_split_fragment = "head"
        return word, head_box.y
    else
        word.is_split_fragment = "tail"
        return word, tail_box.y
    end
end

function ReaderKeySelection:_moveIndicatorCreDoc(current_word, dx, dy, steps, no_wrap_horizontal, preferred_center_x)
    local target_word = current_word
    local did_move = false
    local lock_line_center_y
    local lock_line_tolerance

    if no_wrap_horizontal and dx ~= 0 then
        local _, cy = self:_getWordAnchorCoordinates(current_word)
        lock_line_center_y = self._current_indicator_pos and (self._current_indicator_pos.y + self._current_indicator_pos.h * 0.5) or cy

        local line_h = Size.item.height_default
        if current_word.sbox and not self:_isSplitHyphenatedWord(current_word) then
            line_h = current_word.sbox.h
        end
        lock_line_tolerance = math_max(1, line_h * 0.5)
    end

    for _ = 1, steps do
        local step_word
        if dx ~= 0 then
            local drop_off_head = dx > 0
            local drop_off_tail = dx < 0
            if self.mirroredUI then
                drop_off_head, drop_off_tail = drop_off_tail, drop_off_head
            end
            -- Pre-emptive wrap guard: If we are on a split fragment edge and no_wrap is true,
            -- stepping "off" the edge is a guaranteed line wrap.
            if no_wrap_horizontal and target_word.is_split_fragment then
                if (drop_off_head and target_word.is_split_fragment == "head") or
                   (drop_off_tail and target_word.is_split_fragment == "tail") then
                    logger.dbg("ReaderKeySelection: Semantic wrap prevented on split word edge.")
                    break -- Terminate wrap before mutating state
                end
            end

            step_word = self:_getAdjacentWordRolling(target_word, dx, lock_line_center_y, lock_line_tolerance)
            -- The engine's logical traversal will happily wrap to the next physical line at the margins.
            -- Because _getAdjacentWordRolling relies on these logical XPointer jumps, we must enforce
            -- a strict physical boundary check after the word is found.
            -- If the Y-coordinate of the new word drifts vertically outside our locked horizontal band,
            -- it means a line wrap occurred. If horizontal wrapping is forbidden, we abort the move.
            if step_word and no_wrap_horizontal and step_word ~= target_word then
                local _, next_cy = self:_getWordAnchorCoordinates(step_word)
                if math_abs(next_cy - lock_line_center_y) > lock_line_tolerance then
                    break
                end
            end
        else
            step_word = self:_getAdjacentLineWordRolling(target_word, dy, preferred_center_x)
        end

        if not step_word then
            -- Set the edge cache: We've hit a physical or logical wall.
            self._edge_dx, self._edge_dy = dx, dy
            break
        end
        self._edge_dx, self._edge_dy = nil, nil
        target_word = step_word
        did_move = true
    end

    if did_move then
        self:_setIndicatorToWord(target_word)
    end
    return did_move
end

function ReaderKeySelection:_setIndicatorToWord(word)
    if not word or not word.sbox then return false end
    local rect = self._current_indicator_pos:copy()
    local anchor_x, anchor_y, is_split = self:_getWordAnchorCoordinates(word)
    rect.x = is_split and anchor_x or (anchor_x - rect.w * 0.5)
    rect.y = anchor_y - rect.h * 0.5
    self:_setIndicatorRect(rect)
    self._previous_indicator_word = word
    return true
end

function ReaderKeySelection:_setIndicatorRect(rect)
    local old_rect = self._current_indicator_pos
    self._current_indicator_pos = rect
    if not self._indicator_overlay then
        logger.warn("ReaderKeySelection: _setIndicatorRect: no overlay")
        return
    end
    logger.dbg("ReaderKeySelection: _setIndicatorRect: dirtying overlay, rect=", rect)
    self._indicator_overlay.indicator_rect = rect
    local dirty = getIndicatorDirtyRect(old_rect, rect, self.screen_w, self.screen_h)
    if dirty then
        self._indicator_overlay.dimen = dirty
        UIManager:setDirty(self._indicator_overlay, "fast", dirty)
    else
        UIManager:setDirty(self._indicator_overlay, "fast", rect)
    end
end

function ReaderKeySelection:_getWordAnchorCoordinates(word)
    if not word or not word.sbox then
        return nil, nil, false
    end
    local sbox = word.sbox
    -- Fallback for when the word hasn't been flagged yet
    if not word.is_split_fragment and self:_isSplitHyphenatedWord(word) then
        -- Infer fragment from the indicator position.
        if self._current_indicator_pos and word.segments and #word.segments > 1 then
            local indicator_cy = self._current_indicator_pos.y + self._current_indicator_pos.h * 0.5
            local head_box = word.segments[1]
            local tail_box = word.segments[#word.segments]
            local midpoint_y = (head_box.y + tail_box.y + tail_box.h) * 0.5
            if indicator_cy <= midpoint_y then
                word.is_split_fragment = "head"
            else
                word.is_split_fragment = "tail"
            end
        end
    end
    if word.is_split_fragment then
        local head_is_left = self.mirroredUI
        if self.invert_ui_layout then
            head_is_left = not head_is_left
        end
        -- Grab the width of the crosshairs so we can tuck it inside the bounding box
        local ind_w = self._current_indicator_pos and self._current_indicator_pos.w or 0
        if word.is_split_fragment == "head" and word.segments then
            -- Target the physical box of the head fragment
            local head_box = word.segments[1]
            local x = head_is_left and head_box.x or (head_box.x + head_box.w - ind_w)
            local y = head_box.y + head_box.h * 0.5
            return x, y, true
        elseif word.is_split_fragment == "tail" and word.segments then
            -- Target the physical box of the tail fragment
            local tail_box = word.segments[#word.segments]
            local x = head_is_left and (tail_box.x + tail_box.w - ind_w) or tail_box.x
            local y = tail_box.y + tail_box.h * 0.5
            return x, y, true
        end
    end
    return sbox.x + sbox.w * 0.5, sbox.y + sbox.h * 0.5, false
end

function ReaderKeySelection:_getWordFromScreenPoint(screen_x, screen_y, dx, dy)
    local probe = {}
    if screen_x >= 0 and screen_x <= self.view.visible_area.w and screen_y >= 0 and screen_y <= self.view.visible_area.h then
        probe.x = screen_x
        probe.y = screen_y
        local pos = self.view:screenToPageTransform(probe)
        local word = self.ui.document:getWordFromPosition(pos, true)
        if word and word.sbox then
            return word
        end
    end
    if (dx == nil or dx == 0) and (dy == nil or dy == 0) then return nil end

    local step = math_max(4, math_floor(Size.item.height_default * 0.5))
    local max_distance = math_max(self.view.visible_area.w, self.view.visible_area.h)

    for dist = step, max_distance, step do
        local px = screen_x + dx * dist
        local py = screen_y + dy * dist
        if px >= 0 and px <= self.view.visible_area.w and py >= 0 and py <= self.view.visible_area.h then
            probe.x = px
            probe.y = py
            local pos = self.view:screenToPageTransform(probe)
            local word = self.ui.document:getWordFromPosition(pos, true)
            if word and word.sbox then return word end
        end
    end
end

function ReaderKeySelection:_getNearestWordFromScreenPoint(screen_x, screen_y)
    local probe = { x = screen_x, y = screen_y }
    local pos = self.view:screenToPageTransform(probe)
    local doc = self.ui.document

    local origin_word = doc:getWordFromPosition(pos, true)
    if origin_word and origin_word.sbox then
        logger.dbg("ReaderKeySelection: Exact word found at position:", origin_word.word)
        if self:_isSingleWord(origin_word) then
            return origin_word
        end
    end
    -- No exact word found, perform a ripple search for the nearest word
    local nearest_word = doc:getNearestWordAndBoxFromPosition(pos, 0) -- 0 means DIR_ANY, search the entire page
    if nearest_word and nearest_word.sbox then
        logger.dbg("ReaderKeySelection: No word at exact position. Nearest word is:", nearest_word.word)
        return nearest_word
    end
    logger.dbg("ReaderKeySelection: No word found in current page.")
    return nil
end

function ReaderKeySelection:_getCurrentIndicatorWord(dx, dy)
    local center_x = self._current_indicator_pos.x + self._current_indicator_pos.w * 0.5
    local center_y = self._current_indicator_pos.y + self._current_indicator_pos.h * 0.5
    local word = self:_getWordFromScreenPoint(center_x, center_y, dx, dy)

    -- State Recovery: Re-stamp the mega-box based on the indicator's physical position
    if word and word.sbox and not word.is_split_fragment then
        if self:_isSplitHyphenatedWord(word) then
            local midpoint_y = word.sbox.y + (word.sbox.h * 0.5)
            -- Y-coordinates are absolute, universally bypassing RTL rules
            if center_y < midpoint_y then
                word.is_split_fragment = "head"
                logger.dbg("ReaderKeySelection: State recovered -> Head")
            else
                word.is_split_fragment = "tail"
                logger.dbg("ReaderKeySelection: State recovered -> Tail")
            end
        end
    end
    self._previous_indicator_word = word
    return word
end

function ReaderKeySelection:_getQuickVerticalWordRolling(anchor_x, target_y, dy, exclude_word, current_anchor_y)
    local doc = self.ui.document
    -- Prevent wrapping off the current page.
    local safe_y = math_max(self.view.visible_area.y, math_min(target_y, self.view.visible_area.y + self.view.visible_area.h))

    local probe = { x = anchor_x, y = safe_y }
    -- let Crengine's native fuzzy search do the work
    local candidate = doc:getWordFromPosition(probe, true)

    if not candidate or not candidate.sbox then
        logger.dbg("ReaderKeySelection: Quick move failed - no word found at target.")
        return nil
    end

    if exclude_word and exclude_word.pos0 and candidate.pos0 == exclude_word.pos0 then
        logger.dbg("ReaderKeySelection: Quick move rejected - hit origin word.")
        return nil
    end

    local candidate_sy
    candidate, candidate_sy = self:_resolveSplitWordFromX(candidate, anchor_x)

    local line_tol = (exclude_word and exclude_word.sbox) and math_max(1, exclude_word.sbox.h * 0.5) or math_max(1, Size.item.height_default * 0.5)
    if current_anchor_y then
        if math_abs(candidate_sy - current_anchor_y) <= line_tol then
            logger.dbg("ReaderKeySelection: Quick move rejected - did not clear current line.")
            return nil
        end
        if dy < 0 and candidate_sy >= current_anchor_y - line_tol then return nil end
        if dy > 0 and candidate_sy <= current_anchor_y + line_tol then return nil end
    end

    logger.dbg("ReaderKeySelection: Quick vertical jump success to:", candidate.word)
    return candidate
end

function ReaderKeySelection:_getAdjacentWordRolling(word, direction, lock_line_center_y, lock_line_tolerance)
    if not word or not word.pos0 then return nil end
    local is_forward_physical = (not self.mirroredUI and direction > 0) or (self.mirroredUI and direction < 0)
    if self.invert_ui_layout then
        is_forward_physical = not is_forward_physical
        direction = -direction
    end
    -- If we're on one half of a split word, the next 'line' is just the other half.
    if self:_isSplitHyphenatedWord(word) then
        if is_forward_physical and word.is_split_fragment == "head" then
            logger.dbg("ReaderKeySelection: Internal jump Forward -> Tail")
            word.is_split_fragment = "tail"
            return word
        elseif not is_forward_physical and word.is_split_fragment == "tail" then
            logger.dbg("ReaderKeySelection: Internal jump Backward -> Head")
            word.is_split_fragment = "head"
            return word
        end
    end
    local doc = self.ui.document
    -- Map physical direction to logical XPointer direction
    local logical_dir = self.mirroredUI and -direction or direction

    -- Advance strictly via logical XPointer to perfectly step over BiDi traps
    local next_xp = logical_dir > 0 and doc:getNextVisibleWordStart(word.pos0) or doc:getPrevVisibleWordStart(word.pos0)
    if not next_xp or next_xp == word.pos0 then
        logger.dbg("ReaderKeySelection: Reached logical end of stream.")
        return nil
    end
    -- For hyphenated words straddled across different pages, tails are not detected so we need to physically
    -- probe for them, otherwise indicator will hit a boundary before the fragment.
    if not doc:isXPointerInCurrentPage(next_xp) then
        logger.dbg("ReaderKeySelection: Logical boundary hit. Attempting physical horizontal probe.")
        local head_is_left = self.mirroredUI
        if self.invert_ui_layout then
            head_is_left = not head_is_left
        end
        local probe = {}
        if head_is_left then
            probe.x = is_forward_physical and (word.sbox.x - 10) or (word.sbox.x + word.sbox.w + 10)
        else
            probe.x = is_forward_physical and (word.sbox.x + word.sbox.w + 10) or (word.sbox.x - 10)
        end
        probe.y = lock_line_center_y or (word.sbox.y + word.sbox.h * 0.5)
        local probe_word = self:_getWordFromScreenPoint(probe.x, probe.y, direction, 0)

        if probe_word and probe_word.sbox and probe_word.pos0 ~= word.pos0 then
            -- Directional Entry state stamping
            if not probe_word.is_split_fragment and self:_isSplitHyphenatedWord(probe_word) then
                probe_word.is_split_fragment = is_forward_physical and "head" or "tail"
            end
            logger.dbg("ReaderKeySelection: Physical probe rescued word:", probe_word.word)
            return probe_word
        end
        return nil
    end

    -- Recover the word's end pointer logically
    local end_xp = doc:getNextVisibleWordEnd(next_xp)
    if not end_xp then return nil end
    -- Reconstruct the full word indicator object natively
    local word_boxes = doc:getScreenBoxesFromPositions(next_xp, end_xp, true)
    if not word_boxes or #word_boxes == 0 then return nil end
    local candidate = {
        word = doc:getTextFromXPointers(next_xp, end_xp),
        pos0 = next_xp,
        pos1 = end_xp,
        sbox = Geom.boundingBox(word_boxes),
        segments = word_boxes,
    }
    -- Directional Entry: Stamp the initial state on newly discovered split words
    if not candidate.is_split_fragment and self:_isSplitHyphenatedWord(candidate) then
        if is_forward_physical then
            logger.dbg("ReaderKeySelection: External entry Forward -> Head")
            candidate.is_split_fragment = "head"
        else
            logger.dbg("ReaderKeySelection: External entry Backward -> Tail")
            candidate.is_split_fragment = "tail"
        end
    end
    -- Enforce the physical bounds logic for rolling within a locked line if provided
    if lock_line_center_y and lock_line_tolerance then
        local candidate_center_y = candidate.sbox.y + candidate.sbox.h * 0.5
        if math_abs(candidate_center_y - lock_line_center_y) > lock_line_tolerance then
            return nil
        end
    end

    return candidate
end

function ReaderKeySelection:_getAdjacentLineWordRolling(word, direction, preferred_center_x)
    if not (word and word.pos0 and word.sbox) then return end

    local doc = self.ui.document
    local target_x = preferred_center_x or (word.sbox.x + word.sbox.w * 0.5)

    -- Align to the physical top of the line to prevent offset drift
    local start_sy
    if word.is_split_fragment == "head" and word.segments then
        start_sy = word.segments[1].y
    elseif word.is_split_fragment == "tail" and word.segments then
        start_sy = word.segments[#word.segments].y
    else
        -- Page Boundary Fallback
        local valid_xp = doc:isXPointerInCurrentPage(word.pos0) and word.pos0 or word.pos1
        start_sy = doc:getScreenPositionFromXPointer(valid_xp) or word.sbox.y
    end

    local logical_h = Size.item.height_default
    local line_tol = logical_h * 0.3

    logger.dbg("ReaderKeySelection: Start ultra-lean search. AnchorY:", start_sy, "| TargetX:", target_x, "| Dir:", direction)

    local current_xp = word.pos0
    local target_line_y, fallback_sx, fallback_sy = nil, nil, nil

    -- Phase 1: Fast logical skip (Burn through the current line and break immediately)
    for _ = 1, 80 do
        local next_xp = direction > 0 and doc:getNextVisibleWordStart(current_xp) or doc:getPrevVisibleWordStart(current_xp)
        if not next_xp or next_xp == current_xp then
            logger.dbg("ReaderKeySelection: Break - end of stream.")
            break
        end
        current_xp = next_xp

        if not doc:isXPointerInCurrentPage(next_xp) then
            logger.dbg("ReaderKeySelection: Break - hit page boundary.")
            break
        end

        local sy, sx = doc:getScreenPositionFromXPointer(next_xp)
        if not sy or not sx then break end

        local is_new_line = (direction > 0 and sy > start_sy + line_tol) or (direction < 0 and sy < start_sy - line_tol)
        if is_new_line then
            target_line_y, fallback_sx, fallback_sy = sy, sx, sy
            logger.dbg("ReaderKeySelection: Target line hit at Y:", sy, "- Breaking loop.")
            break -- The magic bullet: Stop scanning. We have our Y-coordinate.
        end
    end

    -- Phase 2: Physical Probe (The single heavy lift)
    local probe = {}
    probe.x = target_x
    probe.y = target_line_y or (start_sy + (direction * logical_h))
    local probe_word = doc:getWordFromPosition(probe, true)

    local best_word = nil
    if probe_word and probe_word.sbox and probe_word.pos0 ~= word.pos0 then
        local evaluate_y
        -- Determine fragment state and adjust physical Y before clamping
        probe_word, evaluate_y = self:_resolveSplitWordFromX(probe_word, target_x)
        -- Strict Y-Clamp to prevent <br/> boxes or fuzzy search drift
        if not (evaluate_y and target_line_y and math_abs(evaluate_y - target_line_y) > line_tol) then
            best_word = probe_word
        else
            logger.dbg("ReaderKeySelection: Physical probe rejected - out of bounds:", evaluate_y)
        end
    end

    -- Phase 3: Fallback (If the line is short and the physical probe grabbed empty space)
    if not best_word and fallback_sx and fallback_sy then
        logger.dbg("ReaderKeySelection: Probe failed. Falling back to logical edge word.")
        probe.x = fallback_sx
        probe.y = fallback_sy
        best_word = doc:getWordFromPosition(probe, true)
    end

    if best_word then
        logger.dbg("ReaderKeySelection: Success. Best word:", best_word.word)
    else
        logger.dbg("ReaderKeySelection: Failed to find valid adjacent word.")
    end

    return best_word
end

function ReaderKeySelection:_moveIndicatorFreeFormPaging(dx, dy, quick_move)
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
    local moved = rect.x ~= self._current_indicator_pos.x or rect.y ~= self._current_indicator_pos.y
    self:_setIndicatorRect(rect)
    return moved
end

function ReaderKeySelection:_createHighlightGesture(gesture)
    local point = self._current_indicator_pos:copy()
    point.x = point.x + point.w * 0.5
    point.y = point.y + point.h * 0.5
    point.w = 0
    point.h = 0
    return {
        ges = gesture,
        pos = point,
        time = time.realtime(),
    }
end

return ReaderKeySelection
