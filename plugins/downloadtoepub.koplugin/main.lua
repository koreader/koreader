--[[--
    Download URLs as EPUBs

    @module koplugin.DownloadToEPUB
--]]--
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen
local Size = require("ui/size")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("frontend/util")
local T = FFIUtil.template
local _ = require("gettext")
-- Gazette Modules
local EpubBuildDirector = require("libs/gazette/epubbuilddirector")
local WebPage = require("libs/gazette/resources/webpage")
local ResourceAdapter = require("libs/gazette/resources/webpageadapter")
local Epub = require("libs/gazette/epub/epub")
local History = require("epubhistory")
local HistoryView = require("epubhistoryview")

local DownloadToEpub = WidgetContainer:new{
    name = "Download to EPUB",
    download_directory = ("%s/%s/"):format(DataStorage:getFullDataDir(), "EPUB Downloads")
}

local EpubBuilder = {
    output_directory = nil,
}

function DownloadToEpub:init()
    self.settings = self.readSettings()
    if self.settings.data.download_directory then
        self.download_directory = self.settings.data.download_directory
    end
    self:createDownloadDirectoryIfNotExists()
    self.ui.menu:registerToMainMenu(self)
    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("30_downloadtoepub", function(this, link_url)
            return {
                text = _("Download to EPUB"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("DownloadEpubFromUrl", link_url))
                end,
                show_in_dialog_func = function()
                    return true
                end
            }
        end)
    end
end

function DownloadToEpub:addToMainMenu(menu_items)
    menu_items.downloadtoepub = {
        text = _("Download to EPUB"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Go to EPUB downloads"),
                callback = function()
                    self:goToDownloadDirectory()
                end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text_func = function()
                            local path = filemanagerutil.abbreviate(self.download_directory)
                            return T(_("Set download directory (%1)"), BD.dirpath(path))
                        end,
                        keep_menu_open = true,
                        callback = function() self:setDownloadDirectory() end,
                    },
                }
            },
            {
                text = _("About"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "DownloadToEpub lets you download external links as EPUBs to your device."
                    })
                end,
            },
        }
    }
    local history_view = HistoryView:new{}
    local last_download_item = history_view:getLastDownloadButton(function(history_item)
            self:maybeOpenEpub(history_item['download_path'])
    end)
    local history_menu_items = history_view:getMenuItems(function(history_item)
            self:maybeOpenEpub(history_item['download_path'])
    end)
    if last_download_item then table.insert(menu_items.downloadtoepub.sub_item_table, 2, last_download_item) end
    if history_menu_items then table.insert(menu_items.downloadtoepub.sub_item_table, 3, history_menu_items[1]) end
end

function DownloadToEpub:maybeOpenEpub(file_path)
    if util.pathExists(file_path) then
        logger.dbg("DownloadToEpub: Opening " .. file_path)
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("SetupShowReader"))
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file_path)
    else
        logger.dbg("DownloadToEpub: Couldn't open " .. file_path .. ". It's been moved or deleted.")
        self:showRedownloadPrompt(file_path)
    end
end

function DownloadToEpub:readSettings()
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "downloadtoepub.lua")
    if not settings.data.downloadtoepub then
        settings.data.downloadtoepub = {}
    end
    return settings
end

function DownloadToEpub:saveSettings()
    local temp_settings = {
        download_directory = self.download_directory
    }
    self.settings:saveSetting("downloadtoepub", temp_settings)
    self.settings:flush()
end

function DownloadToEpub:setDownloadDirectory()
    local downloadmgr = require("ui/downloadmgr")
    downloadmgr:new{
        onConfirm = function(path)
            self.download_directory = path
            self:saveSettings()
        end
    }:chooseDir()
end

function DownloadToEpub:goToDownloadDirectory()
    local FileManager = require("apps/filemanager/filemanager")
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(self.download_directory)
    else
        FileManager:showFiles(self.download_directory)
    end
end

function DownloadToEpub:createDownloadDirectoryIfNotExists()
    if not util.pathExists(self.download_directory) then
        logger.dbg("DownloadToEpub: Creating path (" .. self.download_directory .. ")")
        lfs.mkdir(self.download_directory)
    end
end

function DownloadToEpub:onDownloadEpubFromUrl(link_url)
    local prompt
    prompt = ConfirmBox:new{
        text = T(_("Download to EPUB? \n\nLink: %1"), link_url),
        ok_text = _("Yes"),
        ok_callback = function()
            UIManager:close(prompt)
            self:downloadEpubWithUi(link_url, function(file_path, err)
                if err then
                    UIManager:show(InfoMessage:new{ text = T(_("Error downloading EPUB: %1", err)) })
                else
                    local history = History:new{}
                    history:init()
                    logger.dbg("DownloadToEpub: Maybe deleting from history " .. link_url)
                    history:remove(link_url) -- link might have already been downloaded. If so, remove the history item.
                    logger.dbg("DownloadToEpub: Adding to history " .. link_url .. " " .. file_path)
                    history:add(link_url, file_path)
                    logger.dbg("DownloadToEpub: Finished downloading epub to " .. file_path)
                    self:showReadPrompt(file_path)
                end
            end)
        end,
    }
    UIManager:show(prompt)
end

function DownloadToEpub:downloadEpubWithUi(link_url, callback)
    local info = InfoMessage:new{ text = ("Downloading... " .. link_url) }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    NetworkMgr:runWhenOnline(function()
        local epub_builder = EpubBuilder:new{
            output_directory = self.download_directory,
        }
        local file_path, err = epub_builder:buildFromUrl(link_url)
        callback(file_path, err)
    end)
end

function DownloadToEpub:showRedownloadPrompt(file_path) -- supply this with a directory?
    local prompt

    local history = History:new{}
    history:init()
    local history_item = history:find(file_path)

    if history_item then
        prompt = MultiConfirmBox:new{
            text = T(_("Couldn't open EPUB! \n\nFile has been moved since download (%1)\n\nInitially downloaded from (%2)\n\nWhat would you like to do?"),
                    file_path,
                    history_item.url),
            choice1_text = _("Redownload EPUB"),
            choice1_callback = function()
                logger.dbg("DownloadToEpub: Redownloading " .. history_item.url)
                UIManager:close(prompt)
                self:onDownloadEpubFromUrl(history_item.url)
            end,
            choice2_text = _("Delete from history"),
            choice2_callback = function()
                logger.dbg("DownloadToEpub: Deleting from history " .. history_item.url)
                history:remove(history_item.url)
                UIManager:close(prompt)
            end,
        }
    else
        prompt = InfoMessage:new{
            text = _("Couldn't open EPUB! EPUB has been deleted or moved since being downloaded."),
            show_icon = false,
            timeout = 10,
        }
    end
    UIManager:show(prompt)
end

function DownloadToEpub:showReadPrompt(file_path)
    local prompt = ConfirmBox:new{
        text = _("EPUB downloaded. Would you like to read it now?"),
        ok_text = _("Open EPUB"),
        ok_callback = function()
            logger.dbg("DownloadToEpub: Opening " .. file_path)
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("SetupShowReader"))
            UIManager:close(prompt)
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(file_path)
        end,
    }
    UIManager:show(prompt)
end

function EpubBuilder:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function EpubBuilder:buildFromUrl(url)
    logger.dbg("DownloadToEpub: Begin download of " .. url .. " outputting to " .. self.output_directory)

    local info = InfoMessage:new{ text = _("Getting webpage…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    local webpage, err = self:createWebpage(url)

    if not webpage then
        logger.dbg("DownloadToEpub: " .. err)
        return false, err
    end

    info = InfoMessage:new{ text = _("Building EPUB…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    local epub = Epub:new{}
    epub:addFromList(ResourceAdapter:new(webpage))
    epub:setTitle(webpage.title)
    epub:setAuthor("DownloadToEpub")

    local epub_path = ("%s%s.epub"):format(self.output_directory, util.getSafeFilename(epub.title))
    local build_director, err = self:createBuildDirector(epub_path)
    if not build_director then
        logger.dbg("DownloadToEpub: " .. err)
        return false, err
    end

    info = InfoMessage:new{ text = _("Writing to device…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    logger.dbg("DownloadToEpub: Writing EPUB to " .. epub_path)
    local path_to_epub, err = build_director:construct(epub)
    if not path_to_epub then
        logger.dbg("DownloadToEpub: " .. err)
        return false, err
    end

    return path_to_epub
end

function EpubBuilder:createWebpage(url)
    local webpage, err = WebPage:new({
            url = url,
    })

    if err then
        return false, err
    end

    webpage:build()

    return webpage
end

function EpubBuilder:createBuildDirector(epub_path)
    local build_director, err = EpubBuildDirector:new()

    if not build_director then
        return false, err
    end

    local success, err = build_director:setDestination(epub_path)

    if not success then
        return false, err
    end

    return build_director
end

return DownloadToEpub
