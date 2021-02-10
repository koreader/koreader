--[[--
AlphaContainer will paint its content (1 widget) onto lower levels using
a transparency (0..1)

Example:

    local alpha
    alpha = AlphaContainer:new{
        alpha = 0.7,

        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.default,
            margin = 0,
            padding = Size.padding.default
        }
    }
--]]

local Blitbuffer = require("ffi/blitbuffer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

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
        -- we have a saved copy of what was below our paint area.
        -- we restore this first, provided we're painting in the same spot as where the background was captured.
        if self.background_bb_x == x and self.background_bb_y == y then
            bb:blitFrom(self.background_bb, self.background_bb_x, self.background_bb_y)
        end
    end

    if not private_bb
    or private_bb:getWidth() ~= contentSize.w
    or private_bb:getHeight() ~= contentSize.h
    then
        if private_bb then
            private_bb:free() -- free the one we're going to replace
        end
        -- create private blitbuffer for our child widget to paint to
        private_bb = Blitbuffer.new(contentSize.w, contentSize.h, bb:getType())
        self.private_bb = private_bb

        -- save what is below our painting area
        if not self.background_bb
        or self.background_bb:getWidth() ~= contentSize.w
        or self.background_bb:getHeight() ~= contentSize.h
        then
            if self.background_bb then
                self.background_bb:free() -- free the one we're going to replace
            end
            self.background_bb = Blitbuffer.new(contentSize.w, contentSize.h, bb:getType())
        end
        self.background_bb:blitFrom(bb, 0, 0, x, y)
        self.background_bb_x = x
        self.background_bb_y = y
    end

    -- now have our child widget paint to the private blitbuffer
    private_bb:fill(Blitbuffer.COLOR_WHITE)
    self[1]:paintTo(private_bb, 0, 0)

    -- blit the private blitbuffer to our parent blitbuffer
    bb:addblitFrom(private_bb, x, y, nil, nil, nil, nil, self.alpha)
end

function AlphaContainer:onCloseWidget()
    if self.private_bb then
        self.private_bb:free()
        self.private_bb = nil
    end
    if self.background_bb then
        self.background_bb:free()
        self.background_bb = nil
    end
end


return AlphaContainer
