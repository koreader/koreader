--[[--
An InputContainer is an WidgetContainer that handles user input events including multi touches
and key presses.

See @{InputContainer:registerTouchZones} for example on how to listen for multi touch inputs.

An example for listening on key press input event is this:

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

It is suggested to reference configurable sequences from another table
and store that table as configuration setting

]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Event = require("ui/event")
local _ = require("gettext")

if require("device"):isAndroid() then
    require("jit").off(true, true)
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
    self._touch_zones = {}
    self._touch_zone_pos_idx = {}
end

function InputContainer:paintTo(bb, x, y)
    if self[1] == nil then
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

See gesturedetector for list of supported gestures.

NOTE: You are responsible for calling self:@{updateTouchZonesOnScreenResize} with the new
screen dimension whenever the screen is rotated or resized.

@tparam table zones list of touch zones to register

@usage
local InputContainer = require("ui/widget/container/inputcontainer")
local test_widget = InputContainer:new{}
test_widget:registerTouchZones({
    {
        id = "foo_tap",
        ges = "tap",
        -- This binds handler to the full screen
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
        -- This binds handler to bottom half of the screen
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
    for _, zone in ipairs(zones) do
        if self._touch_zone_pos_idx[zone.id] then
            table.remove(self._touch_zones, self._touch_zone_pos_idx[zone.id])
            self._touch_zone_pos_idx[zone.id] = nil
        end
        local tzone = {
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
        local insert_pos = #self._touch_zones
        if insert_pos ~= 0 then
            if zone.overrides then
                for _, override_id in ipairs(zone.overrides) do
                    local zone_idx = self._touch_zone_pos_idx[override_id]
                    if zone_idx and zone_idx < insert_pos then
                        insert_pos = zone_idx
                    end
                end
            else
                insert_pos = 0
            end
        end
        if insert_pos == 0 then
            table.insert(self._touch_zones, tzone)
            self._touch_zone_pos_idx[zone.id] = 1
        else
            table.insert(self._touch_zones, insert_pos, tzone)
            self._touch_zone_pos_idx[zone.id] = insert_pos
        end
    end
end

--[[--
Update touch zones based on new screen dimension.

@tparam ui.geometry.Geom new_screen_dimen new screen dimension
]]
function InputContainer:updateTouchZonesOnScreenResize(new_screen_dimen)
    for _, tzone in ipairs(self._touch_zones) do
        local range = tzone.gs_range
        range.x = new_screen_dimen.w * tzone.def.screen_zone.ratio_x
        range.y = new_screen_dimen.h * tzone.def.screen_zone.ratio_y
        range.w = new_screen_dimen.w * tzone.def.screen_zone.ratio_w
        range.h = new_screen_dimen.h * tzone.def.screen_zone.ratio_h
    end
end

--[[
the following handler handles keypresses and checks if they lead to a command.
if this is the case, we retransmit another event within ourselves
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

function InputContainer:onGesture(ev)
    for _, tzone in ipairs(self._touch_zones) do
        if tzone.gs_range:match(ev) then
            return tzone.handler(ev)
        end
    end
    for name, gsseq in pairs(self.ges_events) do
        for _, gs_range in ipairs(gsseq) do
            if gs_range:match(ev) then
                local eventname = gsseq.event or name
                return self:handleEvent(Event:new(eventname, gsseq.args, ev))
            end
        end
    end
end

function InputContainer:onInput(input)
    local InputDialog = require("ui/widget/inputdialog")
    self.input_dialog = InputDialog:new{
        title = input.title or "",
        input = input.input,
        input_hint = input.hint_func and input.hint_func() or input.hint or "",
        input_type = input.type or "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        input.callback(self.input_dialog:getInputText())
                        self:closeInputDialog()
                    end,
                },
            },
        },
    }
    self.input_dialog:onShowKeyboard()
    UIManager:show(self.input_dialog)
end

function InputContainer:closeInputDialog()
    UIManager:close(self.input_dialog)
end

return InputContainer
