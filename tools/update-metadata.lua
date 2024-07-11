#!/usr/bin/env luajit

--[[
    tool to generate localized metadata for application stores.
    We currently support F-Droid(fastlane) and Flathub(appstream).

    usage: ./tools/update_metadata.lua
]]--

package.path = "frontend/?.lua;base/" .. package.path
local _ = require("gettext")

-- we can't require util here, some C libraries might not be available
local function htmlEscape(text)
    return text:gsub("[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;",
    })
end

local metadata = {
    summary = _("Ebook reader"),
    desc = {
        paragraphs = {
            _("KOReader is an ebook reader optimized for e-ink screens. It can open many formats and provides advanced text adjustments."),
            _("See below for a selection of its many features:"),
        },
        highlights = {
            _("Supports both fixed page formats (PDF, DjVu, CBT, CBZ) and reflowable e-book formats (EPUB, FB2, Mobi, DOC, CHM, TXT, HTML). Scanned PDF/DjVu documents can be reflowed. Special flow directions for reading double column PDFs and manga."),
            _("Multi-lingual user interface optimized for e-ink screens. Highly customizable reader view with complete typesetting options. Multi-lingual hyphenation dictionaries are bundled in."),
            _("Non-Latin script support for books, including the Hebrew, Arabic, Persian, Russian, Chinese, Japanese and Korean languages."),
            _("Unique Book Map and Page Browser features to navigate your book."),
            _("Special multi-page highlight mode with many local and online export options."),
            _("Can synchronize your reading progress across all your KOReader running devices."),
            _("Integrated with Calibre, Wallabag, Wikipedia, Google Translate and other content providers."),
        },
    },
    notes = {
        _ ("Release notes available on the link below"),
    },
    screenshots = {
        { image = "https://github.com/koreader/koreader-artwork/raw/master/koreader-menu-framed.png",
          default = true,
        },
        { image = "https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes-framed.png",
        },
        { image = "https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary-framed.png",
        }
    },
    keywords = {
        _("reader"),
        _("viewer"),
        _("dictionary"),
        _("wikipedia"),
        _("wallabag"),
        _("annotations"),
        -- don't translate formats
        "epub",
        "fb2",
        "pdf",
        "djvu",
    },

    -- appstream metadata that needs no translation
    component = [[
  <id>rocks.koreader.KOReader</id>

  <name>KOReader</name>
  <developer id="rocks.koreader">
    <name>KOReader Community</name>
  </developer>

  <metadata_license>CC0-1.0</metadata_license>
  <project_license>AGPL-3.0-only</project_license>

  <url type="homepage">https://koreader.rocks/</url>
  <url type="bugtracker">https://github.com/koreader/koreader/issues</url>
  <url type="faq">https://koreader.rocks/user_guide</url>
  <url type="translate">https://hosted.weblate.org/engage/koreader/</url>
  <url type="vcs-browser">https://github.com/koreader/koreader</url>
  <url type="contribute">https://github.com/koreader/koreader</url>

  <branding>
    <color type="primary" scheme_preference="light">#ffffff</color>
    <color type="primary" scheme_preference="dark">#303030</color>
  </branding>

  <requires>
    <display_length>360</display_length>
  </requires>

  <supports>
    <control>pointing</control>
    <control>keyboard</control>
    <control>gamepad</control>
  </supports>

  <recommends>
    <memory>1024</memory>
    <display_length compare="ge">600</display_length>
    <internet>always</internet>
    <control>touch</control>
  </recommends>

  <provides>
    <mediatype>application/epub+zip</mediatype>
    <mediatype>application/fb2</mediatype>
    <mediatype>application/fb3</mediatype>
    <mediatype>application/msword</mediatype>
    <mediatype>application/oxps</mediatype>
    <mediatype>application/pdf</mediatype>
    <mediatype>application/rtf</mediatype>
    <mediatype>application/tcr</mediatype>
    <mediatype>application/vnd.amazon.mobi8-ebook</mediatype>
    <mediatype>application/vnd.comicbook+tar</mediatype>
    <mediatype>application/vnd.comicbook+zip</mediatype>
    <mediatype>application/vnd.ms-htmlhelp</mediatype>
    <mediatype>application/vnd.openxmlformats-officedocument.wordprocessingml.document</mediatype>
    <mediatype>application/vnd.palm</mediatype>
    <mediatype>application/x-cbz</mediatype>
    <mediatype>application/x-chm</mediatype>
    <mediatype>application/x-fb2</mediatype>
    <mediatype>application/x-fb3</mediatype>
    <mediatype>application/x-mobipocket-ebook</mediatype>
    <mediatype>application/x-tar</mediatype>
    <mediatype>application/xhtml+xml</mediatype>
    <mediatype>application/xml</mediatype>
    <mediatype>application/zip</mediatype>
    <mediatype>image/djvu</mediatype>
    <mediatype>image/gif</mediatype>
    <mediatype>image/jp2</mediatype>
    <mediatype>image/jpeg</mediatype>
    <mediatype>image/jxr</mediatype>
    <mediatype>image/png</mediatype>
    <mediatype>image/svg+xml</mediatype>
    <mediatype>image/tiff</mediatype>
    <mediatype>image/vnd.djvu</mediatype>
    <mediatype>image/vnd.ms-photo</mediatype>
    <mediatype>image/x-djvu</mediatype>
    <mediatype>image/x-portable-arbitrarymap</mediatype>
    <mediatype>image/x-portable-bitmap</mediatype>
    <mediatype>text/html</mediatype>
    <mediatype>text/plain</mediatype>
  </provides>

  <launchable type="desktop-id">rocks.koreader.KOReader.desktop</launchable>

  <categories>
    <category>Office</category>
    <category>Viewer</category>
    <category>Literature</category>
  </categories>

  <content_rating type="oars-1.1"/>
]],
}

local updated_files = {}
local function writeFile(str, path)
    local f = io.open(path, "w")
    table.insert(updated_files, path)
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
    table.insert(locales, 1, "en")
    return locales
end

local locales = getLocales()

local function htmlDescription(lang)
    local lang = lang or "en"
    local desc = metadata.desc
    local t = {}
    _.changeLang(lang)
    for i, v in ipairs (desc.paragraphs) do
        table.insert(t, "<p>" .. htmlEscape(_(v)) .. "</p>")
    end
    table.insert(t, "<ul>")
    for i, v in ipairs(desc.highlights) do
        table.insert(t, "  <li>" .. htmlEscape(_(v)) .. "</li>")
    end
    table.insert(t, "</ul>")
    return table.concat(t, "\n")
end

local function tag(element, lang, str, pad)
    local offset = ""
    local pad = pad or 0
    if pad >= 1 then
        for i = 1, pad do
            offset = offset .. " "
        end
    end
    if lang == "en" then
        return string.format("%s<%s>%s</%s>",
            offset, element, str, element)
    else
        return string.format('%s<%s xml:lang="%s">%s</%s>',
            offset, element, lang, str, element)
    end
end

local function genAppstream()
    local metadata_file = "platform/common/koreader.metainfo.xml"
    print("Building appstream metadata, this might take a while...")
    local t = {}
    local desc = metadata.desc
    table.insert(t, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(t, '<!--Do not edit this file. Edit "tools/update-metadata.lua" instead-->')
    table.insert(t, '<component type="desktop-application">')
    table.insert(t, metadata.component)
    local orig, translated
    _.changeLang("en")
    orig = metadata.summary
    for __, lang in ipairs(locales) do
        _.changeLang(lang)
        translated = _(metadata.summary)
        if orig ~= translated or lang == "en" then
            table.insert(t, tag("summary", lang, htmlEscape(translated), 2))
        end
    end
    table.insert(t, '  <description>')
    for i, v in ipairs (desc.paragraphs) do
        _.changeLang("en")
        orig = v
        for __, lang in ipairs(locales) do
            _.changeLang(lang)
            translated = _(v)
            if orig ~= translated or lang == "en" then
                table.insert(t, tag("p", lang, htmlEscape(translated), 4))
            end
        end
    end
    table.insert(t, '    <ul>')
    for i, v in ipairs(desc.highlights) do
        _.changeLang("en")
        orig = v
        for __, lang in ipairs(locales) do
            _.changeLang(lang)
            translated = _(v)
            if orig ~= translated or lang == "en" then
                table.insert(t, tag("li", lang, htmlEscape(translated), 6))
            end
        end
    end
    table.insert(t, '    </ul>')
    table.insert(t, '  </description>')
    table.insert(t, '  <screenshots>')
    for i, v in ipairs(metadata.screenshots) do
        if v.default then
            table.insert(t, '    <screenshot type="default">')
        else
            table.insert(t, '    <screenshot>')
        end
        table.insert(t, tag("image", "en", v.image, 6))
        if v.caption then
            _.changeLang(en)
            orig = v.caption
            for __, lang in ipairs(locales) do
                _.changeLang(lang)
                translated = _(v.caption)
                if orig ~= translated or lang == "en" then
                    table.insert(t, tag("caption", lang, htmlEscape(translated), 6))
                end
            end
        end
        table.insert(t, '    </screenshot>')
    end
    table.insert(t, '  </screenshots>')

    table.insert(t, '  <keywords>')
    for i, v in ipairs(metadata.keywords) do
        _.changeLang(en)
        orig = v
        for __, lang in ipairs(locales) do
            _.changeLang(lang)
            translated = _(v)
            if orig ~= translated or lang == "en" then
                table.insert(t, tag("keyword", lang, htmlEscape(translated), 4))
            end
        end
    end
    table.insert(t, '  </keywords>')
    table.insert(t, [[  <releases>
    <release version="%%VERSION%%" date="%%DATE%%">
      <description>]])
    for i, v in ipairs(metadata.notes) do
        _.changeLang(en)
        orig = v
        for __, lang in ipairs(locales) do
            _.changeLang(lang)
            translated = _(v)
            if orig ~= translated or lang == "en" then
                table.insert(t, tag("p", lang, htmlEscape(translated), 8))
            end
        end
    end
    table.insert(t, [[      </description>
      <url>https://github.com/koreader/koreader/releases/tag/%%VERSION%%</url>
    </release>
  </releases>]])
    table.insert(t, '</component>')
    writeFile(table.concat(t, "\n"), metadata_file)
end


local function genFastlane()
    print("Building fastlane metadata")


    local short, full = "short_description.txt", "full_description.txt"
    local short_orig = metadata.summary
    local full_orig = htmlDescription()
    local short_translated, full_translated

    for __, lang in ipairs(locales) do
        _.changeLang(lang)
        if lang == "en" then
            metadata_dir = "metadata/en-US/"
            metadata_file = metadata_dir .. short
            writeFile(short_orig, metadata_file)
            metadata_file = metadata_dir .. full
            writeFile(full_orig, metadata_file)
        else
            metadata_dir = "metadata/" .. lang .. "/"
            short_translated = _(metadata.summary)
            full_translated = htmlDescription(lang)
            if short_orig ~= short_translated or full_orig ~= full_translated then
                os.execute('mkdir -p ' .. metadata_dir)
            end
            if short_orig ~= short_translated then
                metadata_file = metadata_dir .. short
                writeFile(short_translated, metadata_file)
            end
            if full_orig ~= full_translated then
                metadata_file = metadata_dir .. full
                writeFile(full_translated, metadata_file)
            end
        end
    end
end

genAppstream()
genFastlane()
print("All done! Updated files:")
print(table.concat(updated_files, "\n"))
