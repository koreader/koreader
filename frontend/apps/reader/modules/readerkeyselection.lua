local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Size = require("ui/size")
local time = require("ui/time")
local Screen = Device.screen

local ReaderKeySelection = InputContainer:extend{}

function ReaderKeySelection:init()
    if Device:isTouchDevice() and not Device:hasDPad() then
        return
    end
    self:registerKeyEvents()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self._previous_indicator_pos = nil
    self._last_indicator_move_args = {dx = 0, dy = 0, distance = 0, time = time:now()}
end

function ReaderKeySelection:onSetDimensions(dimen)
    self.screen_w, self.screen_h = dimen.w, dimen.h
end

function ReaderKeySelection:registerKeyEvents()
    if Device:hasDPad() then
        self.key_events.StopHighlightIndicator  = { { Device.input.group.Back }, args = true } -- true: clear highlight selection
        self.key_events.UpHighlightIndicator    = { { "Up" },    event = "MoveHighlightIndicator", args = {0, -1} }
        self.key_events.DownHighlightIndicator  = { { "Down" },  event = "MoveHighlightIndicator", args = {0, 1} }
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
        -- onStartHighlightIndicator (H) is handled by hotkeys.koplugin
    end
end
ReaderKeySelection.onPhysicalKeyboardConnected = ReaderKeySelection.registerKeyEvents

function ReaderKeySelection:onHighlightPress(skip_tap_check)
    if not self._current_indicator_pos then return false end
    if self._start_indicator_highlight then
        self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
        self:onStopHighlightIndicator()
        return true
    end
    -- Check if we're in select mode (or extending an existing highlight)
    if self.ui.highlight.select_mode and self.ui.highlight.highlight_idx then
        self.ui.highlight:onHold(nil, self:_createHighlightGesture("hold"))
        self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
        self:onStopHighlightIndicator()
        return true
    end
    -- Attempt to open an existing highlight
    if not skip_tap_check and self.ui.highlight:onTap(nil, self:_createHighlightGesture("tap")) then
        self:onStopHighlightIndicator(true) -- need_clear_selection=true
        return true
    end
    -- no existing highlight at current indicator position: start hold
    self._start_indicator_highlight = true
    self.ui.highlight:onHold(nil, self:_createHighlightGesture("hold"))

    if not (self.ui.rolling and self.ui.highlight.selected_text and self.ui.highlight.selected_text.sboxes and #self.ui.highlight.selected_text.sboxes > 0) then
        return true
    end
    -- With crengine, selected_text.sboxes have good coordinates, so we'll borrow them.
    local pos = self.ui.highlight.selected_text.sboxes[1]
    local margins = self.ui.document.configurable.h_page_margins[1] + self.ui.document.configurable.h_page_margins[2]
    local two_column_mode = self.ui.document.configurable.visible_pages == 2
    local effective_width = two_column_mode and (self.screen_w - margins) / 2 or self.screen_w - margins
    -- When words are split (and hyphenated) due to line breaks, they create selection boxes that are almost as wide as the
    -- effective_width, so we need to check if that is the case, in order to handle those cases properly. We cannot precisely
    -- and easily recognise hyphenated words in the front end, so a heuristic approach is used, it goes in two steps.
    -- Step one: check if our box is a 'big boy'. We must allow some room for unknown variables like publisher-embedded padding, etc.
    local is_word_split = pos.w > 0.7 * effective_width
    -- Step two: weed out false positives (i.e long words) by comparing words found at different box coordinates.
    if is_word_split then
        -- In the case of a split (and hyphenated) word, we should get distinct words at different coordinates inside the box,
        -- false positives on the other hand, should return the same word at different coordinates.
        local word_at_pos1 = self.ui.document:getWordFromPosition({
            x = BD.mirroredUILayout() and pos.x + pos.w or pos.x,
            y = pos.y + pos.h * 1/4 -- puts us at a potential line 1 of 2
        })
        local word_at_pos2 = self.ui.document:getWordFromPosition({
            x = BD.mirroredUILayout() and pos.x or pos.x + pos.w,
            y = pos.y + pos.h * 3/4 -- puts us at a potential line 2 of 2
        })
        local does_word_at_pos1_match = word_at_pos1 and word_at_pos1.word == self.ui.highlight.selected_text.text
        local does_word_at_pos2_match = word_at_pos2 and word_at_pos2.word == self.ui.highlight.selected_text.text
        -- If all 3 words are a match, then we're likely not a split word, just a very long one, something worthy of floccinaucinihilipilification.
        if does_word_at_pos1_match and does_word_at_pos2_match then
            is_word_split = false -- check mate
        else -- We're reasonably sure the word was split (and hyphenated). Re-select the original word to ensure the correct word is highlighted.
            self.ui.document:getWordFromPosition({
                x = BD.mirroredUILayout() and pos.x + pos.w or pos.x,
                y = pos.y + pos.h * 3/4
            })
        end
    end

    -- helper function to update crosshairs positioning and self.hold_pos
    local function updatePositions(hold_x, hold_y, indicator_x, indicator_y)
        self.hold_pos = self.view:screenToPageTransform({ x = hold_x, y = hold_y })
        UIManager:setDirty(self.dialog, "ui", self._current_indicator_pos)
        self._current_indicator_pos.x = indicator_x
        self._current_indicator_pos.y = indicator_y
    end
    -- Determine positions based on word type and layout.
    if is_word_split then
        if BD.mirroredUILayout() then -- RTL
            updatePositions(
                pos.x + pos.w,          -- rightmost point
                pos.y + pos.h * 3 / 4,  -- adjusted vertical position
                pos.x + pos.w,
                pos.y + pos.h * 3 / 4 - self._current_indicator_pos.h / 2
            )
        else
            updatePositions(
                pos.x,                  -- leftmost point
                pos.y + pos.h * 3 / 4,  -- adjusted vertical position
                pos.x,
                pos.y + pos.h * 3 / 4 - self._current_indicator_pos.h / 2
            )
        end
    else
        updatePositions(
            -- set hold_pos to center of selected_text to make center selection more stable, not JITted at edge
            pos.x + pos.w / 2,          -- center of word horizontally
            pos.y + pos.h / 2,          -- center of word vertically
            pos.x + pos.w / 2 - self._current_indicator_pos.w / 2,
            pos.y + pos.h / 2 - self._current_indicator_pos.h / 2
        )
    end
    return true
end

function ReaderKeySelection:onHighlightModifierPress()
    if not self._current_indicator_pos then return false end -- let event propagate to hotkeys
    if not self._start_indicator_highlight then
        self:onHighlightPress(true)
        return true -- don't trigger hotkeys during text selection
    end
    -- Simulate very long-long press by setting the long hold flag. This will trigger the long-press dialog.
    self.ui.highlight.long_hold_reached = true
    self.ui.highlight:onHoldRelease(nil, self:_createHighlightGesture("hold_release"))
    self:onStopHighlightIndicator()
    return true
end

function ReaderKeySelection:onStartHighlightIndicator()
    -- disable long-press icon (poke-ball), as it is triggered constantly due to NT devices needing a workaround for text selection to work.
    self.ui.highlight.long_hold_reached_action = function() end
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

function ReaderKeySelection:onStopHighlightIndicator(need_clear_selection)
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
    self._start_indicator_highlight = false
    self._current_indicator_pos = nil
    self.view.highlight.indicator = nil
    UIManager:setDirty(self.dialog, "ui", rect)
    if need_clear_selection then
        self.ui.highlight:clear()
    end
    return true
end

function ReaderKeySelection:onMoveHighlightIndicator(args)
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
        -- make sure we account for both the status bar and alt status bar so we don't overlap them with the indicator
        local alt_status_bar_height = 0
        if self.ui.rolling and self.ui.document.configurable.status_line == 0 then
            alt_status_bar_height = self.ui.document:getHeaderHeight()
        end
        if rect.y < alt_status_bar_height then
            rect.y = alt_status_bar_height
        end
        local footer_height = self.view.footer_visible and self.view.footer:getHeight() or 0
        local status_bar_height = self.ui.rolling and footer_height or 0 -- for PDFs, status bar is already accounted for
        if rect.y + rect.h > self.view.visible_area.h - status_bar_height then
            rect.y = self.view.visible_area.h - status_bar_height - rect.h
        end
        UIManager:setDirty(self.dialog, "ui", self._current_indicator_pos)
        self._current_indicator_pos = rect
        self.view.highlight.indicator = rect
        UIManager:setDirty(self.dialog, "ui", rect)
        if self._start_indicator_highlight then
            self.ui.highlight:onHoldPan(nil, self:_createHighlightGesture("hold_pan"))
        end
        return true
    end
    return false
end

function ReaderKeySelection:_createHighlightGesture(gesture)
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

return ReaderKeySelection
