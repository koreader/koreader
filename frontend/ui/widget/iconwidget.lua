--[[
Subclass of ImageWidget to show icons
]]

local DataStorage = require("datastorage")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local Screen = require("device").screen
local logger = require("logger")

-- Directories to look for icons by name, with any of the accepted suffixes
local ICONS_DIRS = {}
local user_icons_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(user_icons_dir, "mode") == "directory" then
    table.insert(ICONS_DIRS, user_icons_dir)
end
-- Default icons (material design light)
table.insert(ICONS_DIRS, "resources/icons/mdlight")
-- Fallback directories
table.insert(ICONS_DIRS, "resources/icons")
table.insert(ICONS_DIRS, "resources")

-- Supported icon suffixes
local ICONS_EXTS = { ".svg", ".png" }

-- Show this icon instead of crashing if we can't find any icon
local ICON_NOT_FOUND = "resources/icons/icon-not-found.svg"

-- Icon filepath location cache
local ICONS_PATH = {}

local IconWidget = ImageWidget:extend{
    -- The icon filename should be provided without any path
    icon = ICON_NOT_FOUND, -- show this if not provided
    -- See ImageWidget for other available options,
    -- we only start with a few different defaults, that can
    -- be overriden by callers.
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    alpha = false, --- @note: our icons have a transparent background, but we flatten them at caching time, and this flag is only checked at blitting time.
    preserve_alpha = false, --- @note: but, we *can*, as an exception, ask to keep the alpha intact, and do alpha-blending at runtime each and every time.
    is_icon = true, -- avoid dithering in ImageWidget:paintTo()
}

function IconWidget:init()
    if self.image or self.file then
        -- In case we're created with one of these: just be an ImageWidget.
        return
    end
    -- See if already seen and full path cached
    self.file = ICONS_PATH[self.icon]
    if not self.file then
        -- Not yet seen, look for it
        for _, dir in ipairs(ICONS_DIRS) do
            for __, ext in ipairs(ICONS_EXTS) do
                local path = dir .. "/" .. self.icon .. ext
                if lfs.attributes(path, "mode") == "file" then
                    self.file = path
                    break
                end
            end
            if self.file then
                break
            end
        end
        if not self.file then
            self.file = ICON_NOT_FOUND
        end
        ICONS_PATH[self.icon] = self.file
    end

    -- If we've asked to preserve alpha, do that ;)
    if self.preserve_alpha then
        self.alpha = true
    end
end

return IconWidget
