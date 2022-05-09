#!/usr/bin/env luajit

-- utility to generate fastlane metadata for each translation
-- usage: ./tools/update_metadata.lua

package.path = "frontend/?.lua;" .. package.path

local _ = require("gettext")

local fastlane_short_description = _("Ebook reader with support for many formats like PDF, DjVu, EPUB, FB2, CBZ.")

local fastlane_full_description = _([[* portable: runs on embedded devices (Cervantes, Kindle, Kobo, PocketBook), Android and Linux computers. Developers can run a KOReader emulator in Linux and MacOS.

* multi-format documents: supports fixed page formats (PDF, DjVu, CBT, CBZ) and reflowable e-book formats (EPUB, FB2, Mobi, DOC, CHM, TXT). Scanned PDF/DjVu documents can also be reflowed with the built->

* full-featured reading: multi-lingual user interface with a highly customizable reader view and many typesetting options. You can set arbitrary page margins, override line spacing and choose external fo>

* integrated with calibre (search metadata, receive ebooks wirelessly, browse library via OPDS),  Wallabag, Wikipedia, Google Translate and other content providers.

* optimized for e-ink devices: custom UI without animation, with paginated menus, adjustable text contrast, and easy zoom to fit content or page in paged media.

* extensible via plugins

* and much more: look up words with StarDict dictionaries / Wikipedia, add your own online OPDS catalogs and RSS feeds, online over-the-air software updates, an FTP client, an SSH server, …
]])

local metadata = {
    ["short_description.txt"] = fastlane_short_description,
    ["full_description.txt"] = fastlane_full_description,
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

local function updateMetadata(str, path)
    local locales = getLocales()
    local count = { new = 0, updated = 0, not_translated = 0 }

    -- update english metadata first
    _.changeLang("en")
    local source = _(str)
    local metadata_file = "metadata/en-US" .. "/" .. path
    writeFile(source, metadata_file)

    -- update metadata for other languages if they're already translated.
    for __, lang in ipairs(locales) do
        _.changeLang(lang)
        local translation = _(str)
        if source ~= translation then
            local metadata_dir = "metadata/" .. lang
            metadata_file = metadata_dir .. "/" .. path
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
    print(path, "new", count.new, "updated", count.updated, "not translated", count.not_translated)
end

print("updating metadata for " .. #getLocales() .. " languages")
for file, str in pairs(metadata) do
    updateMetadata(str, file)
end
