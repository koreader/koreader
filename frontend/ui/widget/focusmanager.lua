local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local logger = require("logger")
local UIManager = require("ui/uimanager")
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
local FocusManager = InputContainer:new{
    selected = nil, -- defaults to x=1, y=1
    layout = nil, -- mandatory
    movement_allowed = { x = true, y = true }
}

function FocusManager:init()
    if not self.selected then
        self.selected = { x = 1, y = 1 }
    end

    if Device:hasDPad() then
        self.key_events = {
            -- these will all generate the same event, just with different arguments
            FocusUp =    { {"Up"},    doc = "move focus up",    event = "FocusMove", args = {0, -1} },
            FocusDown =  { {"Down"},  doc = "move focus down",  event = "FocusMove", args = {0,  1} },
            FocusLeft =  { {"Left"},  doc = "move focus left",  event = "FocusMove", args = {-1, 0} },
            FocusRight = { {"Right"}, doc = "move focus right", event = "FocusMove", args = {1,  0} },
        }
        if Device:hasFewKeys() then
            self.key_events.FocusLeft = nil
        end
    end
end

function FocusManager:onFocusMove(args)
    local dx, dy = unpack(args)

    if (dx ~= 0 and not self.movement_allowed.x)
        or (dy ~= 0 and not self.movement_allowed.y) then
        return true
    end

    if not self.layout or not self.layout[self.selected.y] or not self.layout[self.selected.y][self.selected.x] then
        return true
    end
    local current_item = self.layout[self.selected.y][self.selected.x]
    while true do
        if not self.layout[self.selected.y + dy] then
            --horizontal border, try to wraparound
            if not self:_wrapAround(dy) then
                break
            end
        elseif not self.layout[self.selected.y + dy][self.selected.x] then
            --inner horizontal border, trying to be clever and step down
            if not self:_verticalStep(dy) then
                break
            end
        elseif not self.layout[self.selected.y + dy][self.selected.x + dx] then
            --vertical border, no wraparound
            break
        else
            self.selected.y = self.selected.y + dy
            self.selected.x = self.selected.x + dx
        end
        logger.dbg("Cursor position : ".. self.selected.y .." : "..self.selected.x)

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

function FocusManager:_wrapAround(dy)
    --go to the last valid item directly above or below the current item
    --return false if none could be found
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
    if type(self.layout[self.selected.y + dy]) ~= "table" or self.layout[self.selected.y + dy] == {} then
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
    return self.layout[self.selected.y][self.selected.x]
end

return FocusManager
