local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local LuaSettings = require("luasettings")
local OPDSBrowser = require("opdsbrowser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local logger = require("logger")
local Device = require("device")

local OPDS = WidgetContainer:extend{
    name = "opds",
    opds_settings_file = DataStorage:getSettingsDir() .. "/opds.lua",
    settings = nil,
    servers = nil,
    downloads = nil,
    default_servers = {
        {
            title = "Project Gutenberg",
            url = "https://m.gutenberg.org/ebooks.opds/?format=opds",
        },
        {
            title = "Standard Ebooks",
            url = "https://standardebooks.org/feeds/opds",
        },
        {
            title = "ManyBooks",
            url = "http://manybooks.net/opds/index.php",
        },
        {
            title = "Internet Archive",
            url = "https://bookserver.archive.org/",
        },
        {
            title = "textos.info (Spanish)",
            url = "https://www.textos.info/catalogo.atom",
        },
        {
            title = "Gallica (French)",
            url = "https://gallica.bnf.fr/opds",
        },
    },
}

function OPDS:init()
    self.settings = LuaSettings:open(self.opds_settings_file)
    if next(self.settings.data) == nil then
        self.updated = true -- first run, force flush
    end
    self.servers = self.settings:readSetting("servers", self.default_servers)
    self.downloads = self.settings:readSetting("downloads", {})
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function OPDS:onDispatcherRegisterActions()
    Dispatcher:registerAction("opds_show_catalog",
        {category="none", event="ShowOPDSCatalog", title=_("OPDS Catalog"), filemanager=true,}
    )
end

function OPDS:addToMainMenu(menu_items)
    if not self.ui.document then -- FileManager menu only
        menu_items.opds = {
            text = _("OPDS"),
            sub_item_table = {
                {
                    text = _("OPDS catalog"),
                    keep_menu_open = true,
                    callback = function()
                        self:onShowOPDSCatalog()
                    end,
                },
                {
                    text = _("Automatic OPDS download"),
                    keep_menu_open = true,
                    sub_item_table = self:getOPDSDownloadMenu(),
                },
            },
        }
    end
end

function OPDS:getOPDSDownloadMenu()
    return {
        {
            text = _("OPDS sync"),
            checked_func = function()
                return G_reader_settings:isTrue("opds_sync")
            end,
            callback = function()
                G_reader_settings:toggle("opds_sync")
            end,
        },
        {
            text = _("Perform sync"),
            callback = function()
                self:checkSyncDownload(self.servers)
            end,
        },
        {
            text = _("Set OPDS sync directory"),
            callback = function()
                self:setSyncDir()
            end,
        },
    }
end


function OPDS:checkSyncDownload()
    for _, item in ipairs(self.servers) do
        if item.sync then
            local lastDownload = OPDSBrowser:syncDownload(item)
            if lastDownload then
                logger.dbg("Updating opds last download for server" .. item.title)
                self:appendFieldToCatalog(item, "lastDownload", lastDownload)
            else
            end
        end
    end
end


function OPDS:appendFieldToCatalog(item, newName, newValue)
    item[newName] = newValue
    self.updated = true
end

function OPDS:setSyncDir()
    local force_chooser_dir
    if Device:isAndroid() then
        force_chooser_dir = Device.home_dir
    end

    require("ui/downloadmgr"):new{
        onConfirm = function(inbox)
            logger.info("set opds sync directory", inbox)
            G_reader_settings:saveSetting("opds_sync_dir", inbox)
        end,
    }:chooseDir(force_chooser_dir)
end

function OPDS:onShowOPDSCatalog()
    self.opds_browser = OPDSBrowser:new{
        servers = self.servers,
        downloads = self.downloads,
        title = _("OPDS catalog"),
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        _manager = self,
        file_downloaded_callback = function(file)
            self:showFileDownloadedDialog(file)
        end,
        close_callback = function()
            if self.opds_browser.download_list then
                self.opds_browser.download_list.close_callback()
            end
            UIManager:close(self.opds_browser)
            self.opds_browser = nil
            if self.last_downloaded_file then
                if self.ui.file_chooser then
                    local pathname = util.splitFilePathName(self.last_downloaded_file)
                    self.ui.file_chooser:changeToPath(pathname, self.last_downloaded_file)
                end
                self.last_downloaded_file = nil
            end
        end,
    }
    UIManager:show(self.opds_browser)
end

function OPDS:showFileDownloadedDialog(file)
    self.last_downloaded_file = file
    UIManager:show(ConfirmBox:new{
        text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(file)),
        ok_text = _("Read now"),
        ok_callback = function()
            self.last_downloaded_file = nil
            self.opds_browser.close_callback()
            if self.ui.document then
                self.ui:switchDocument(file)
            else
                self.ui:openFile(file)
            end
        end,
    })
end

function OPDS:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

return OPDS
