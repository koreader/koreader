local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Screen = require("device").screen

local ReaderFlipping = InputContainer:new{
    orig_reflow_mode = 0,
}

function ReaderFlipping:init()
    local icon_size = Screen:scaleBySize(32)
    local widget = ImageWidget:new{
        file = "resources/icons/appbar.book.open.png",
        width = icon_size,
        height = icon_size,
        alpha = true,
    }
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = widget:getSize().h},
        widget,
    }
    self:resetLayout()
end

function ReaderFlipping:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._last_screen_width then return end
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
end

return ReaderFlipping
