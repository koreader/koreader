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
    local path = require("datastorage"):getDataDir()
    local ok, extensions = pcall(dofile, string.format("%s/%s", path, "calibre-extensions.lua"))
    if ok then return extensions end
end

local CalibreExtensions = {
    outputs = { "epub", "mobi", "docx", "fb2", "pdf", "txt" },
    default_output = G_reader_settings:readSetting("calibre_wireless_default_format") or "epub",
    user_overrides = getCustomConfig(),
}

function CalibreExtensions:get()
    if type(self.user_overrides) == "table" then
        return self.user_overrides
    else
        local sorted = {}
        sorted[1] = self.default_output
        for _, v in ipairs(valid_ext) do
            if v ~= self.default_output then
                sorted[#sorted+1] = v
            end
        end
        return sorted
    end
end

function CalibreExtensions:getInfo()
    local str = ""
    local t = self:get()
    for i, v in ipairs(t) do
        if i == #t then
            str = str .. v
        else
            str = str .. v .. ", "
        end
    end
    return str
end

function CalibreExtensions:isCustom()
    return self.user_overrides ~= nil
end

return CalibreExtensions
