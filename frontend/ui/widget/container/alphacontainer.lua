--[[--
AlphaContainer will paint its content (a single widget) at the specified opacity level (0..1)

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

local AlphaContainer = WidgetContainer:extend{
    alpha = 1,
    -- we cache a blitbuffer object for reuse here:
    private_bb = nil,
}

function AlphaContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()

    if not self.private_bb
    or self.private_bb:getWidth() ~= contentSize.w
    or self.private_bb:getHeight() ~= contentSize.h
    then
        if self.private_bb then
            self.private_bb:free() -- free the one we're going to replace
        end
        -- create a private blitbuffer for our child widget to paint to
        self.private_bb = Blitbuffer.new(contentSize.w, contentSize.h, bb:getType())
        -- fill it with our usual background color
        self.private_bb:fill(Blitbuffer.COLOR_WHITE)
    end

    -- now, compose our child widget's content on our private blitbuffer canvas
    self[1]:paintTo(self.private_bb, 0, 0)

    -- and finally blit the private blitbuffer to the target blitbuffer at the requested opacity level
    bb:addblitFrom(self.private_bb, x, y, 0, 0, contentSize.w, contentSize.h, self.alpha)
end

function AlphaContainer:onCloseWidget()
    if self.private_bb then
        self.private_bb:free()
        self.private_bb = nil
    end
end


return AlphaContainer
