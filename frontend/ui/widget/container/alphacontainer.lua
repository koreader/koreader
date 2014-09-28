local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BlitBuffer = require("ffi/blitbuffer")

--[[
AlphaContainer will paint its content (1 widget) onto lower levels using
a transparency (0..1)
--]]
local AlphaContainer = WidgetContainer:new{
    alpha = 1,
    -- we cache a blitbuffer object for re-use here:
    private_bb = nil,
    -- we save the underlying area here:
    background_bb = nil,
    background_bb_x = nil,
    background_bb_y = nil
}

function AlphaContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()
    local private_bb = self.private_bb

    if self.background_bb then
        -- we have a saved copy of what was below our paint area
        -- we restore this first
        bb:blitFrom(self.background_bb, self.background_bb_x, self.background_bb_y)
    end

    if not private_bb
    or private_bb:getWidth() ~= contentSize.w
    or private_bb:getHeight() ~= contentSize.h
    then
        -- create private blitbuffer for our child widget to paint to
        private_bb = BlitBuffer.new(contentSize.w, contentSize.h, bb:getType())
        self.private_bb = private_bb

        -- save what is below our painting area
        if not self.background_bb
        or self.background_bb:getWidth() ~= contentSize.w
        or self.background_bb:getHeight() ~= contentSize.h
        then
            self.background_bb = BlitBuffer.new(contentSize.w, contentSize.h, bb:getType())
        end
        self.background_bb:blitFrom(bb, 0, 0, x, y)
    end

    -- now have our childs paint to the private blitbuffer
    -- TODO: should we clean before painting?
    self[1]:paintTo(private_bb, 0, 0)

    -- blit the private blitbuffer to our parent blitbuffer
    bb:addblitFrom(private_bb, x, y, nil, nil, nil, nil, self.alpha)
end

return AlphaContainer
