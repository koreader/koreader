--[[
    File formats supported by KOReader. These are reported when the device talks with calibre wireless server.

    calibre assumes that the list is in desired order.
    When sending documents if no format on the list exists then calibre converts the book to the first format.

    See https://www.mobileread.com/forums/showthread.php?t=341423
--]]

local valid_ext = {
    "epub",
    "fb2",
    "mobi",
    "azw",
    "xps",
    "doc",
    "docx",
    "djv",
    "djvu",
    "pdf",
    "cbz",
    "htm",
    "html",
    "xhtml",
    "pdb",
    "prc",
    "rtf",
    "txt",
    "md",
    "chm",
    "zip",
}

-- if the file "calibre-extensions.lua", under dataDir, returns a table
-- then use it instead of default extensions.
local function getCustomConfig()
    local ok, extensions = pcall(dofile, string.format("%s/%s",
        require("datastorage"):getDataDir(), "calibre-extensions.lua"))
    if ok then return extensions end
end


local CalibreExtensions = {
    user_overrides = getCustomConfig(),
    user_preferences = G_reader_settings:readSetting("calibre_wireless_extensions") or valid_ext,
}

function CalibreExtensions:get()
    if type(self.user_overrides) == "table" then
        return self.user_overrides
    else
        return self.user_preferences
    end
end

function CalibreExtensions:isCustom()
    return self.user_overrides ~= nil
end

function CalibreExtensions:sort()
    local UIManager = require("ui/uimanager")
    local SortWidget = require("ui/widget/sortwidget")
    local _ = require("gettext")
    local item_table = {}
    for i = 1, #self.user_preferences do
        item_table[i] = { text = self.user_preferences[i], label = self.user_preferences[i] }
    end

    local sort_item
    sort_item = SortWidget:new{
        title = _("Sort extensions"),
        item_table = item_table,
        callback = function()
            for i=1, #sort_item.item_table do
                self.user_preferences[i] = sort_item.item_table[i].label
            end
            G_reader_settings:saveSetting("calibre_wireless_extensions", self.user_preferences or valid_ext)
            UIManager:close(sort_item)
        end
    }
    UIManager:show(sort_item)
end

return CalibreExtensions
