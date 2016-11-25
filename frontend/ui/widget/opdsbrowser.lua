local MultiInputDialog = require("ui/widget/multiinputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local LoginDialog = require("ui/widget/logindialog")
local OPDSParser = require("ui/opdsparser")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local CacheItem = require("cacheitem")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local url = require('socket.url')
local util = require("ffi/util")
local Cache = require("cache")
local DEBUG = require("dbg")
local _ = require("gettext")

local socket = require('socket')
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local mime = require('mime')

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
    acquisition_rel = "^http://opds%-spec%.org/acquisition",
    image_rel = "http://opds-spec.org/image",
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
        url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2]),
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
                hint = _("Catalog name"),
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
                hint = _("calibre host"),
            },
            {
                text = calibre.port and tostring(calibre.port) or "8080",
                hint = _("calibre port"),
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
    for _, server in ipairs(self.opds_servers) do
        table.insert(item_table, {
            text = server.title,
            content = server.subtitle,
            url = server.url,
        })
    end
    local added_servers = G_reader_settings:readSetting("opds_servers") or {}
    for _, server in ipairs(added_servers) do
        table.insert(item_table, {
            text = server.title,
            content = server.subtitle,
            url = server.url,
            deletable = true,
            editable = true,
        })
    end
    local calibre_opds = G_reader_settings:readSetting("calibre_opds") or {}
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

function OPDSBrowser:getBasicAuthentication(host)
    local authentications = G_reader_settings:readSetting("www-auth") or {}
    return authentications[host]
end

function OPDSBrowser:setBasicAuthentication(host, username, password)
    local authentications = G_reader_settings:readSetting("www-auth") or {}
    authentications[host] = {
        username = username,
        password = password,
    }
    G_reader_settings:saveSetting("www-auth", authentications)
end

function OPDSBrowser:getAuthorizationHeader(host)
    local auth = self:getBasicAuthentication(host)
    if auth then
        local authorization = auth.username .. ':' .. auth.password
        return {
            Authorization = "Basic " .. mime.b64(authorization),
        }
    end
end

function OPDSBrowser:fetchFeed(feed_url)
    local request, sink = {}, {}
    local parsed = url.parse(feed_url)
    request['url'] = feed_url
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    request['headers'] = self:getAuthorizationHeader(parsed.host)
    DEBUG("request", request)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local code, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error(code)
    end

    --DEBUG("response", code, headers, status)
    if code == 401 and status and status:find("Unauthorized") then
        self._coroutine = coroutine.running() or self._coroutine
        self:fetchWithLogin(parsed.host, function()
            return self:fetchFeed(feed_url)
        end)
        if coroutine.running() then
            local result = coroutine.yield()
            return result
        end
    else
        local xml = table.concat(sink)
        if xml ~= "" then
            --DEBUG("xml", xml)
            return xml
        end
    end
end

function OPDSBrowser:fetchWithLogin(host, callback)
    self.login_dialog = LoginDialog:new{
        title = _("Login to OPDS server"),
        username = "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:closeDialog()
                    end,
                },
                {
                    text = _("Login"),
                    enabled = true,
                    callback = function()
                        local username, password = self:getCredential()
                        self:setBasicAuthentication(host, username, password)
                        self:closeDialog()
                        UIManager:scheduleIn(0.5, function()
                            local res = callback()
                            if res then
                                coroutine.resume(self._coroutine, res)
                            end
                        end)
                    end,
                },
            },
        },
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.4,
    }

    self.login_dialog:onShowKeyboard()
    UIManager:show(self.login_dialog)
end

function OPDSBrowser:closeDialog()
    self.login_dialog:onClose()
    UIManager:close(self.login_dialog)
end

function OPDSBrowser:getCredential()
    return self.login_dialog:getCredential()
end

function OPDSBrowser:parseFeed(feed_url)
    local feed
    local hash = "opds|catalog|" .. feed_url
    local cache = CatalogCache:check(hash)
    if cache then
        feed = cache.feed
    else
        DEBUG("cache", hash)
        feed = self:fetchFeed(feed_url)
        if feed then
            CatalogCache:insert(hash, CatalogCacheItem:new{ feed = feed })
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
            text = util.template(
                _("Cannot get catalog info from %1"),
                (feed_url or "")
            ),
        })
        return
    end

    if ok and catalog then
        DEBUG("catalog", catalog)
        return catalog
    end
end

function OPDSBrowser:genItemTableFromURL(item_url)
    local catalog = self:getCatalog(item_url)
    return self:genItemTableFromCatalog(catalog, item_url)
end

function OPDSBrowser:genItemTableFromCatalog(catalog, item_url)
    local item_table = {}
    if catalog then
        local feed = catalog.feed or catalog
        local function build_href(href)
            --DEBUG("building href", item_url, href)
            return url.absolute(item_url, href)
        end
        local hrefs = {}
        if feed.link then
            for _, link in ipairs(feed.link) do
                if link.type ~= nil then
                    if link.type:find(self.catalog_type) or
                        link.type:find(self.search_type) then
                        if link.rel and link.href then
                            hrefs[link.rel] = build_href(link.href)
                        end
                    end
                end
            end
        end
        item_table.hrefs = hrefs
        if feed.entry then
            for _, entry in ipairs(feed.entry) do
                local item = {}
                item.acquisitions = {}
                if entry.link then
                    for _, link in ipairs(entry.link) do
                        if link.type:find(self.catalog_type) and (not link.rel or link.rel == "subsection" or link.rel == "http://opds-spec.org/sort/popular" or link.rel == "http://opds-spec.org/sort/new") then
                            item.url = build_href(link.href)
                        end
                        if link.rel and link.rel:match(self.acquisition_rel) then
                            table.insert(item.acquisitions, {
                                type = link.type,
                                --DEBUG("building acquisition url", link);
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
                if type(entry.title) == "string" then
                    title = entry.title
                elseif type(entry.title) == "table" then
                    if type(entry.title.type) == "string" and entry.title.div ~= "" then
                        title = entry.title.div
                    end
                end
                if title == "Unknown" then
                    DEBUG("Cannot handle title", entry.title)
                end
                local author = "Unknown Author"
                if type(entry.author) == "table" and entry.author.name then
                    author = entry.author.name
                end
                item.text = title
                item.title = title
                item.author = author
                item.id = entry.id
                item.content = entry.content
                item.updated = entry.updated
                table.insert(item_table, item)
            end
        end
    end
    return item_table
end

function OPDSBrowser:updateCatalog(item_table_url)
    local menu_table = self:genItemTableFromURL(item_table_url)
    if #menu_table > 0 then
        --DEBUG("menu table", menu_table)
        self:swithItemTable(nil, menu_table)
        if self.page_num <= 1 then
            self:onNext()
        end
        return true
    end
end

function OPDSBrowser:appendCatalog(item_table_url)
    local new_table = self:genItemTableFromURL(item_table_url)
    for _, item in ipairs(new_table) do
        table.insert(self.item_table, item)
    end
    self.item_table.hrefs = new_table.hrefs
    self:swithItemTable(nil, self.item_table, -1)
    return true
end

function OPDSBrowser:downloadFile(item, format, remote_url)
    -- download to user selected directory or last opened dir
    local lastdir = G_reader_settings:readSetting("lastdir")
    local download_dir = G_reader_settings:readSetting("download_dir") or lastdir
    local local_path = download_dir .. "/" .. item.author .. ' - ' .. item.title .. "." .. string.lower(format)
    DEBUG("downloading file", local_path, "from", remote_url)

    local parsed = url.parse(remote_url)
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local r, c, h = httpRequest{
        url = remote_url,
        headers = self:getAuthorizationHeader(parsed.host),
        sink = ltn12.sink.file(io.open(local_path, "w")),
    }

    if c == 200 then
        DEBUG("file downloaded to", local_path)
        UIManager:show(InfoMessage:new{
            text = _("File saved to:\n") .. local_path,
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
                            self:downloadFile(item, format, acquisition.href)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes…"),
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
                require("ui/downloadmgr"):new{
                    title = _("Choose download directory"),
                    onConfirm = function(path)
                        DEBUG("set download directory to", path)
                        G_reader_settings:saveSetting("download_dir", path)
                    end,
                }:chooseDir()
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
        })
        if not self:updateCatalog(item.url) then
            table.remove(self.paths)
        end
    end
    return true
end

function OPDSBrowser:editServerFromInput(item, fields)
    DEBUG("input catalog", fields)
    local servers = {}
    for _, server in ipairs(G_reader_settings:readSetting("opds_servers") or {}) do
        if server.title == item.text or server.url == item.url then
            server.title = fields[1]
            server.url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2])
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
    for _, server in ipairs(G_reader_settings:readSetting("opds_servers") or {}) do
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
            self:updateCatalog(path.url)
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
    local page_num = self.page_num
    while page_num == self.page_num and hrefs and hrefs.next do
        self:appendCatalog(hrefs.next)
    end
    return true
end

return OPDSBrowser
