local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local ltn12 = require("ltn12")
local https = require("ssl.https")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local featured = require("featured")
local fontsearch = require("fontsearch")

local GFonts = WidgetContainer:new{
    name = "gfonts",
    is_doc_only = false,
    base_url = "https://www.googleapis.com/webfonts/v1/webfonts",
    user_cache = DataStorage:getDataDir() .. "/cache/gbooks.lua",
    user_key = DataStorage:getSettingsDir() .. "gfonts-api.txt",
    timestamp_format = "%Y%m%d",
    fonts = {},
    blacklist = {},
--[[    blacklist = {
        "Noto Sans", "Noto Sans HK", "Noto Sans JP", "Noto Sans KR", "Noto Sans SC", "Noto Sans TC",
        "Noto Serif", "Noto Serif HK", "Noto Serif JP", "Noto Serif KR", "Noto Serif SC", "Noto Serif TC",
    },
--]]
    recommended = {
        "Bitter",
        "Crimson Text",
        "Gentium Book Basic",
        "Ibarra Real Nova",
        "Lit3rata",
        "Merriweather",
        "Source Serif Pro",
    },
    categories = {
        ["display"]            = _("Display"),
        ["handwriting"]        = _("Handwriting"),
        ["monospace"]          = _("Monospace"),
        ["sans-serif"]         = _("Sans serif"),
        ["serif"]              = _("Serif"),
    },
    dates = {
        ["last_week"]          = _("Last week"),
        ["last_month" ]        = _("Last month"),
        ["last_year" ]         = _("Last year"),
        ["older"]              = _("Older"),
    },
    languages = {
        ["arabic"]             = _("Arabic"),
        ["bengali"]            = _("Bengali"),
        ["chinese-simplified"] = _("Simplified Chinese"),
        ["cyrillic"]           = _("Cyrillic"),
        ["cyrillic-ext"]       = _("Cyrillic (extended)"),
        ["devanagari"]         = _("Devanagari"),
        ["greek"]              = _("Greek"),
        ["greek-ext"]          = _("Greek (extended)"),
        ["gujarati"]           = _("Gujarati"),
        ["gurmukhi"]           = _("Gurmukhi"),
        ["hebrew"]             = _("Hebrew"),
        ["japanese"]           = _("Japanese"),
        ["kannada"]            = _("Kannada"),
        ["khmer"]              = _("Khmer"),
        ["korean"]             = _("Korean"),
        ["latin"]              = _("Latin"),
        ["latin-ext"]          = _("Latin (extended)"),
        ["malayalam"]          = _("Malayalam"),
        ["myanmar"]            = _("Myanmar"),
        ["oriya"]              = _("Oriya"),
        ["sinhala"]            = _("Sinhala"),
        ["tamil"]              = _("Tamil"),
        ["telugu"]             = _("Telugu"),
        ["thai"]               = _("Thai"),
        ["tibetan"]            = _("Tibetan"),
        ["vietnamese"]         = _("Vietnamese"),
    },
    variants = {
        ["regular"]            = "regular",
        ["italic"]             = "italic",
        ["500"]                = "medium",
        ["500italic"]          = "medium-italic",
        ["700"]                = "bold",
        ["700italic"]          = "bold-italic",
    },
}

function GFonts:init()
    self.ui.menu:registerToMainMenu(self)
    local keyfile = io.open(self.user_key, "r")
    if keyfile then
        local key = keyfile:read("*a")
        keyfile:close()
        self.api_key = key
        return
    end
    self.api_key = "AIzaSyDQZaihK8Lb7jJ3DYyrQrpyyJF7tyvrqAs"
end

function GFonts:addToMainMenu(menu_items)
    menu_items.google_fonts = {
        text = _("Download fonts"),
        callback = function()
            self:frontpage()
        end,
    }

    menu_items.google_fonts_settings = {
        text = _("Set download location"),
        callback = function()
            self:setFontDir()
        end,
    }
end

-- frontpage for font lookup
function GFonts:frontpage()
    -- get path to download fonts
    if not self.font_dir then
        local font_dir = self:getFontDir()
        -- no path, prompt for inbox dir and call this again
        if not font_dir then
            local callback = function() self:frontpage() end
            self:setFontDir(callback)
            return
        end
        self.font_dir = font_dir
    end
    -- returns true if modification time is equal or less than 7 days old
    local ok_stamp = function(timestamp)
        if not timestamp then return false end
        local current = os.date(self.timestamp_format)
        if tonumber(current) > timestamp + 7 then return false end
        return true
    end

    -- make sure fonts are ready before showing the UI
    local ready = false
    if #self.fonts > 0 and self.fonts.timestamp then
        if ok_stamp(self.fonts.timestamp) then
            ready = true
        end
    end
    if not ready and util.fileExists(self.user_cache) then
        -- load font list from cache
        local ok, data = pcall(dofile, self.user_cache)
        if ok then
            if ok_stamp(data.timestamp) then
                self.fonts = data
                ready = true
            end
        end
    end

    if not ready then
        -- generate a new font table, this is slow as it relies on network sources
        self.fonts = self:fontTable()

        -- this shouldn't happen, to-do: warn the user something failed?
        if not self.fonts or not self.fonts.list then
            return
        end
    end

    -- ready to show the UI
    self.search_dialog = InputDialog:new{
        title = T(_("Search in %1 fonts"), #self.fonts.list),
        input = self.search_value,
        buttons = {
            {
                {
                    text = _("Featured"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "featured"
                        self:close()
                    end,
                },
                {
                    text = _("Last modified"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "last"
                        self:close()
                    end,
                },
            },
            {
                {
                    text = _("Category"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "category"
                        self:close()
                    end,
                },
                {
                    text = _("Language"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "language"
                        self:close()
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = nil
                        self:close()
                    end,
                },
                {
                    text = _("Family"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "family"
                        self:close()
                    end,
                },
            },
        },
        width = math.floor(Screen:getWidth() * 0.8),
        height = math.floor(Screen:getHeight() * 0.2),
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function GFonts:showResults(t, title)
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new {
        width = Screen:getWidth() - 15,
        height = Screen:getHeight() - 15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    table.sort(t, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:switchItemTable(title, t)
    UIManager:show(menu_container)
end

function GFonts:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end
    UIManager:show(InfoMessage:new{
        text = item.info,
    })
end

function GFonts:close()
    self.search_dialog:onClose()
    UIManager:close(self.search_dialog)
    if self.lastsearch then
        self:find()
    end
end

function GFonts:find()
    if not self.lastsearch then return end
    local s = self.lastsearch
    local catalog, catalog_name
    if s == "featured" then
        catalog_name = _("Featured fonts")
        local featured_fonts = {}
        for _, name in ipairs(self.recommended) do
            for _, font in ipairs(self.fonts.list) do
                if font.family == name then
                    table.insert(featured_fonts, #featured_fonts + 1, font)
                end
            end
        end
        catalog = self:fontCatalog(featured_fonts)
    elseif s == "family" then
        catalog_name = _("Fonts")
        catalog = self:fontCatalog(self.fonts.list)
    elseif s == "category" or s == "language" or s == "last" then
        if s == "category" then
            catalog_name = _("Categories")
        elseif s == "language" then
            catalog_name = _("Languages")
        elseif s == "last" then
            catalog_name = _("Last modified")
        end
        catalog = self:optionsCatalog(fontsearch.frequenceOf(s, self.fonts.list), s)
    end
    if catalog and catalog_name then
        self:showResults(catalog, catalog_name)
    end
end

function GFonts:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end
    UIManager:show(InfoMessage:new{
        text = item.info,
    })
end

function GFonts:fontCatalog(t)
    if not t then return end
    local catalog = {}
    local info = function(font)
        local info = T(_("Font: %1\nVersion: %2\nCategory: %3\nLast modified: %4"),
            font.family, font.version, font.category, font.lastModified)
        local lang = _("Languages:")
        for index, subset in ipairs(font.subsets) do
            local id = self.languages[subset]
            subset = id:lower() or subset
            lang = index ~= 1 and lang .. ", " .. subset or lang .. " " .. subset
        end
        return info .. "\n" .. lang
    end
    for _, font in ipairs(t) do
        local entry = {}
        entry.text = font.family
        entry.info = info(font)
        entry.callback = function()
            self:promptDownload(t, font.family)
        end
        table.insert(catalog, entry)
    end
    return catalog
end

function GFonts:optionsCatalog(t, option)
    if not t or not option then return end
    local catalog = {}
    for item, ocurrence in pairs(t) do
        local name
        if option == "last" then
            name = self.dates[item]
        elseif option == "language" then
            name = self.languages[item]
        elseif option == "category" then
            name = self.categories[item]
        end
        local entry = {}
        entry.text = string.format("%s (%d)", name or item, ocurrence)
        entry.callback = function()
            local callback = self:fontCatalog(fontsearch.fontsByMatch(option, self.fonts.list, item))
            self:showResults(callback, T(_("%1 fonts"), name or item))
        end
        table.insert(catalog, entry)
    end
    return catalog
end

function GFonts:fontTable()
    -- get font table from google
    local rapidjson = require("rapidjson")
    local socket = require("socket")
    local request, sink = {}, {}
    request.url = self.base_url .. "?key=" .. self.api_key
    request.method = "GET"
    request.sink = ltn12.sink.table(sink)
    https.TIMEOUT = 10
    local _, headers, status = socket.skip(1, https.request(request))
    if headers == nil then
        return {}, "Network is unreachable"
    elseif status ~= "HTTP/1.1 200 OK" then
        return {}, status
    end
    local t = rapidjson.decode(table.concat(sink))
    if not t or not t.items or type(t.items) ~= "table" then
        return {}, "Can't decode server response"
    end
    local fonts = t.items
    -- remove blacklisted entries
    for _, family in ipairs(self.blacklist) do
        for index, font in ipairs(fonts) do
            if family == font.family then
                table.remove(fonts, index)
            end
        end
    end
    -- add our own fonts to the table
    for _, font in ipairs(featured.getFonts()) do
        table.insert(fonts, #fonts + 1, font)
    end
    -- dump generated font table and timestamp to disk
    local font_table = {}
    font_table["timestamp"] = os.date(self.timestamp_format)
    font_table["list"] = fonts
    self.fonts = font_table
    util.dumpTable(self.fonts, self.user_cache)
end

function GFonts:promptDownload(t, family)
    if not t or not family then return end
    UIManager:show(ConfirmBox:new{
        text = T(_("Download %1?"), family),
        ok_text = _("Download"),
        ok_callback = function()
            UIManager:nextTick(function()
                self:downloadFont(t, family)
            end)
        end,
    })
end

function GFonts:downloadFont(t, family)
    for index, font in ipairs(t) do
        if font.family == family then
            for key, value in pairs(self.variants) do
                local font_url = t[index].files[key]
                if font_url then
                    https.TIMEOUT = 10
                    Device.setIgnoreInput(true) -- Avoid ANRs on android, no-op for other platforms
                    local font_name = string.format("%s-%s.%s", family, value, font.format or "ttf")
                    logger.info("downloading", font_name, "to", self.font_dir)
                    UIManager:show(InfoMessage:new{
                        text = T(_("Downloading %1"), font_name),
                        timeout = 2,
                    })
                    UIManager:forceRePaint()
                    https.request{
                        url = font_url,
                        sink = ltn12.sink.file(io.open(font_name, "w")),
                    }
                    Device.setIgnoreInput(false)
                end
            end
        end
    end
end

function GFonts:getFontDir()
    local font_dir = G_reader_settings:readSetting("font_inbox_dir")
    if not font_dir and (Device:isAndroid() or Device:isDesktop() or Device:isEmulator()) then
        font_dir = require("frontend/ui/elements/font_settings"):getPath()
    elseif not font_dir then
        font_dir = os.getenv("EXT_FONT_DIR")
    end
    return font_dir
end

function GFonts:setFontDir(callback)
    require("ui/downloadmgr"):new{
        onConfirm = function(inbox)
            G_reader_settings:saveSetting("font_inbox_dir", inbox)
            self.font_dir = inbox
            if callback then
                callback()
            end
        end,
    }:chooseDir()
end

return GFonts
