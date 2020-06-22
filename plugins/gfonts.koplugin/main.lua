local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local api = require("api")
local featured = require("featured")
local fontsearch = require("fontsearch")
local logger = require("logger")

local GFonts = WidgetContainer:new{
    name = "gfonts",
    is_doc_only = false,
    fonts = {},
    user_cache = DataStorage:getDataDir() .. "/cache/gbooks.lua",
    user_key = DataStorage:getSettingsDir() .. "gfonts-api.txt",
    timestamp_format = "%Y%m%d",
}

function GFonts:init()
    self.ui.menu:registerToMainMenu(self)
    api:init(self.user_key)
end

function GFonts:addToMainMenu(menu_items)
    menu_items.google_fonts = {
        text = "Google Fonts",
        callback = function()
            self:loadFonts()
            self:search()
        end,
    }
end

function GFonts:checkTimestamp(stamp)
    if not stamp then return false end
    local date = os.date(self.timestamp_format)
    if tonumber(date) > stamp + 7 then -- days between updates
        return false
    end
    return true
end

function GFonts:loadFonts()
    if #self.fonts > 0 and self.fonts.timestamp then
        if self:checkTimestamp(self.fonts.timestamp) then
            return true
        end
    end
    if util.fileExists(self.user_cache) then
        local ok, data = pcall(dofile, self.user_cache)
        if ok then
            if self:checkTimestamp(data.timestamp) then
                self.fonts = data
                return true
            end
        end
    end
    return self:getFonts()
end

function GFonts:getFonts()
    local fonts = {}
    fonts["timestamp"] = os.date(self.timestamp_format)
    fonts["list"] = api:getFonts()
    if #fonts.list > 0 then
        self.fonts = fonts
        util.dumpTable(self.fonts, self.user_cache)
        return true
    end
    return false
end

function GFonts:search()
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
    if not title then
        title = _("Search results")
    end
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
    self.search_menu:switchItemTable(title, t)
    UIManager:show(menu_container)
end

function GFonts:close()
    self.search_dialog:onClose()
    UIManager:close(self.search_dialog)
    if self.lastsearch then
        self:find(self.lastsearch)
    end
end

function GFonts:find(option)
    local catalog, catalog_name
    if self.lastsearch == "featured" then
        local recommended = featured:getFonts(self.fonts.list)
        logger.info(recommended)
        catalog = self:fontCatalog(recommended)
        catalog_name = _("Featured fonts")
    elseif self.lastsearch == "family" then
        catalog = self:fontCatalog(self.fonts.list)
        catalog_name = _("Fonts")
    else
        if self.lastsearch == "category" then
            catalog_name = _("Categories")
        elseif self.lastsearch == "language" then
            catalog_name = _("Languages")
        elseif self.lastsearch == "last" then
            catalog_name = _("Last modified")
        else
            logger.info(self.lastsearch)
            return
        end
        local results = fontsearch:sortBy(self.lastsearch, self.fonts.list)
        catalog = self:optionsCatalog(results, self.lastsearch)
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

function GFonts:optionsCatalog(t, option)
    local catalog = {}
    for item, ocurrence in pairs(t) do
        local entry = {}
        local name
        if option == "last" then
            if item == "last_year" then
                name = _("Last year")
            elseif item == "last_month" then
                name = _("Last month")
            elseif item == "last_week" then
                name = _("Last week")
            else
                name = _("Older")
            end
        else
            name = item
        end
        entry.text = string.format("%s (%d)", name, ocurrence)
        entry.callback = function()
            local fonts = self:fontCatalog(fontsearch:fontsBy(option, item, self.fonts.list))
            self:showResults(fonts, _("Fonts"))
        end
        table.insert(catalog, entry)
    end
    return catalog
end


function GFonts:downloadFont(family)
    logger.info("Prompt download " .. family)
    UIManager:show(ConfirmBox:new{
        text = T(_("Do you want to download %1"), family),
        ok_text = _("Download"),
        ok_callback = function()
            api:downloadFont(self.fonts.list, family)
        end,
    })
end

local function getFontInfo(font)
    local info = T(_("Font: %1\nVersion: %2\nCategory: %3\nLast modified: %4"),
        font.family, font.version, font.category, font.lastModified)
    local lang = _("Languages:")
    local langs = ""
    for i, subset in ipairs(font.subsets) do
        langs = i ~= 1 and langs .. ", " .. subset or subset
    end
    return info .. "\n" .. lang  .. " " .. langs
end

function GFonts:fontCatalog(t)
    logger.info(t)
    local catalog = {}
    for _, font in ipairs(t) do
        local entry = {}
        entry.text = font.family
        entry.info = getFontInfo(font)
        entry.callback = function()
            self:downloadFont(font.family)
        end
        table.insert(catalog, entry)
    end
    return catalog
end

return GFonts
