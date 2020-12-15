--[[
Subclass of ImageWidget to show icons
]]

local ImageWidget = require("ui/widget/imagewidget")
local Screen = require("device").screen

local IconWidget = ImageWidget:extend{
    -- The icon filename should be provided without any path
    icon = "notice-warning.svg", -- show this if not provided

    -- Hardcoded. If we want themes, just have this point
    -- to an alternative directory
    icon_dir = "resources/icons/svg/",

    -- See ImageWidget for other available options,
    -- we only start with a few different defaults, that can
    -- be overriden by callers.
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    alpha = true, -- our icons have a transparent background
    is_icon = true,
}

function IconWidget:init()
    if self.image or self.file then
        -- In case we're created with one of these: just be an ImageWidget.
        return
    end
    self.file = self.icon_dir .. self.icon
end

return IconWidget
