local MultiInputDialog = require("ui/widget/multiinputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
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
    calibre_name = _("Local calibre catalog"),

    catalog_type = "application/atom%+xml",
    search_type = "application/opensearchdescription%+xml",
    acquisition_rel = "http://opds-spec.org/acquisition",
    thumbnail_rel = "http://opds-spec.org/image/thumbnail",

    formats = {
        ["application/epub+zip"] = "EPUB",
        ["application/fb2+zip"] = "FB2",
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

function OPDSBrowser:editCalibreFromInput(fields)
    DEBUG("input calibre server", fields)
    local calibre = G_reader_settings:readSetting("calibre_opds") or {}
    if fields[1] then
        calibre.host = fields[1]
    end
    if tonumber(fields[2]) then
        calibre.port = fields[2]
    end
    G_reader_settings:saveSetting("calibre_opds", calibre)
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

function OPDSBrowser:editCalibreServer()
    local calibre = G_reader_settings:readSetting("calibre_opds") or {}
    self.add_server_dialog = MultiInputDialog:new{
        title = _("Edit local calibre host and port"),
        fields = {
            {
                -- TODO: get IP address of current device
                text = calibre.host or "192.168.1.1",
                hint = _("Calibre host"),
            },
            {
                text = calibre.port and tostring(calibre.port) or "8080",
                hint = _("Calibre port"),
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
                    text = _("Apply"),
                    callback = function()
                        self.add_server_dialog:onClose()
                        UIManager:close(self.add_server_dialog)
                        self:editCalibreFromInput(MultiInputDialog:getFields())
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
            deletable = true,
            editable = true,
        })
    end
    local calibre_opds = G_reader_settings:readSetting("calibre_opds") or {}
    local calibre_callback = nil
    if not calibre_opds.host or not calibre_opds.port then
        table.insert(item_table, {
            text = self.calibre_name,
            callback = function()
                self:editCalibreServer()
            end,
            deletable = false,
        })
    else
        table.insert(item_table, {
            text = self.calibre_name,
            url = string.format("http://%s:%d/opds",
                calibre_opds.host, calibre_opds.port),
            editable = true,
            deletable = false,
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
        error(code)
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
        DEBUG("cannot get catalog info from", feed_url, catalog)
        UIManager:show(InfoMessage:new{
            text = _("Cannot get catalog info from ") .. feed_url,
        })
        return
    end

    if ok and catalog then
        DEBUG("catalog", catalog)
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
            elseif href:match("^//") then
                local parsed = url.parse(item_url or base_url)
                if parsed and parsed.scheme then
                    return parsed.scheme .. ":" .. href
                else
                    return "http:" .. href
                end
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
    self:swithItemTable(nil, self.item_table, -1)
    return true
end

function OPDSBrowser:downloadFile(title, format, remote_url)
    -- download to user selected directory or last opened dir
    local lastdir = G_reader_settings:readSetting("lastdir")
    local download_dir = G_reader_settings:readSetting("download_dir") or lastdir
    local local_path = download_dir .. "/" .. title .. "." .. string.lower(format)
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
        DEBUG("response", {r, c, h})
        UIManager:show(InfoMessage:new{
            text = _("Could not save file to:\n") .. local_path,
            timeout = 3,
        })
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
    -- set download directory button
    table.insert(buttons, {
        {
            text = _("Set download directory"),
            callback = function()
                local lastdir = G_reader_settings:readSetting("lastdir")
                local download_dir = G_reader_settings:readSetting("download_dir")
                local path_chooser = PathChooser:new{
                    title = _("Choose download directory"),
                    path = download_dir and (download_dir .. "/..") or lastdir,
                    onConfirm = function(path)
                        DEBUG("set download directory to", path)
                        G_reader_settings:saveSetting("download_dir", path)
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }
    })

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

function OPDSBrowser:editServerFromInput(item, fields)
    DEBUG("input catalog", fields)
    local servers = {}
    for i, server in ipairs(G_reader_settings:readSetting("opds_servers") or {}) do
        if server.title == item.text or server.url == item.url then
            server.title = fields[1]
            server.url = fields[2]
        end
        table.insert(servers, server)
    end
    G_reader_settings:saveSetting("opds_servers", servers)
    self:init()
end

function OPDSBrowser:editOPDSServer(item)
    DEBUG("edit", item)
    self.edit_server_dialog = MultiInputDialog:new{
        title = _("Edit OPDS catalog"),
        fields = {
            {
                text = item.text or "",
                hint = _("Catalog Name"),
            },
            {
                text = item.url or "",
                hint = _("Catalog URL"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.edit_server_dialog:onClose()
                        UIManager:close(self.edit_server_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self.edit_server_dialog:onClose()
                        UIManager:close(self.edit_server_dialog)
                        self:editServerFromInput(item, MultiInputDialog:getFields())
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
    }
    self.edit_server_dialog:onShowKeyboard()
    UIManager:show(self.edit_server_dialog)
end

function OPDSBrowser:deleteOPDSServer(item)
    DEBUG("delete", item)
    local servers = {}
    for i, server in ipairs(G_reader_settings:readSetting("opds_servers") or {}) do
        if server.title ~= item.text or server.url ~= item.url then
            table.insert(servers, server)
        end
    end
    G_reader_settings:saveSetting("opds_servers", servers)
    self:init()
end

function OPDSBrowser:onMenuHold(item)
    if item.deletable or item.editable then
        self.opds_server_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Edit"),
                        enabled = item.editable,
                        callback = function()
                            UIManager:close(self.opds_server_dialog)
                            if item.text ~= self.calibre_name then
                                self:editOPDSServer(item)
                            else
                                self:editCalibreServer(item)
                            end
                        end
                    },
                    {
                        text = _("Delete"),
                        enabled = item.deletable,
                        callback = function()
                            UIManager:close(self.opds_server_dialog)
                            self:deleteOPDSServer(item)
                        end
                    },
                },
            }
        }
        UIManager:show(self.opds_server_dialog)
        return true
    end
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
