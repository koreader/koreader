--- A subclass of ImageWidget to show icons, so its fields can be used here
-- @usage local IconWidget = require("ui/widget/iconwidget")
-- local icon_widget = IconWidget:new{
--     icon = "check", -- Which corresponds to resources/icons/mdlight/check.svg
--     dim = true,
--     alpha = true
-- }
-- UIManager:show(icon_widget)
-- @module ui.widget.iconwidget
-- @see ui.widget.imagewidget

local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

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

--- @table IconWidget
-- @field alpha A boolean on whether to enable transparency on the icon (defaults to false)
-- @field icon The name (excluding the file extension) of any SVG or PNG in [resources/icons](https://github.com/koreader/koreader/tree/master/resources/icons)
local IconWidget = ImageWidget:extend{
    -- The icon filename should be provided without any path
    icon = ICON_NOT_FOUND, -- show this if not provided
    -- See ImageWidget for other available options,
    -- we only start with a few different defaults, that can
    -- be overridden by callers.
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    is_icon = true, -- avoid dithering in ImageWidget:paintTo()
    --- @note: Our icons have a transparent background, but, by default, we flatten them at caching time.
    ---        Our caller may choose to override that by setting this to true, in which case,
    ---        the alpha layer will be kept intact, and we'll do alpha-blending at blitting time.
    alpha = false
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
end

return IconWidget
