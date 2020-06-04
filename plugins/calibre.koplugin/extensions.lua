-- tell calibre which extensions are supported by the client
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
