local MultiInputDialog = require("ui/widget/multiinputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local lfs = require("libs/libkoreader-lfs")
local OPDSParser = require("ui/opdsparser")
local NetworkMgr = require("ui/networkmgr")
local UIManager = require("ui/uimanager")
local CacheItem = require("cacheitem")
local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local Device = require("ui/device")
local url = require('socket.url')
local util = require("ffi/util")
local Cache = require("cache")
local DEBUG = require("dbg")
local _ = require("gettext")
local ffi = require("ffi")

local socket = require('socket')
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')

local CatalogCacheItem = CacheItem:new{
    size = 1024,  -- fixed size for catalog item
}

-- cache catalog parsed from feed xml
local CatalogCache = Cache:new{
    max_memsize = 20*1024, -- keep only 20 cache items
    current_memsize = 0,
    cache = {},
    cache_order = {},
}

local OPDSBrowser = Menu:extend{
    opds_servers = {},
    catalog_type = "application/atom%+xml",
    search_type = "application/opensearchdescription%+xml",
    acquisition_rel = "http://opds-spec.org/acquisition",
    thumbnail_rel = "http://opds-spec.org/image/thumbnail",

    formats = {
        ["application/epub+zip"] = "EPUB",
        ["application/pdf"] = "PDF",
        ["text/plain"] = "TXT",
        ["application/x-mobipocket-ebook"] = "MOBI",
        ["application/x-mobi8-ebook"] = "AZW3",
    },

    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    parent = nil,
}

function OPDSBrowser:init()
    self.item_table = self:genItemTableFromRoot(self.opds_servers)
    Menu.init(self) -- call parent's init()
end

function OPDSBrowser:addServerFromInput(fields)
    DEBUG("input catalog", fields)
    local servers = G_reader_settings:readSetting("opds_servers") or {}
    table.insert(servers, {
        title = fields[1],
        url = fields[2],
    })
    G_reader_settings:saveSetting("opds_servers", servers)
    self:init()
end

function OPDSBrowser:addNewCatalog()
    self.add_server_dialog = MultiInputDialog:new{
        title = _("Add OPDS catalog"),
        fields = {
            {
                text = "",
                hint = _("Catalog Name"),
            },
            {
                text = "",
                hint = _("Catalog URL"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.add_server_dialog:onClose()
                        UIManager:close(self.add_server_dialog)
                    end
                },
                {
                    text = _("Add"),
                    callback = function()
                        self.add_server_dialog:onClose()
                        UIManager:close(self.add_server_dialog)
                        self:addServerFromInput(MultiInputDialog:getFields())
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
    }
    self.add_server_dialog:onShowKeyboard()
    UIManager:show(self.add_server_dialog)
end

function OPDSBrowser:genItemTableFromRoot()
    local item_table = {}
    for i, server in ipairs(self.opds_servers) do
        table.insert(item_table, {
            text = server.title,
            content = server.subtitle,
            url = server.url,
            baseurl = server.baseurl,
        })
    end
    local added_servers = G_reader_settings:readSetting("opds_servers") or {}
    for i, server in ipairs(added_servers) do
        table.insert(item_table, {
            text = server.title,
            content = server.subtitle,
            url = server.url,
            baseurl = server.baseurl,
        })
    end
    table.insert(item_table, {
        text = _("Add new OPDS catalog"),
        callback = function()
            self:addNewCatalog()
        end,
    })
    return item_table
end

function OPDSBrowser:fetchFeed(feed_url)
    local headers, request, sink = {}, {}, {}
    local parsed = url.parse(feed_url)
    request['url'] = feed_url
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    DEBUG("request", request)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local code, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    local xml = table.concat(sink)
    if xml ~= "" then
        --DEBUG("xml", xml)
        return xml
    end
end

function OPDSBrowser:parseFeed(feed_url)
    local feed = nil
    local hash = "opds|catalog|" .. feed_url
    local cache = CatalogCache:check(hash)
    if cache then
        feed = cache.feed
    else
        DEBUG("cache", hash)
        feed = self:fetchFeed(feed_url)
        if feed then
            local cache = CatalogCacheItem:new{
                feed = feed
            }
            CatalogCache:insert(hash, cache)
        end
    end
    if feed then
        return OPDSParser:parse(feed)
    end
end

function OPDSBrowser:getCatalog(feed_url)
    local ok, catalog = pcall(self.parseFeed, self, feed_url)
    -- prompt users to turn on Wifi if network is unreachable
    if not ok and catalog and catalog:find("Network is unreachable") then
        NetworkMgr:promptWifiOn()
        return
    elseif not ok and catalog then
        DEBUG(catalog)
        return
    end

    if ok and catalog then
        --DEBUG("catalog", catalog)
        return catalog
    end
end

function OPDSBrowser:genItemTableFromURL(item_url, base_url)
    local item_table = {}
    local catalog = self:getCatalog(item_url or base_url)
    if catalog then
        local feed = catalog.feed or catalog
        local function build_href(href)
            if href:match("^http") then
                return href
            elseif base_url then
                return base_url .. "/" .. href
            elseif item_url then
                local parsed = url.parse(item_url)
                -- update item url with href parts(mostly path and query)
                for k, v in pairs(url.parse(href) or {}) do
                    if k == "path" then
                        v = "/" .. v
                    end
                    parsed[k] = v
                end
                return url.build(parsed)
            end
        end
        local hrefs = {}
        if feed.link then
            for i, link in ipairs(feed.link) do
                if link.type:find(self.catalog_type) or
                    link.type:find(self.search_type) then
                    if link.rel and link.href then
                        hrefs[link.rel] = build_href(link.href)
                    end
                end
            end
        end
        item_table.hrefs = hrefs
        if feed.entry then
            for i, entry in ipairs(feed.entry) do
                local item = {}
                item.baseurl = base_url
                item.acquisitions = {}
                if entry.link then
                    for i, link in ipairs(entry.link) do
                        if link.type:find(self.catalog_type) then
                            item.url = build_href(link.href)
                        end
                        if link.rel == self.acquisition_rel then
                            table.insert(item.acquisitions, {
                                type = link.type,
                                href = build_href(link.href),
                            })
                        end
                        if link.rel == self.thumbnail_rel then
                            item.thumbnail = build_href(link.href)
                        end
                        if link.rel == self.image_rel then
                            item.image = build_href(link.href)
                        end
                    end
                end
                local title = "Unknown"
                local title_type = type(entry.title)
                if type(entry.title) == "string" then
                    title = entry.title
                elseif type(entry.title) == "table" then
                    if entry.title.type == "text/xhtml" then
                        title = entry.title.div or title
                    end
                end
                if title == "Unknown" then
                    DEBUG("Cannot handle title", entry.title)
                end
                item.text = title
                item.title = title
                item.id = entry.id
                item.content = entry.content
                item.updated = entry.updated
                table.insert(item_table, item)
            end
        end
    end
    return item_table
end

function OPDSBrowser:updateCatalog(url, baseurl)
    local menu_table = self:genItemTableFromURL(url, baseurl)
    if #menu_table > 0 then
        --DEBUG("menu table", menu_table)
        self:swithItemTable(nil, menu_table)
        return true
    end
end

function OPDSBrowser:appendCatalog(url, baseurl)
    local new_table = self:genItemTableFromURL(url, baseurl)
    for i, item in ipairs(new_table) do
        table.insert(self.item_table, item)
    end
    self.item_table.hrefs = new_table.hrefs
    self:swithItemTable(nil, self.item_table)
    return true
end

function OPDSBrowser:downloadFile(title, format, remote_url)
    -- download to last opened dir or OPDS_DOWNLOADS
    local lastdir = G_reader_settings:readSetting("lastdir")
    if OPDS_DOWNLOADS and (string.sub(OPDS_DOWNLOADS,1,5)=="/mnt/") then -- prevent to write on the root of the device for Kindle and Kobo. 
                                                                         -- TO DO: Add check for Android. util.isAndroid always returns true on my Kobo, so it is useless.
        lastdir = OPDS_DOWNLOADS
    end
    if string.sub(lastdir,string.len(lastdir)) ~= "/" then
        lastdir = lastdir .. "/"
        pcall(lfs.mkdir(lastdir))
        if not lfs.attributes(lastdir,"mode")=="directory" then
            lastdir = G_reader_settings:readSetting("lastdir") .. "/"
        end
    end
    local local_path = lastdir .. title .. "." .. string.lower(format)
    DEBUG("downloading file", local_path, "from", remote_url)

    local parsed = url.parse(remote_url)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local r, c, h = httpRequest{
        url = remote_url,
        sink = ltn12.sink.file(io.open(local_path, "w")),
    }

    if c == 200 then
        DEBUG("file downloaded successfully to", local_path)
        UIManager:show(InfoMessage:new{
            text = _("File successfully saved to:\n") .. local_path,
            timeout = 3,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Could not save file to:\n") .. local_path,
            timeout = 3,
        })
        DEBUG("response", {r, c, h})
    end
end

function OPDSBrowser:showDownloads(item)
    local acquisitions = item.acquisitions
    local downloadsperline = 2
    local lines = math.ceil(#acquisitions/downloadsperline)
    local buttons = {}
    for i = 1, lines do
        local line = {}
        for j = 1, downloadsperline do
            local button = {}
            local index = (i-1)*downloadsperline + j
            local acquisition = acquisitions[index]
            if acquisition then
                local format = self.formats[acquisition.type]
                if format then
                    button.text = format
                    button.callback = function()
                        UIManager:scheduleIn(1, function()
                            self:downloadFile(item.title, format, acquisition.href)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes..."),
                            timeout = 3,
                        })
                    end
                    table.insert(line, button)
                end
            end
        end
        table.insert(buttons, line)
    end

    self.download_dialog = ButtonDialog:new{
        buttons = buttons
    }
    UIManager:show(self.download_dialog)
end

function OPDSBrowser:onMenuSelect(item)
    -- add catalog
    if item.callback then
        item.callback()
    -- acquisition
    elseif item.acquisitions and #item.acquisitions > 0 then
        DEBUG("downloads available", item)
        self:showDownloads(item)
    -- navigation
    else
        table.insert(self.paths, {
            url = item.url,
            baseurl = item.baseurl,
        })
        if not self:updateCatalog(item.url, item.baseurl) then
            table.remove(self.paths)
        end
    end
    return true
end

function OPDSBrowser:onReturn()
    DEBUG("return to last page catalog")
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            -- return to last path
            self:updateCatalog(path.url, path.baseurl)
        else
            -- return to root path, we simply reinit opdsbrowser
            self:init()
        end
    end
    return true
end

function OPDSBrowser:onNext()
    DEBUG("fetch next page catalog")
    local hrefs = self.item_table.hrefs
    if hrefs and hrefs.next then
        self:appendCatalog(hrefs.next)
    end
    return true
end

return OPDSBrowser
