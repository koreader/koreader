--[[--
A layout widget that puts objects above each other.
--]]

local BD = require("ui/bidi")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local OverlapGroup = WidgetContainer:extend{
    -- Note: we default to allow_mirroring = true.
    -- When using LeftContainer, RightContainer or HorizontalGroup
    -- in an OverlapGroup, mostly when they take the whole width,
    -- either OverlapGroup, or all the others, need to have
    -- allow_mirroring=false (otherwise, some upper mirroring would
    -- cancel a lower one...).
    -- It's usually safer to set it to false on the OverlapGroup,
    -- but some thinking is needed when many of them are nested.
    allow_mirroring = true,
    _size = nil,
}

function OverlapGroup:getSize()
    if not self._size then
        self._size = {w = 0, h = 0}
        self._offsets = { x = math.huge, y = math.huge }
        for i, widget in ipairs(self) do
            local w_size = widget:getSize()
            if self._size.h < w_size.h then
                self._size.h = w_size.h
            end
            if self._size.w < w_size.w then
                self._size.w = w_size.w
            end
        end
    end

    return self._size
end

-- NOTE: OverlapGroup is one of those special snowflakes that will compute self.dimen at init,
--       instead of at paintTo...
function OverlapGroup:init()
    self:getSize()  -- populate self._size
    -- sync self._size with self.dimen, self.dimen has higher priority
    if self.dimen then
        -- Jump through some extra hoops because this may not be a Geom...
        if self.dimen.w then
            self._size.w = self.dimen.w
        end
        if self.dimen.h then
            self._size.h = self.dimen.h
        end
    end
    -- Regardless of what was passed to the constructor, make sure dimen is actually a Geom
    self.dimen = Geom:new{x = 0, y = 0, w = self._size.w, h = self._size.h}
end

function OverlapGroup:paintTo(bb, x, y)
    local size = self:getSize()

    for i, wget in ipairs(self) do
        local wget_size = wget:getSize()
        local overlap_align = wget.overlap_align
        if BD.mirroredUILayout() and self.allow_mirroring then
            -- Checks in the same order as how they are checked below
            if overlap_align == "right" then
                overlap_align = "left"
            elseif overlap_align == "center" then
                overlap_align = "center"
            elseif wget.overlap_offset then
                wget.overlap_offset[1] = size.w - wget_size.w - wget.overlap_offset[1]
            else
                overlap_align = "right"
            end
            -- see if something to do with wget.overlap_offset
        end
        if overlap_align == "right" then
            wget:paintTo(bb, x+size.w-wget_size.w, y)
        elseif overlap_align == "center" then
            wget:paintTo(bb, x+math.floor((size.w-wget_size.w)/2), y)
        elseif wget.overlap_offset then
            wget:paintTo(bb, x+wget.overlap_offset[1], y+wget.overlap_offset[2])
        else
            -- default to left
            wget:paintTo(bb, x, y)
        end
    end
end

return OverlapGroup
