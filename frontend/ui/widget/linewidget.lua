local Widget = require("ui/widget/widget")
local Blitbuffer = require("ffi/blitbuffer")

local LineWidget = Widget:new{
    style = "solid",
    background = Blitbuffer.COLOR_BLACK,
    dimen = nil,
    --@TODO replay dirty hack here  13.03 2013 (houqp)
    empty_segments = nil,
}

function LineWidget:paintTo(bb, x, y)
    if self.style == "none" then return end
    if self.style == "dashed" then
        for i = 0, self.dimen.w - 20, 20 do
            bb:paintRect(x + i, y,
                        16, self.dimen.h, self.background)
        end
    else
        if self.empty_segments then
            bb:paintRect(x, y,
                        self.empty_segments[1].s,
                        self.dimen.h,
                        self.background)
            bb:paintRect(x + self.empty_segments[1].e, y,
                        self.dimen.w - x - self.empty_segments[1].e,
                        self.dimen.h,
                        self.background)
        else
            bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.background)
        end
    end
end

return LineWidget
