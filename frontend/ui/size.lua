--[[--
This module provides a standardized set of sizes for use in widgets.

There are values for borders, margins, paddings, radii, and lines. Have a look
at the code for full details. If you are considering to deviate from one of the
defaults, please take a second to consider:

1. Why you want to differ in the first place. We consciously strive toward
   consistency in the UI, which is typically valued higher than one pixel more
   or less in a specific context.
2. If there really isn't anything close to what you want, whether it should be
   added to the arsenal of default sizes rather than as a local exception.

@usage
    local Size = require("ui/size")
    local frame -- just an example widget
    frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.default,
        margin = Size.margin.default,
        VerticalGroup:new{
            -- etc
        }
    }
]]

local dbg = require("dbg")
local Device = require("device")
local Screen = Device.screen

-- This function calculates reasonable large number of items based on screen properties
-- px is the screen_height or screen_width
-- 72 is used because there are 72 points per inch (in printing press)
-- limit is points (pt), i.e., what is minimum number of points to make this item readable
-- Items might be number of lines in the list (pt = 20), of mosaic grid cover size (pt = 75)
function SizeMaxItemsNorm(px, dpi, limit)
    local maxItemsNorm = math.floor(px / dpi * 72 / limit + 0.5)
    return maxItemsNorm
end

local Size = {
    border = {
        default = Screen:scaleBySize(1),
        thin = Screen:scaleBySize(0.5),
        button = Screen:scaleBySize(1.5),
        window = Screen:scaleBySize(1.5),
        thick = Screen:scaleBySize(2),
        inputtext = Screen:scaleBySize(2),
    },
    margin = {
        default = Screen:scaleBySize(5),
        tiny = Screen:scaleBySize(1),
        small = Screen:scaleBySize(2),
        title = Screen:scaleBySize(2),
        fine_tune = Screen:scaleBySize(3),
        fullscreen_popout = Screen:scaleBySize(3), -- Size.border.window * 2
        button = 0,
    },
    padding = {
        default = Screen:scaleBySize(5),
        tiny = Screen:scaleBySize(1),
        small = Screen:scaleBySize(2),
        large = Screen:scaleBySize(10),
        button = Screen:scaleBySize(2),
        buttontable = Screen:scaleBySize(4),
        fullscreen = Screen:scaleBySize(15),
    },
    radius = {
        default = Screen:scaleBySize(2),
        window = Screen:scaleBySize(7),
        button = Screen:scaleBySize(7),
    },
    line = {
        thin = Screen:scaleBySize(0.5),
        medium = Screen:scaleBySize(1),
        thick = Screen:scaleBySize(1.5),
        progress = Screen:scaleBySize(7),
    },
    item = {
        height_default = Screen:scaleBySize(30),
        height_big = Screen:scaleBySize(40),
        height_large = Screen:scaleBySize(50),
    },
    span = {
        horizontal_default = Screen:scaleBySize(10),
        horizontal_small = Screen:scaleBySize(5),
        vertical_default = Screen:scaleBySize(2),
        vertical_large = Screen:scaleBySize(5),
    },
    maxItemsNorm = {
        info_list = SizeMaxItemsNorm(Screen:getHeight(), Device.display_dpi, 20),
        mosaic_h = SizeMaxItemsNorm(Screen:getHeight(), Device.display_dpi, 75),
        mosaic_w = SizeMaxItemsNorm(Screen:getWidth(), Device.display_dpi, 75),
    },
}

if dbg.is_on then
    local mt = {
        __index = function(t, k)
            local prop_value = rawget(t, k)
            local prop_exists = prop_value ~= nil
            if not prop_exists then
                local warning = rawget(t, "_name") and string.format("Size.%s.%s", rawget(t, "_name"), k)
                                or string.format("Size.%s", k)
                error("Size: this property does not exist: " .. warning)
            end
            assert(prop_exists)
            return prop_value
        end
    }
    setmetatable(Size, mt)
    for el, table in pairs(Size) do
        table._name = el
        setmetatable(Size[el], mt)
    end
end

return Size
