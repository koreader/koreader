local InputContainer = require("ui/widget/container/inputcontainer")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")

--[[
Wrapper Widget that manages focus for a whole dialog

supports a 2D model of active elements

e.g.:
    layout = {
        { textinput, textinput },
        { okbutton,  cancelbutton }
    }

this is a dialog with 2 rows. in the top row, there is the
single (!) widget <textinput>. when the focus is in this
group, left/right movement seems (!) to be doing nothing.

in the second row, there are two widgets and you can move
left/right. also, you can go up from both to reach <textinput>,
and from that go down and (depending on internat coordinates)
reach either <okbutton> or <cancelbutton>.

but notice that this does _not_ do the layout for you,
it rather defines an abstract layout.
]]
local FocusManager = InputContainer:new{
    selected = nil, -- defaults to x=1, y=1
    layout = nil, -- mandatory
    movement_allowed = { x = true, y = true }
}

function FocusManager:init()
    self.selected = { x = 1, y = 1 }
    self.key_events = {
        -- these will all generate the same event, just with different arguments
        FocusUp =    { {"Up"},    doc = "move focus up",    event = "FocusMove", args = {0, -1} },
        FocusDown =  { {"Down"},  doc = "move focus down",  event = "FocusMove", args = {0,  1} },
        FocusLeft =  { {"Left"},  doc = "move focus left",  event = "FocusMove", args = {-1, 0} },
        FocusRight = { {"Right"}, doc = "move focus right", event = "FocusMove", args = {1,  0} },
    }
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
        if self.selected.x + dx > #self.layout[self.selected.y]
        or self.selected.x + dx < 1 then
            break  -- abort when we run into horizontal borders
        end

        -- move cyclic in vertical direction
        if self.selected.y + dy > #self.layout then
            if not self:onWrapLast() then
                break
            end
        elseif self.selected.y + dy < 1 then
            if not self:onWrapFirst() then
                break
            end
        else
            self.selected.y = self.selected.y + dy
        end
        self.selected.x = self.selected.x + dx

        if self.layout[self.selected.y][self.selected.x] ~= current_item
        or not self.layout[self.selected.y][self.selected.x].is_inactive then
            -- we found a different object to focus
            current_item:handleEvent(Event:new("Unfocus"))
            self.layout[self.selected.y][self.selected.x]:handleEvent(Event:new("Focus"))
            -- trigger a repaint (we need to be the registered widget!)
            UIManager:setDirty(self.show_parent or  self, "partial")
            break
        end
    end

    return true
end

function FocusManager:onWrapFirst()
    self.selected.y = #self.layout
    return true
end

function FocusManager:onWrapLast()
    self.selected.y = 1
    return true
end

return FocusManager
