local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
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

local FontDownloader = WidgetContainer:new{
    name = "fontdownloader",
    is_doc_only = false,
    user_cache = DataStorage:getDataDir() .. "/cache/font-downloader.lua",
    timestamp_format = "%Y-%m-%d",

    -- specific of google fonts
    base_url = "https://www.googleapis.com/webfonts/v1/webfonts",
    user_key = DataStorage:getSettingsDir() .. "gfonts-api.txt",

    fonts = {},
    blacklist = {},
--[[
    blacklist = {
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
        ["display"]             = _("Display"),
        ["handwriting"]         = _("Handwriting"),
        ["monospace"]           = _("Monospace"),
        ["sans-serif"]          = _("Sans serif"),
        ["serif"]               = _("Serif"),
    },
    dates = {
        ["last_week"]           = _("Last week"),
        ["last_month" ]         = _("Last month"),
        ["last_year" ]          = _("Last year"),
        ["older"]               = _("Older"),
    },
    languages = {
        ["arabic"]              = _("Arabic"),
        ["bengali"]             = _("Bengali"),
        ["chinese-hongkong"]    = _("Hong Kong Chinese"),
        ["chinese-simplified"]  = _("Simplified Chinese"),
        ["chinese-traditional"] = _("Traditional Chinese"),
        ["cyrillic"]            = _("Cyrillic"),
        ["devanagari"]          = _("Devanagari"),
        ["greek"]               = _("Greek"),
        ["gujarati"]            = _("Gujarati"),
        ["gurmukhi"]            = _("Gurmukhi"),
        ["hebrew"]              = _("Hebrew"),
        ["japanese"]            = _("Japanese"),
        ["kannada"]             = _("Kannada"),
        ["khmer"]               = _("Khmer"),
        ["korean"]              = _("Korean"),
        ["latin"]               = _("Latin"),
        ["malayalam"]           = _("Malayalam"),
        ["myanmar"]             = _("Myanmar"),
        ["oriya"]               = _("Oriya"),
        ["sinhala"]             = _("Sinhala"),
        ["tamil"]               = _("Tamil"),
        ["telugu"]              = _("Telugu"),
        ["thai"]                = _("Thai"),
        ["tibetan"]             = _("Tibetan"),
        ["vietnamese"]          = _("Vietnamese"),
    },
    variants = {
        ["regular"]             = "regular",
        ["italic"]              = "italic",
        ["500"]                 = "medium",
        ["500italic"]           = "medium-italic",
        ["700"]                 = "bold",
        ["700italic"]           = "bold-italic",
    },
}

function FontDownloader:init()
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

function FontDownloader:addToMainMenu(menu_items)
    -- plugin settings
    menu_items.font_downloader = {
        text = _("Font downloader"),
        sub_item_table = {
            {
                text = _("Set download location"),
                callback = function()
                    self:setFontDir()
                end,
            },
            {
                text = _("Sync font index"),
                callback = function()
                    self.fonts = self:fontTable()
                end,
            },
        }
    }
    -- inject in font menu for CRE documents
    if self.ui.document and self.ui.document.provider == "crengine" then
        local menu = menu_items.change_font.sub_item_table[1].sub_item_table
        for _, entry in ipairs(menu) do
            if entry.id and entry.id == "fontdownloader" then
                return
            end
        end
        local position = #menu - 1 -- above fallback fonts
        table.insert(menu, position, {
            id = "fontdownloader",
            text = _("Download more fonts"),
            callback = function()
                self:frontpage()
            end,
        })
    end
end

function FontDownloader:onFontDownloadLookup()
    self:frontpage()
    return true
end

function FontDownloader:onNetworkConnected()
    if self.pending_action then
        -- execute pending actions
        self.pending_action()
        self.pending_action = nil
    end
end

-- frontpage for font lookup
--
-- the function schedules itself as a pending action if it fails for some reason,
-- so we keep a retry count to avoid "fail" loops
function FontDownloader:frontpage(retry_count)
    if retry_count and retry_count > 3 then
        logger.warn("Too many retries. Giving up")
        return
    end

    -- returns true if font table is loaded or cached (with valid timestamp)
    local ok_table = function()
        if #self.fonts > 0 and self.fonts.timestamp then
            if fontsearch.timestampOk(self.fonts.timestamp) then
                return true
            end
        end
        if util.fileExists(self.user_cache) then
            local ok, data = pcall(dofile, self.user_cache)
            if ok then
                if fontsearch.timestampOk(data.timestamp) then
                    self.fonts = data
                    return true
                end
            end
        end
    end

    -- check font dir
    if not self.font_dir then
        local font_dir = self:getFontDir()
        if not font_dir then
            -- failed: needs inbox dir
            retry_count = (retry_count or 0) + 1
            local callback = function() self:frontpage(retry_count) end
            self:setFontDir(callback)
            return nil, "no font dir"
        end
        self.font_dir = font_dir
    end

    -- check font table
    local ready = ok_table()
    if not ready then
        retry_count = (retry_count or 0) + 1
        local callback = function() self:frontpage(retry_count) end
        if not NetworkMgr:isConnected() then
            self.pending_action = callback
            NetworkMgr:promptWifiOn()
            return nil, "network is down"
        end
        self.fonts = self:fontTable()
        UIManager:nextTick(callback)
        return nil, "downloading font index"
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
                        self.lastsearch = "featured"
                        self:close()
                    end,
                },
                {
                    text = _("Last modified"),
                    callback = function()
                        self.lastsearch = "last"
                        self:close()
                    end,
                },
            },
            {
                {
                    text = _("Category"),
                    callback = function()
                        self.lastsearch = "category"
                        self:close()
                    end,
                },
                {
                    text = _("Language"),
                    callback = function()
                        self.lastsearch = "language"
                        self:close()
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
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
    return true
end

function FontDownloader:showResults(t, title)
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

function FontDownloader:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end
    UIManager:show(InfoMessage:new{
        text = item.info,
    })
end

function FontDownloader:close()
    self.search_dialog:onClose()
    UIManager:close(self.search_dialog)
    if self.lastsearch then
        self:find()
    end
end

function FontDownloader:find()
    if not self.lastsearch then
        return
    end
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
        if self.search_value == "" then
            catalog_name = _("Fonts")
        else
            catalog_name = T(_("Fonts that match %1"), self.search_value)
        end
        catalog = self:fontCatalog(fontsearch.fontsByMatch(s, self.fonts.list, self.search_value))
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

function FontDownloader:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end
    UIManager:show(InfoMessage:new{
        text = item.info,
    })
end

function FontDownloader:fontCatalog(t)
    if not t then return end
    local catalog = {}
    local info = function(font)
        local info = T(_("Font: %1\nVersion: %2\nCategory: %3\nLast modified: %4"),
            font.family, font.version, font.category, font.lastModified)
        local lang = _("Languages:")
        for index, subset in ipairs(font.subsets) do
            -- check if current subset is an extension of the previous one
            if subset:match("-ext$") then
                subset = "+"
                lang = lang .. subset
            else
                local id = self.languages[subset]
                if id then subset = id:lower() end
                lang = index ~= 1 and lang .. ", " .. subset or lang .. " " .. subset
            end
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

function FontDownloader:optionsCatalog(t, option)
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

function FontDownloader:fontTable()
    -- get font table from google
    UIManager:show(InfoMessage:new{
        text = _("Downloading font index"),
        timeout = 1,
    })
    UIManager:forceRePaint()
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

function FontDownloader:promptDownload(t, family)
    if not t or not family then return end
    if not NetworkMgr:isConnected() then
        local callback = function() self:promptDownload(t, family) end
        self.pending_action = callback
        NetworkMgr:promptWifiOn()
        return
    end
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

function FontDownloader:downloadFont(t, family)
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
                        sink = ltn12.sink.file(io.open(self.font_dir .. "/" .. font_name, "w")),
                    }
                    Device.setIgnoreInput(false)
                end
            end
        end
    end
end

function FontDownloader:getFontDir()
    local font_dir = G_reader_settings:readSetting("font_inbox_dir")
    if not font_dir and (Device:isAndroid() or Device:isDesktop() or Device:isEmulator()) then
        font_dir = require("frontend/ui/elements/font_settings"):getPath()
    elseif not font_dir then
        font_dir = os.getenv("EXT_FONT_DIR")
    end
    return font_dir
end

function FontDownloader:setFontDir(callback)
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

return FontDownloader
