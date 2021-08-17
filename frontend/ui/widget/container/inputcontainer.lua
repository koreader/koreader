--[[--
An InputContainer is a WidgetContainer that handles user input events including multi touches
and key presses.

See @{InputContainer:registerTouchZones} for examples of how to listen for multi touch input.

This example illustrates how to listen for a key press input event:

    PanBy20 = {
        { "Shift", Input.group.Cursor },
        seqtext = "Shift+Cursor",
        doc = "pan by 20px",
        event = "Pan", args = 20, is_inactive = true,
    },
    PanNormal = {
        { Input.group.Cursor },
        seqtext = "Cursor",
        doc = "pan by 10 px", event = "Pan", args = 10,
    },
    Quit = { {"Home"} },

It is recommended to reference configurable sequences from another table
and to store that table as a configuration setting.

]]

local DepGraph = require("depgraph")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")

if Device.should_restrict_JIT then
    jit.off(true, true)
end

local InputContainer = WidgetContainer:new{
    vertical_align = "top",
}

function InputContainer:_init()
    -- we need to do deep copy here
    local new_key_events = {}
    if self.key_events then
        for k,v in pairs(self.key_events) do
            new_key_events[k] = v
        end
    end
    self.key_events = new_key_events

    local new_ges_events = {}
    if self.ges_events then
        for k,v in pairs(self.ges_events) do
            new_ges_events[k] = v
        end
    end
    self.ges_events = new_ges_events
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
        self.dimen = Geom:new{w = content_size.w, h = content_size.h}
    end
    self.dimen.x = x
    self.dimen.y = y
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
        self._zones[zone.id]= {
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

function InputContainer:onInput(input, ignore_first_hold_release)
    local InputDialog = require("ui/widget/inputdialog")
    self.input_dialog = InputDialog:new{
        title = input.title or "",
        input = input.input_func and input.input_func() or input.input,
        input_hint = input.hint_func and input.hint_func() or input.hint or "",
        input_type = input.type or "number",
        buttons = input.buttons or {
            {
                {
                    text = input.cancel_text or _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = input.ok_text or _("OK"),
                    is_enter_default = true,
                    callback = function()
                        if input.deny_blank_input and self.input_dialog:getInputText() == "" then return end
                        input.callback(self.input_dialog:getInputText())
                        self:closeInputDialog()
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

return InputContainer
