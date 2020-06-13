--[[
    File formats supported by KOReader. These are reported when the device talks with calibre wireless server.

    Note that the server can allow or restrict file formats based on calibre configuration for each device.
    Optionally KOReader users can set their own supported formats to report to the server.
--]]

local user_path = require("datastorage"):getDataDir() .. "/calibre-extensions.lua"
local ok, extensions = pcall(dofile, user_path)

if ok then
    return extensions
else
    return {
        "azw",
        "cbz",
        "chm",
        "djv",
        "djvu",
        "doc",
        "docx",
        "epub",
        "fb2",
        "htm",
        "html",
        "md",
        "mobi",
        "pdb",
        "pdf",
        "prc",
        "rtf",
        "txt",
        "xhtml",
        "xps",
        "zip",
    }
end
