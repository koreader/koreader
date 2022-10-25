#!/usr/bin/env luajit

-- tool to generate localized metadata
--
-- metadata is fetched by F-Droid on each tagged release and used to update
-- https://f-droid.org/packages/org.koreader.launcher.fdroid/
--
-- usage: ./tools/update_metadata.lua
--
-- NOTE: title and screenshots are not translated. These resources are located in metadata/en-US

package.path = "frontend/?.lua;base/" .. package.path
local _ = require("gettext")

local metadata = {
    ["short_description.txt"] = _("Ebook reader with support for many formats like PDF, DjVu, EPUB, FB2, CBZ."),
    ["full_description.txt"] = _([[* portable: runs on embedded devices (Cervantes, Kindle, Kobo, PocketBook), Android and Linux computers. Developers can run a KOReader emulator in Linux and MacOS.

* multi-format documents: supports fixed page formats (PDF, DjVu, CBT, CBZ) and reflowable e-book formats (EPUB, FB2, Mobi, DOC, CHM, TXT). Scanned PDF/DjVu documents can also be reflowed with the built-in K2pdfopt library.

* full-featured reading: multi-lingual user interface with a highly customizable reader view and many typesetting options. You can set arbitrary page margins, override line spacing and choose external fonts and styles. It has multi-lingual hyphenation dictionaries bundled into the application.

* integrated with calibre (search metadata, receive ebooks wirelessly, browse library via OPDS),  Wallabag, Wikipedia, Google Translate and other content providers.

* optimized for e-ink devices: custom UI without animation, with paginated menus, adjustable text contrast, and easy zoom to fit content or page in paged media.

* extensible via plugins

* and much more: look up words with StarDict dictionaries / Wikipedia, add your own online OPDS catalogs and RSS feeds, online over-the-air software updates, an FTP client, an SSH server, …
]]),
}

local function isFile(str)
    local f = io.open(str, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function writeFile(str, path)
    local f = io.open(path, "w")
    if f then
        f:write(str)
        f:write("\n")
        f:close()
    end
end

local function isLocaleDir(str)
    for _, v in ipairs({"templates", "README.md", "LICENSE"}) do
        if str == v then return false end
    end
    return true
end

local function getLocales()
    local locales = {}
    local output = io.popen('ls l10n')
    if not output then return {} end
    for dir in output:lines() do
        if isLocaleDir(dir) then
            locales[#locales + 1] = dir
        end
    end
    output:close()
    return locales
end

----------------------------------------------------------------
print("updating metadata for " .. #getLocales() .. " languages")
for file, str in pairs(metadata) do
    local count = { new = 0, updated = 0, not_translated = 0 }

    -- update english
    _.changeLang("en")
    local source = _(str)
    local metadata_file = "metadata/en-US/" .. file
    writeFile(source, metadata_file)

    -- update translations
    for __, lang in ipairs(getLocales()) do
        _.changeLang(lang)
        local translation = _(str)
        if source ~= translation then
            local metadata_dir = "metadata/" .. lang
            metadata_file = metadata_dir .. "/" .. file
            os.execute('mkdir -p ' .. metadata_dir)
            if isFile(metadata_file) then
                count.updated = count.updated + 1
            else
                count.new = count.new + 1
            end
            writeFile(translation, metadata_file)
        else
            count.not_translated = count.not_translated + 1
        end
    end
    print(string.format("%s: %d new | %d updated | %d not translated",
        file, count.new, count.updated, count.not_translated))
end
