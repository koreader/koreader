--[[--
An InputContainer is a WidgetContainer that handles user input events including multi touches and key presses.

See @{InputContainer:registerTouchZones} for examples of how to listen for multi touch input.

This example illustrates how to listen for a key press input event via the `key_events` hashmap:

    key_events = {
        PanBy20 = {
            { "Shift", Input.group.Cursor }, -- Shift + (any member of) Cursor
            event = "Pan",
            args = 20,
            is_inactive = true,
        },
        PanNormal = {
            { Input.group.Cursor }, -- Any member of Cursor (itself an array)
            event = "Pan",
            args = 10,
        },
        Exit = {
            { "Alt", "F4" }, -- Alt + F4
            { "Ctrl", "Q" }, -- Ctrl + Q
        },
        Home = {
            { { "Home", "H" } }, -- Any of Home or H (note the extra nesting!)
        },
        End = {
            { "End" }, -- NOTE: For a *single* key, we can forgo the nesting (c.f., match @ device/key).
        },
    },

It is recommended to reference configurable sequences from another table
and to store that table as a configuration setting.

]]

local DepGraph = require("depgraph")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Screen = Device.screen
local _ = require("gettext")

local InputContainer = WidgetContainer:extend{
    vertical_align = "top",
}

function InputContainer:_init()
    -- These should be instance-specific
    if not self.key_events then
        self.key_events = {}
    end
    if not self.ges_events then
        self.ges_events = {}
    end
    self.touch_zone_dg = nil
    self._zones = {}
    self._ordered_touch_zones = {}
end

function InputContainer:paintTo(bb, x, y)
    if self[1] == nil then
        return
    end
    if self.skip_paint then
        return
    end

    if not self.dimen then
        local content_size = self[1]:getSize()
        self.dimen = Geom:new{
            x = x, y = y,
            w = content_size.w, h = content_size.h,
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    if self.vertical_align == "center" then
        local content_size = self[1]:getSize()
        self[1]:paintTo(bb, x, y + math.floor((self.dimen.h - content_size.h)/2))
    else
        self[1]:paintTo(bb, x, y)
    end
end

--[[--

Register touch zones into this InputContainer.

See gesturedetector for a list of supported gestures.

NOTE: You are responsible for calling self:@{updateTouchZonesOnScreenResize} with the new
screen dimensions whenever the screen is rotated or resized.

@tparam table zones list of touch zones to register

@usage
local InputContainer = require("ui/widget/container/inputcontainer")
local test_widget = InputContainer:new{}
test_widget:registerTouchZones({
    {
        id = "foo_tap",
        ges = "tap",
        -- This binds the handler to the full screen
        screen_zone = {
            ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
        },
        handler = function(ges)
            print('User tapped on screen!')
            return true
        end
    },
    {
        id = "foo_swipe",
        ges = "swipe",
        -- This binds the handler to bottom half of the screen
        screen_zone = {
            ratio_x = 0, ratio_y = 0.5, ratio_w = 1, ratio_h = 0.5,
        },
        handler = function(ges)
            print("User swiped at the bottom with direction:", ges.direction)
            return true
        end
    },
})
require("ui/uimanager"):show(test_widget)

]]
function InputContainer:registerTouchZones(zones)
    local screen_width, screen_height = Screen:getWidth(), Screen:getHeight()
    if not self.touch_zone_dg then self.touch_zone_dg = DepGraph:new{} end
    for _, zone in ipairs(zones) do
        -- override touch zone with the same id to support reregistration
        if self._zones[zone.id] then
            self.touch_zone_dg:removeNode(zone.id)
        end
        self._zones[zone.id] = {
            def = zone,
            handler = zone.handler,
            gs_range = GestureRange:new{
                ges = zone.ges,
                rate = zone.rate,
                range = Geom:new{
                    x = screen_width * zone.screen_zone.ratio_x,
                    y = screen_height * zone.screen_zone.ratio_y,
                    w = screen_width * zone.screen_zone.ratio_w,
                    h = screen_height * zone.screen_zone.ratio_h,
                },
            },
        }
        self.touch_zone_dg:addNode(zone.id)
        -- print("added "..zone.id)
        if zone.overrides then
            for _, override_zone_id in ipairs(zone.overrides) do
                -- print("  override "..override_zone_id)
                self.touch_zone_dg:addNodeDep(override_zone_id, zone.id)
            end
        end
    end
    -- print("ordering:")
    self._ordered_touch_zones = {}
    for _, zone_id in ipairs(self.touch_zone_dg:serialize()) do
        table.insert(self._ordered_touch_zones, self._zones[zone_id])
        -- print("  "..zone_id)
    end
end

function InputContainer:unRegisterTouchZones(zones)
    if self.touch_zone_dg then
        for i, zone in ipairs(zones) do
            if self._zones[zone.id] then
                self.touch_zone_dg:removeNode(zone.id)
                if zone.overrides then
                    for _, override_zone_id in ipairs(zone.overrides) do
                        --self.touch_zone_dg:removeNodeDep(override_zone_id, zone.id)
                        self.touch_zone_dg:removeNodeDep(override_zone_id, zone.id)
                    end
                end
                for _, id in ipairs(self._ordered_touch_zones) do
                    if id.def.id == zone.id then
                        table.remove(self._ordered_touch_zones, i)
                        break
                    end
                end
            end
        end
        self._ordered_touch_zones = {}
        if self.touch_zone_dg then
            for _, zone_id in ipairs(self.touch_zone_dg:serialize()) do
                table.insert(self._ordered_touch_zones, self._zones[zone_id])
            end
        end
    end
end

function InputContainer:checkRegisterTouchZone(id)
    if self.touch_zone_dg then
        return self.touch_zone_dg:checkNode(id)
    else
        return false
    end
end

--[[--
Updates touch zones based on new screen dimensions.

@tparam ui.geometry.Geom new_screen_dimen new screen dimensions
]]
function InputContainer:updateTouchZonesOnScreenResize(new_screen_dimen)
    for _, tzone in ipairs(self._ordered_touch_zones) do
        local range = tzone.gs_range.range
        range.x = new_screen_dimen.w * tzone.def.screen_zone.ratio_x
        range.y = new_screen_dimen.h * tzone.def.screen_zone.ratio_y
        range.w = new_screen_dimen.w * tzone.def.screen_zone.ratio_w
        range.h = new_screen_dimen.h * tzone.def.screen_zone.ratio_h
    end
end

--[[
Handles keypresses and checks if they lead to a command.
If this is the case, we retransmit another event within ourselves.
--]]
function InputContainer:onKeyPress(key)
    for name, seq in pairs(self.key_events) do
        if not seq.is_inactive then
            for _, oneseq in ipairs(seq) do
                -- NOTE: key is a device/key object, this isn't string.match!
                if key:match(oneseq) then
                    local eventname = seq.event or name
                    return self:handleEvent(Event:new(eventname, seq.args, key))
                end
            end
        end
    end
end

-- NOTE: Currently a verbatim copy of onKeyPress ;).
function InputContainer:onKeyRepeat(key)
    for name, seq in pairs(self.key_events) do
        if not seq.is_inactive then
            for _, oneseq in ipairs(seq) do
                if key:match(oneseq) then
                    local eventname = seq.event or name
                    return self:handleEvent(Event:new(eventname, seq.args, key))
                end
            end
        end
    end
end

function InputContainer:onGesture(ev)
    for _, tzone in ipairs(self._ordered_touch_zones) do
        if tzone.gs_range:match(ev) and tzone.handler(ev) then
            return true
        end
    end
    for name, gsseq in pairs(self.ges_events) do
        for _, gs_range in ipairs(gsseq) do
            if gs_range:match(ev) then
                local eventname = gsseq.event or name
                if self:handleEvent(Event:new(eventname, gsseq.args, ev)) then
                    return true
                end
            end
        end
    end
    if self.stop_events_propagation then
        return true
    end
end

-- Will be overloaded by the Gestures plugin, if enabled, for use in _onGestureFiltered
function InputContainer:_isGestureAlwaysActive(ges, multiswipe_directions)
    -- If the plugin isn't enabled, IgnoreTouchInput can still be emitted by Dispatcher (e.g., via Profile or QuickMenu).
    -- Regardless of that, we still want to block all gestures anyway, as our own onResume handler will ensure
    -- that the standard onGesture handler is restored on the next resume cycle,
    -- allowing one to restore input handling automatically.
    return false
end
InputContainer.isGestureAlwaysActive = InputContainer._isGestureAlwaysActive

-- Filtered variant that only lets specific touch zones marked as "always active" through.
-- (This is used by the "toggle_touch_input" Dispatcher action).
function InputContainer:_onGestureFiltered(ev)
    for _, tzone in ipairs(self._ordered_touch_zones) do
        if self:isGestureAlwaysActive(tzone.def.id, ev.multiswipe_directions) and tzone.gs_range:match(ev) and tzone.handler(ev) then
            return true
        end
    end
    -- No ges_events at all, although if the need ever arises, we could also support an "always active" marker for those ;).
    if self.stop_events_propagation then
        return true
    end
end

-- NOTE: Monkey-patching InputContainer.onGesture allows us to effectively disable touch input,
--       because barely any InputContainer subclasses implement onGesture, meaning they all inherit this one,
--       making this specific method in this specific widget the only piece of code that handles the Gesture
--       Events sent by GestureDetector.
--       We would need to be slightly more creative if subclassed widgets did overload it in in any meaningful way[1].
--       (i.e., use a broadcast Event, don't stop its propagation, and swap self.onGesture in every instance
--       while still only swapping Input.onGesture once...).
--
--       [1] The most common implementation you'll see is a NOP for ReaderUI modules that defer gesture handling to ReaderUI.
--           Notification also implements a simple one to dismiss notifications on any user input,
--           which is something that doesn't impede our goal, which is why we don't need to deal with it.
function InputContainer:setIgnoreTouchInput(state)
    logger.dbg("InputContainer:setIgnoreTouchInput", state)
    if state == true then
        -- Replace the onGesture handler w/ the minimal one if that's not already the case
        if not InputContainer._onGesture then
            InputContainer._onGesture = InputContainer.onGesture
            InputContainer.onGesture = InputContainer._onGestureFiltered
            -- Notify UIManager so it knows what to do if a random popup shows up
            UIManager._input_gestures_disabled = true
            logger.dbg("Disabled InputContainer gesture handler")

            -- Notify our caller that the state changed
            return true
        end
    elseif state == false then
        -- Restore the proper onGesture handler if we disabled it
        if InputContainer._onGesture then
            InputContainer.onGesture = InputContainer._onGesture
            InputContainer._onGesture = nil
            UIManager._input_gestures_disabled = false
            logger.dbg("Restored InputContainer gesture handler")

            return true
        end
    end

    -- We did not actually change the state
    return false
end

-- And the matching Event handler
function InputContainer:onIgnoreTouchInput(toggle)
    local Notification = require("ui/widget/notification")
    if toggle == true then
        if self:setIgnoreTouchInput(true) then
            Notification:notify(_("Disabled touch input"))
        end
    elseif toggle == false then
        if self:setIgnoreTouchInput(false) then
            Notification:notify(_("Restored touch input"))
        end
    else
        -- Toggle the current state
        return self:onIgnoreTouchInput(not UIManager._input_gestures_disabled)
    end

    -- We only affect the base class, once is enough ;).
    return true
end

function InputContainer:onInput(input, ignore_first_hold_release)
    local InputDialog = require("ui/widget/inputdialog")
    self.input_dialog = InputDialog:new{
        title = input.title,
        input = input.input_func and input.input_func() or input.input,
        input_hint = input.hint_func and input.hint_func() or input.hint,
        input_type = input.input_type,
        buttons = input.buttons or {
            {
                {
                    text = input.cancel_text or _("Cancel"),
                    id = "close",
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = input.ok_text or _("OK"),
                    is_enter_default = true,
                    callback = function()
                        if input.allow_blank_input or self.input_dialog:getInputText() ~= "" then
                            input.callback(self.input_dialog:getInputText())
                            self:closeInputDialog()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard(ignore_first_hold_release)
end

function InputContainer:closeInputDialog()
    UIManager:close(self.input_dialog)
end

function InputContainer:onPhysicalKeyboardDisconnected()
    -- Clear the key bindings if Device no longer has keys
    -- NOTE: hasKeys is the lowest common denominator of key-related Device caps,
    --       hasDPad/hasFewKeys/hasKeyboard all imply hasKeys ;).
    if not Device:hasKeys() then
        self.key_events = {}
    end
end

return InputContainer
