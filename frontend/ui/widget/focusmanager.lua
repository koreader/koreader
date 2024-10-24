local bit = require("bit")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local util = require("util")
--[[
Wrapper Widget that manages focus for a whole dialog

supports a 2D model of active elements

e.g.:
    layout = {
        { textinput, textinput,    item },
        { okbutton,  cancelbutton, item },
        { nil,       item,         nil  },
        { nil,       item,         nil  },
        { nil,       item,         nil  },
    }
Navigate the layout by trying to avoid not set or nil value.
Provide a simple wrap around in the vertical direction.
The first element of the first table must be valid to ensure
to not get stuck in an invalid position.

but notice that this does _not_ do the layout for you,
it rather defines an abstract layout.
]]
local FocusManager = InputContainer:extend{
    selected = nil, -- defaults to x=1, y=1
    layout = nil, -- mandatory
    movement_allowed = { x = true, y = true },
}

-- Only build the default mappings once on initialization, or when an external keyboard is (dis-)/connected.
-- We'll make copies during instantiation.
local KEY_EVENTS
local BUILTIN_KEY_EVENTS
local EXTRA_KEY_EVENTS

local function populateEventMappings()
    KEY_EVENTS = {}
    BUILTIN_KEY_EVENTS = {}
    EXTRA_KEY_EVENTS = {}

    if Device:hasDPad() then
        local event_keys = {}
        -- these will all generate the same event, just with different arguments
        table.insert(event_keys, { "FocusUp",    { { "Up" },    event = "FocusMove", args = {0, -1} } })
        table.insert(event_keys, { "FocusRight", { { "Right" }, event = "FocusMove", args = {1,  0} } })
        table.insert(event_keys, { "FocusDown",  { { "Down" },  event = "FocusMove", args = {0,  1} } })
        table.insert(event_keys, { "Press",      { { "Press" }, event = "Press" } })
        local FEW_KEYS_END_INDEX = #event_keys -- Few keys device: only setup up, down, right and press

        table.insert(event_keys, { "FocusLeft",  { { "Left" },  event = "FocusMove", args = {-1, 0} } })

        -- Advanced features: more event handlers can be enabled via settings.reader.lua in a similar manner
        table.insert(event_keys, { "HoldContext",    { { "ContextMenu" },  event = "Hold" } })
        table.insert(event_keys, { "HoldShift",      { { "Shift", "Press" }, event = "Hold" } })
        table.insert(event_keys, { "HoldScreenKB",   { { "ScreenKB", "Press" }, event = "Hold" } })
        table.insert(event_keys, { "HoldSymAA",      { { "Sym", "AA" },    event = "Hold" } })
        -- half rows/columns move, it is helpful for slow device like Kindle DX to move quickly
        table.insert(event_keys, { "HalfFocusUp",    { { "Alt", "Up" },    event = "FocusHalfMove", args = {"up"} } })
        table.insert(event_keys, { "HalfFocusRight", { { "Alt", "Right" }, event = "FocusHalfMove", args = {"right"} } })
        table.insert(event_keys, { "HalfFocusDown",  { { "Alt", "Down" },  event = "FocusHalfMove", args = {"down"} } })
        table.insert(event_keys, { "HalfFocusLeft",  { { "Alt", "Left" },  event = "FocusHalfMove", args = {"left"} } })
        -- for PC navigation behavior support
        table.insert(event_keys, { "FocusNext",      { { "Tab" },          event = "FocusNext" } })
        table.insert(event_keys, { "FocusPrevious",  { { "Shift", "Tab" }, event = "FocusPrevious" } })
        local NORMAL_KEYS_END_INDEX = #event_keys

        for i = 1, FEW_KEYS_END_INDEX do
            local key_name = event_keys[i][1]
            KEY_EVENTS[key_name] = event_keys[i][2]
            BUILTIN_KEY_EVENTS[key_name] = event_keys[i][2]
        end
        if not Device:hasFewKeys() then
            for i = FEW_KEYS_END_INDEX+1, NORMAL_KEYS_END_INDEX do
                local key_name = event_keys[i][1]
                KEY_EVENTS[key_name] = event_keys[i][2]
                BUILTIN_KEY_EVENTS[key_name] = event_keys[i][2]
            end
            local focus_manager_setting = G_reader_settings:child("focus_manager")
            -- Enable advanced feature, like Hold, FocusNext, FocusPrevious
            -- Can also add extra arrow keys like using A, W, D, S for Left, Up, Right, Down
            local alternative_keymaps = focus_manager_setting:readSetting("alternative_keymaps")
            if type(alternative_keymaps) == "table" then
                for i = 1, #event_keys do
                    local key_name = event_keys[i][1]
                    local alternative_keymap = alternative_keymaps[key_name]
                    if alternative_keymap then
                        local handler_defition = util.tableDeepCopy(event_keys[i][2])
                        handler_defition[1] = alternative_keymap -- replace sample key combinations
                        local new_event_key = "Alternative" .. key_name
                        KEY_EVENTS[new_event_key] = handler_defition
                        EXTRA_KEY_EVENTS[new_event_key] = handler_defition
                    end
                end
            end
        end
    end
end

populateEventMappings()

function FocusManager:_init()
    InputContainer._init(self)

    -- These *need* to be instance-specific, hence the copy
    if not self.selected then
        self.selected = { x = 1, y = 1 }
    else
        self.selected = {x = self.selected.x, y = self.selected.y }
    end

    -- Ditto, as each widget may choose their own custom key bindings
    self.key_events = util.tableDeepCopy(KEY_EVENTS)
    -- We should be fine with a simple ref for those, though
    self.builtin_key_events = BUILTIN_KEY_EVENTS
    self.extra_key_events = EXTRA_KEY_EVENTS
end

function FocusManager:isAlternativeKey(key)
    for _, seq in pairs(self.extra_key_events) do
        for _, oneseq in ipairs(seq) do
            if key:match(oneseq) then
                return true
            end
        end
    end
    return false
end

function FocusManager:onFocusHalfMove(args)
    if not self.layout then
        return false
    end
    local direction = unpack(args)
    local x, y = self.selected.x, self.selected.y
    local row = self.layout[self.selected.y]
    local dx, dy = 0, 0
    if direction == "up" then
        dy = - math.floor(#self.layout / 2)
        if dy == 0 then
            dy = -1
        elseif dy + y <= 0 then
            dy = -y + 1 -- first row
        end
    elseif direction == "down" then
        dy = math.floor(#self.layout / 2)
        if dy == 0 then
            dy = 1
        elseif dy + y > #self.layout then
            dy = #self.layout - y -- last row
        end
    elseif direction == "left" then
        dx = - math.floor(#row / 2)
        if dx == 0 then
            dx = -1
        elseif dx + x <= 0 then
            dx = -x + 1 -- first column
        end
    elseif direction == "right" then
        dx = math.floor(#row / 2)
        if dx == 0 then
            dx = 1
        elseif dx + x > #row then
            dx = #row - y -- last column
        end
    end
    return self:onFocusMove({dx, dy})
end

function FocusManager:onPress()
    return self:sendTapEventToFocusedWidget()
end

function FocusManager:onHold()
    return self:sendHoldEventToFocusedWidget()
end

-- for tab key
function FocusManager:onFocusNext()
    if not self.layout then
        return false
    end
    local x, y = self.selected.x, self.selected.y
    local row = self.layout[y]
    local dx, dy = 1, 0
    if not row[x + dx] then -- beyond end of column, go to next row
        dx, dy = 0, 1
    end
    return self:onFocusMove({dx, dy})
end

-- for backtab key
function FocusManager:onFocusPrevious()
    if not self.layout then
        return false
    end
    local x, y = self.selected.x, self.selected.y
    local row = self.layout[y]
    local dx, dy = -1, 0
    if not row[x + dx] then -- beyond start of column, go to previous row
        dx, dy = 0, -1
    end
    return self:onFocusMove({dx, dy})
end

function FocusManager:onFocusMove(args)
    if not self.layout then -- allow parent focus manager to handle the event
        return false
    end
    local dx, dy = unpack(args)

    if (dx ~= 0 and not self.movement_allowed.x)
        or (dy ~= 0 and not self.movement_allowed.y) then
        return true
    end

    if not self.layout[self.selected.y] or not self.layout[self.selected.y][self.selected.x] then
        logger.dbg("FocusManager: no currently selected widget found")
        return true
    end
    local current_item = self.layout[self.selected.y][self.selected.x]
    while true do
        if not self.layout[self.selected.y + dy] then
            --horizontal border, try to wraparound
            if not self:_wrapAroundY(dy) then
                break
            end
        elseif not self.layout[self.selected.y + dy][self.selected.x] then
            --inner horizontal border, trying to be clever and step down
            if not self:_verticalStep(dy) then
                break
            end
        elseif not self.layout[self.selected.y + dy][self.selected.x + dx] then
            --vertical border, try to wraparound
            if not self:_wrapAroundX(dx) then
                break
            end
        else
            self.selected.y = self.selected.y + dy
            self.selected.x = self.selected.x + dx
        end
        logger.dbg("FocusManager cursor position is:", self.selected.x, ",", self.selected.y)

        if self.layout[self.selected.y][self.selected.x] ~= current_item
        or not self.layout[self.selected.y][self.selected.x].is_inactive then
            -- we found a different object to focus
            current_item:handleEvent(Event:new("Unfocus"))
            self.layout[self.selected.y][self.selected.x]:handleEvent(Event:new("Focus"))
            -- Trigger a fast repaint, this does not count toward a flashing eink refresh
            -- NOTE: Ideally, we'd only have to repaint the specific subwidget we're highlighting,
            --       but we may not know its exact coordinates, so, redraw the parent widget instead.
            UIManager:setDirty(self.show_parent or self, "fast")
            break
        end
    end
    return true
end

function FocusManager:onPhysicalKeyboardConnected()
    -- Re-initialize with new keys info.
    populateEventMappings()
    -- We can't just call FocusManager._init because it will *reset* the mappings, losing our widget-specific ones (if any),
    -- and it'll call InputContainer._init, which *also* resets the touch zones.
    -- Instead, we'll just do a merge ourselves.
    util.tableMerge(self.key_events, KEY_EVENTS)
    -- populateEventMappings replaces these, so, update our refs
    self.builtin_key_events = BUILTIN_KEY_EVENTS
    self.extra_key_events = EXTRA_KEY_EVENTS
end

function FocusManager:onPhysicalKeyboardDisconnected()
    local prev_key_events = KEY_EVENTS
    populateEventMappings()

    -- If we still have keys, remove what disappeared from KEY_EVENTS from self.key_events (if any).
    if Device:hasKeys() then
        -- NOTE: This is slightly overkill, we could very well live with a few unreachable mappings for the rest of this widget's life ;).
        for k, _ in pairs(prev_key_events) do
            if not KEY_EVENTS[k] then
                self.key_events[k] = nil
            end
        end
    else
        -- If we longer have keys at all, that's easy ;).
        self.key_events = {}
    end
    self.builtin_key_events = BUILTIN_KEY_EVENTS
    self.extra_key_events = EXTRA_KEY_EVENTS
end

-- constant, used to reset focus widget after layout recreation
-- do not send an Unfocus event
FocusManager.NOT_UNFOCUS = 1
-- do not send a Focus event
FocusManager.NOT_FOCUS = 2
-- In some cases, we may only want to send Focus events on non-Touch devices
FocusManager.FOCUS_ONLY_ON_NT = (Device:hasDPad() and not Device:isTouchDevice()) and 0 or FocusManager.NOT_FOCUS
-- And in some cases, we may want to send both events *regardless* of heuristics or device caps
FocusManager.FORCED_FOCUS = 4

--- Move focus to specified widget
function FocusManager:moveFocusTo(x, y, focus_flags)
    focus_flags = focus_flags or 0
    if not self.layout then
        return false
    end
    local current_item = nil
    if self.layout[self.selected.y] then
        current_item = self.layout[self.selected.y][self.selected.x]
    end
    local target_item = nil
    if self.layout[y] then
        target_item = self.layout[y][x]
    end
    if target_item then
        logger.dbg("FocusManager: Move focus position to:", x, ",", y)
        self.selected.x = x
        self.selected.y = y
        -- widget create new layout on update, previous may be removed from new layout.
        if bit.band(focus_flags, FocusManager.FORCED_FOCUS) == FocusManager.FORCED_FOCUS or Device:hasDPad() then
            -- If FORCED_FOCUS was requested, we want *all* the events: mask out both NOT_ bits
            if bit.band(focus_flags, FocusManager.FORCED_FOCUS) == FocusManager.FORCED_FOCUS then
                focus_flags = bit.band(focus_flags, bit.bnot(bit.bor(FocusManager.NOT_UNFOCUS, FocusManager.NOT_FOCUS)))
            end
            if bit.band(focus_flags, FocusManager.NOT_UNFOCUS) ~= FocusManager.NOT_UNFOCUS then
                -- NOTE: We can't necessarily guarantee the integrity of self.layout,
                --       as some callers *will* mangle it and call us expecting to fix things ;).
                --       Since we do not want to leave *multiple* items (visually) focused,
                --       we potentially need to be a bit heavy-handed ;).
                if current_item and current_item ~= target_item then
                    -- This is the absolute best-case scenario, when self.layout's integrity is sound
                    current_item:handleEvent(Event:new("Unfocus"))
                else
                    -- Couldn't find the current item, or it matches the target_item: blast the whole widget container,
                    -- just in case we still have a different, older widget visually focused.
                    -- Can easily happen if caller calls refocusWidget *after* having manually mangled self.layout.
                    self:handleEvent(Event:new("Unfocus"))
                end
            end
            if bit.band(focus_flags, FocusManager.NOT_FOCUS) ~= FocusManager.NOT_FOCUS then
                target_item:handleEvent(Event:new("Focus"))
                UIManager:setDirty(self.show_parent or self, "fast")
            end
        end
        return true
    end
    return false
end

--- Go to the last valid item directly left or right of the current item.
-- @return false if none could be found
function FocusManager:_wrapAroundX(dx)
    local x = self.selected.x
    while self.layout[self.selected.y][x - dx] do
        x = x - dx
    end
    if x ~= self.selected.x then
        self.selected.x = x
        if not self.layout[self.selected.y][self.selected.x] then
            --call verticalStep on the current line to perform the search
            return self:_verticalStep(0)
        end
        return true
    else
        return false
    end
end

--- Go to the last valid item directly above or below the current item.
-- @return false if none could be found
function FocusManager:_wrapAroundY(dy)
    local y = self.selected.y
    while self.layout[y - dy] do
        y = y - dy
    end
    if y ~= self.selected.y then
        self.selected.y = y
        if not self.layout[self.selected.y][self.selected.x] then
            --call verticalStep on the current line to perform the search
            return self:_verticalStep(0)
        end
        return true
    else
        return false
    end
end

function FocusManager:_verticalStep(dy)
    local x = self.selected.x
    if type(self.layout[self.selected.y + dy]) ~= "table" or next(self.layout[self.selected.y + dy]) == nil then
        logger.err("[FocusManager] : Malformed layout")
        return false
    end
    --looking for the item on the line below, the closest on the left side
    while not self.layout[self.selected.y + dy][x] do
        x = x - 1
        if x == 0 then
            --if he is not on the left, must be on the right
            x = self.selected.x
            while not self.layout[self.selected.y + dy][x] do
                x = x + 1
            end
        end
    end
    self.selected.x = x
    self.selected.y = self.selected.y + dy
    return true
end

function FocusManager:getFocusItem()
    if not self.layout then
        return nil
    end
    return self.layout[self.selected.y][self.selected.x]
end

function FocusManager:_sendGestureEventToFocusedWidget(gesture)
    local focused_widget = self:getFocusItem()
    if focused_widget then
        -- center of widget position
        local point = focused_widget.dimen:copy()
        point.x = point.x + point.w / 2
        point.y = point.y + point.h / 2
        point.w = 0
        point.h = 0
        logger.dbg("FocusManager: Send", gesture, "to", point.x , ",", point.y)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = gesture,
            pos = point,
        }))
        return true
    end
    return false
end

function FocusManager:sendTapEventToFocusedWidget()
    return self:_sendGestureEventToFocusedWidget("tap")
end

function FocusManager:sendHoldEventToFocusedWidget()
    return self:_sendGestureEventToFocusedWidget("hold")
end

function FocusManager:mergeLayoutInVertical(child, pos)
    if not child.layout then
        return
    end
    if not pos then
        pos = #self.layout + 1 -- end of row
    end
    for _, row in ipairs(child.layout) do
        table.insert(self.layout, pos, row)
        pos = pos + 1
    end
    child:disableFocusManagement(self)
end

function FocusManager:mergeLayoutInHorizontal(child)
    if not child.layout then
        return
    end
    for i, row in ipairs(child.layout) do
        local prow = self.layout[i]
        if not prow then
            prow = {}
            self.layout[i] = prow
        end
        for _, widget in ipairs(row) do
            table.insert(prow, widget)
        end
    end
    child:disableFocusManagement(self)
end

function FocusManager:disableFocusManagement(parent)
    self._parent = parent
    -- unfocus current widget in current child container
    -- parent container will call refocusWidget to focus another one
    local row = self.layout[self.selected.y]
    if row and row[self.selected.x] then
        row[self.selected.x]:handleEvent(Event:new("Unfocus"))
    end
    self.layout = nil -- turn off focus feature
end

-- constant for refocusWidget method to ease code reading
FocusManager.RENDER_NOW = false
FocusManager.RENDER_IN_NEXT_TICK = true

--- Container calls this method to re-set focus widget style
--- Some container regenerate layout on update and lose focus style
function FocusManager:refocusWidget(nextTick, focus_flags)
    -- On touch devices, we do *not* want to show visual focus changes generated programmatically,
    -- we only want to see them for actual user input events (#12361).
    if not focus_flags then
        focus_flags = FocusManager.FOCUS_ONLY_ON_NT
    end

    if not self._parent then
        if not nextTick then
            self:moveFocusTo(self.selected.x, self.selected.y, focus_flags)
        else
            -- sometimes refocusWidget called in widget's action callback
            -- widget may force repaint after callback, like Button with vsync = true
            -- then focus style will be lost, set focus style to next tick to make sure focus style painted
            UIManager:nextTick(function()
                self:moveFocusTo(self.selected.x, self.selected.y, focus_flags)
            end)
        end
    else
        self._parent:refocusWidget(nextTick, focus_flags)
        self._parent = nil
    end
end

return FocusManager
