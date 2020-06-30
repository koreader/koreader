local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Cache = require("cache")
local CacheItem = require("cacheitem")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local OPDSParser = require("ui/opdsparser")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local http = require('socket.http')
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require('ltn12')
local mime = require('mime')
local socket = require('socket')
local url = require('socket.url')
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

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
    calibre_name = _("Local calibre library"),

    catalog_type = "application/atom%+xml",
    search_type = "application/opensearchdescription%+xml",
    acquisition_rel = "^http://opds%-spec%.org/acquisition",
    image_rel = "http://opds-spec.org/image",
    thumbnail_rel = "http://opds-spec.org/image/thumbnail",

    formats = {
        ["application/epub+zip"] = "EPUB",
        ["application/fb2+zip"] = "FB2",
        ["application/pdf"] = "PDF",
        ["text/html"] = "HTML",
        ["text/plain"] = "TXT",
        ["application/x-mobipocket-ebook"] = "MOBI",
        ["application/x-mobi8-ebook"] = "AZW3",
        ["application/x-cbz"] = "CBZ",
        ["application/x-cbr"] = "CBR",
        ["application/djvu"] = "DJVU",
    },

    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    parent = nil,
}

function OPDSBrowser:init()
    local servers = G_reader_settings:readSetting("opds_servers")
    if not servers then -- If there are no saved servers, add some defaults
        servers = {
          {
            title = "Project Gutenberg",
            url = "http://m.gutenberg.org/ebooks.opds/?format=opds",
          },
          {
            title = "Project Gutenberg [Searchable]",
            url = "https://m.gutenberg.org/ebooks/search.mobile/?format=opds&query=%s",
            searchable = true,
          },
          {
             title = "Feedbooks",
             url = "http://www.feedbooks.com/publicdomain/catalog.atom",
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
             title = "Flibusta (Russian)",
             url = "http://www.flibusta.is/opds",
          },
          {
             title = "Flibusta [Ru] [Searchable]",
             url = "http://www.flibusta.is/opds/search?searchTerm=%s",
             searchable = true,
          },
          {
             title = "textos.info (Spanish)",
             url = "https://www.textos.info/catalogo.atom",
          },
          {
             title = "Gallica (French)",
             url = "https://gallica.bnf.fr/opds",
          },
          {
             title = "Gallica [Fr] [Searchable]",
             url = "https://gallica.bnf.fr/services/engine/search/opds?operation=searchRetrieve&query=(gallica all \"%s\")",
             searchable = true,
          }
        }
        G_reader_settings:saveSetting("opds_servers", servers)
    elseif servers[4] and servers[4].title == "Internet Archive" and servers[4].url == "http://bookserver.archive.org/catalog/"  then
        servers[4].url = "https://bookserver.archive.org"
    end
    self.item_table = self:genItemTableFromRoot()
    Menu.init(self) -- call parent's init()
end

function OPDSBrowser:addServerFromInput(fields)
    logger.info("input catalog", fields)
    local servers = G_reader_settings:readSetting("opds_servers") or {}
    local new_server = {
        title = fields[1],
        url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2]),
        searchable =  (fields[2]:match("%%s") and true or false),
        username = fields[3],
        password = fields[4],
    }
    table.insert(servers, new_server)
    G_reader_settings:saveSetting("opds_servers", servers)
    self:init()
end

function OPDSBrowser:editCalibreFromInput(fields)
    logger.dbg("input calibre server", fields)
    local calibre = G_reader_settings:readSetting("calibre_opds") or {}
    if fields[1] then
        calibre.host = fields[1]
    end
    if tonumber(fields[2]) then
        calibre.port = fields[2]
    end
    if fields[3] then
        calibre.username = fields[3]
    end
    if fields[4] then
        calibre.password = fields[4]
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
            {
                text = "",
                hint = _("Username (optional)"),
            },
            {
                text = "",
                hint = _("Password (optional)"),
                text_type = "password",
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
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
    }
    UIManager:show(self.add_server_dialog)
    self.add_server_dialog:onShowKeyboard()
end

function OPDSBrowser:editCalibreServer()
    local calibre = G_reader_settings:readSetting("calibre_opds") or {}
    self.add_server_dialog = MultiInputDialog:new{
        title = _("Edit local calibre host and port"),
        fields = {
            {
                --- @todo get IP address of current device
                text = calibre.host or "192.168.1.1",
                hint = _("calibre host"),
            },
            {
                text = calibre.port and tostring(calibre.port) or "8080",
                hint = _("calibre port"),
            },
            {
                text = calibre.username or "",
                hint = _("Username (optional)"),
            },
            {
                text = calibre.password or "",
                hint = _("Password (optional)"),
                text_type = "password",
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
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
    }
    UIManager:show(self.add_server_dialog)
    self.add_server_dialog:onShowKeyboard()
end

function OPDSBrowser:genItemTableFromRoot()
    local item_table = {}
    local added_servers = G_reader_settings:readSetting("opds_servers") or {}
    for _, server in ipairs(added_servers) do
        table.insert(item_table, {
            text = server.title,
            content = server.subtitle,
            url = server.url,
            username = server.username,
            password = server.password,
            deletable = true,
            editable = true,
            searchable = server.searchable,
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
            username = calibre_opds.username,
            password = calibre_opds.password,
            editable = true,
            deletable = false,
            searchable = false,
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

function OPDSBrowser:fetchFeed(item_url, username, password, method)
    local request, sink = {}, {}
    local parsed = url.parse(item_url)
    local hostname = parsed.host
    local auth = string.format("%s:%s", username, password)
    request['url'] = item_url
    request['method'] = method and method or "GET"
    request['sink'] = ltn12.sink.table(sink)
    request['headers'] = username and { Authorization = "Basic " .. mime.b64(auth), ["Host"] = hostname, } or  { ["Host"] = hostname, }
    logger.info("request", request)
    http.TIMEOUT = 10
    local httpRequest = http.request
    local code, headers = socket.skip(1, httpRequest(request))
    -- raise error message when network is unavailable
    if headers == nil then
        error(code)
    end
    if code == 200 then
        if method == "HEAD" then
            if headers["last-modified"] then
                return headers["last-modified"]
            else
                return
            end
        end
        local xml = table.concat(sink)
        if xml ~= "" then
            return xml
        end
    elseif method == "HEAD" then
        -- Don't show error messages when we check headers only.
        return
    elseif code == 301 then
        UIManager:show(InfoMessage:new{
            text = T(_("The catalog has been permanently moved. Please update catalog URL to '%1'."), BD.url(headers['Location'])),
        })
    elseif code == 401 then
        UIManager:show(InfoMessage:new{
            text = T(_("Authentication required for catalog. Please add a username and password.")),
        })
    elseif code == 403 then
        UIManager:show(InfoMessage:new{
            text = T(_("Failed to authenticate. Please check your username and password.")),
        })
    elseif code == 404 then
        UIManager:show(InfoMessage:new{
            text = T(_("Catalog not found.")),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog. Server response code %1."), code),
        })
    end
end

function OPDSBrowser:parseFeed(item_url, username, password)
    local feed
    local feed_last_modified = self:fetchFeed(item_url, username, password, "HEAD")
    local hash = "opds|catalog|" .. item_url
    if feed_last_modified then
        hash = hash .. feed_last_modified
    end

    local cache = CatalogCache:check(hash)
    if cache then
        feed = cache.feed
    else
        logger.dbg("cache", hash)
        feed = self:fetchFeed(item_url, username, password)
        if feed then
            CatalogCache:insert(hash, CatalogCacheItem:new{ feed = feed })
        end
    end
    if feed then
        return OPDSParser:parse(feed)
    end
end

function OPDSBrowser:getCatalog(item_url, username, password)
    local ok, catalog = pcall(self.parseFeed, self, item_url, username, password)
    if not ok and catalog and not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
        return
    elseif not ok and catalog then
        logger.info("cannot get catalog info from", item_url, catalog)
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog info from %1"), (BD.url(item_url) or "")),
        })
        return
    end

    if ok and catalog then
        return catalog
    end
end

function OPDSBrowser:genItemTableFromURL(item_url, username, password)
    local catalog = self:getCatalog(item_url, username, password)
    return self:genItemTableFromCatalog(catalog, item_url, username, password)
end

function OPDSBrowser:genItemTableFromCatalog(catalog, item_url, username, password)
    local item_table = {}
    if not catalog then
        return item_table
    end

    local feed = catalog.feed or catalog

    local function build_href(href)
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
    if username then
        item_table.username = username
    end
    if password then
        item_table.password = password
    end

    if not feed.entry then
        if #hrefs == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Catalog not found."),
            })
        end
        return item_table
    end

    for _, entry in ipairs(feed.entry) do
        local item = {}
        item.acquisitions = {}
        if entry.link then
            for _, link in ipairs(entry.link) do
                if link.type:find(self.catalog_type)
                        and (not link.rel
                             or link.rel == "subsection"
                             or link.rel == "http://opds-spec.org/subsection"
                             or link.rel == "http://opds-spec.org/sort/popular"
                             or link.rel == "http://opds-spec.org/sort/new") then
                    item.url = build_href(link.href)
                end
                if link.rel then
                    if link.rel:match(self.acquisition_rel) then
                        table.insert(item.acquisitions, {
                            type = link.type,
                            href = build_href(link.href),
                        })
                    elseif link.rel == self.thumbnail_rel then
                        item.thumbnail = build_href(link.href)
                    elseif link.rel == self.image_rel then
                        item.image = build_href(link.href)
                    end
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
            logger.info("Cannot handle title", entry.title)
        end
        item.text = title
        local author = "Unknown Author"
        if type(entry.author) == "table" and entry.author.name then
            author = entry.author.name
            if type(author) == "table" then
                if #author > 0 then
                    author = table.concat(author, ", ")
                else
                    -- we may get an empty table on https://gallica.bnf.fr/opds
                    author = nil
                end
            end
            if author then
                item.text = title .. "\n" .. author
            end
        end
        item.title = title
        item.author = author
        item.id = entry.id
        item.content = entry.content
        item.updated = entry.updated
        if username then
            item.username = username
        end
        if password then
            item.password = password
        end
        table.insert(item_table, item)
    end
    return item_table
end

function OPDSBrowser:updateCatalog(item_url, username, password)
    local menu_table = self:genItemTableFromURL(item_url, username, password)
    if #menu_table > 0 then
        self:switchItemTable(nil, menu_table)
        if self.page_num <= 1 then
            self:onNext()
        end
        return true
    end
end

function OPDSBrowser:appendCatalog(item_url, username, password)
    local new_table = self:genItemTableFromURL(item_url, username, password)
    if #new_table == 0 then return false end

    for _, item in ipairs(new_table) do
        table.insert(self.item_table, item)
    end
    self.item_table.hrefs = new_table.hrefs
    self:switchItemTable(nil, self.item_table, -1)
    return true
end

function OPDSBrowser.getCurrentDownloadDir()
    local lastdir = G_reader_settings:readSetting("lastdir")
    return G_reader_settings:readSetting("download_dir") or lastdir
end

function OPDSBrowser:downloadFile(item, format, remote_url)
    -- download to user selected directory or last opened dir
    local download_dir = self.getCurrentDownloadDir()
    local filename = util.getSafeFilename(item.author .. " - " .. item.title .. "." .. string.lower(format), download_dir)
    local local_path = download_dir .. "/" .. filename
    local_path = util.fixUtf8(local_path, "_")

    local function download()
        UIManager:scheduleIn(1, function()
            logger.dbg("downloading file", local_path, "from", remote_url)
            local parsed = url.parse(remote_url)
            http.TIMEOUT = 20

            local dummy, c = nil

            if parsed.scheme == "http" then
                dummy, c = http.request {
                    url         = remote_url,
                    sink        = ltn12.sink.file(io.open(local_path, "w")),
                    user        = item.username,
                    password    = item.password
                }
            elseif parsed.scheme == "https" then
                local auth = string.format("%s:%s", item.username, item.password)
                local hostname = parsed.host

                dummy, c = http.request {
                    url         = remote_url,
                    headers     = { Authorization = "Basic " .. mime.b64(auth), ["Host"] = hostname },
                    sink        = ltn12.sink.file(io.open(local_path, "w")),
                }
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("Invalid protocol:\n%1"), parsed.scheme),
                    timeout = 3,
                })
            end

            if c == 200 then
                logger.dbg("file downloaded to", local_path)
                if self.file_downloaded_callback then
                    self.file_downloaded_callback(local_path)
                end
            else
                UIManager:show(InfoMessage:new {
                    text = _("Could not save file to:\n") .. BD.filepath(local_path),
                    timeout = 3,
                })
            end
        end)

        UIManager:show(InfoMessage:new{
            text = _("Downloading may take several minutes…"),
            timeout = 1,
        })
    end

    if lfs.attributes(local_path, "mode") == "file" then
        UIManager:show(ConfirmBox:new {
            text = T(_("The file %1 already exists. Do you want to overwrite it?"), BD.filepath(local_path)),
            ok_text = _("Overwrite"),
            ok_callback = function()
                download()
            end,
        })
    else
        download()
    end
end

function OPDSBrowser:createNewDownloadDialog(path, buttons)
    self.download_dialog = ButtonDialogTitle:new{
        title = T(_("Download directory:\n%1\n\nDownload file type:"), BD.dirpath(path)),
        buttons = buttons
    }
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
                    -- append DOWNWARDS BLACK ARROW ⬇ U+2B07 to format
                    button.text = format .. "\xE2\xAC\x87"
                    button.callback = function()
                        self:downloadFile(item, format, acquisition.href)
                        UIManager:close(self.download_dialog)
                    end
                    table.insert(line, button)
                end
            elseif #acquisitions > downloadsperline then
                table.insert(line, {text=""})
            end
        end
        table.insert(buttons, line)
    end
    table.insert(buttons, {})
    -- set download directory button
    table.insert(buttons, {
        {
            text = _("Select another directory"),
            callback = function()
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        logger.info("set download directory to", path)
                        G_reader_settings:saveSetting("download_dir", path)
                        UIManager:nextTick(function()
                            UIManager:close(self.download_dialog)
                            self:createNewDownloadDialog(path, buttons)
                            UIManager:show(self.download_dialog)
                        end)
                    end,
                }:chooseDir()
            end,
        }
    })

    self:createNewDownloadDialog(self.getCurrentDownloadDir(), buttons)
    UIManager:show(self.download_dialog)
end

function OPDSBrowser:browse(browse_url, username, password)
    logger.dbg("Browse opds url", browse_url)
    table.insert(self.paths, {
        url = browse_url,
        username = username,
        password = password,
    })
    if not self:updateCatalog(browse_url, username, password) then
        table.remove(self.paths)
    end
end

function OPDSBrowser:browseSearchable(browse_url, username, password)
    self.search_server_dialog = InputDialog:new{
        title = _("Search OPDS catalog"),
        input = "",
        hint = _("Search string"),
        -- @translators: This is an input hint for something to search for in an OPDS catalog, namely a famous author everyone knows. It probably doesn't need to be localized, but this is just here in case another name or book title would be more appropriate outside of a European context.
        input_hint = _("Alexandre Dumas"),
        input_type = "string",
        description = _("%s in url will be replaced by your input"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.search_server_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(self.search_server_dialog)
                        local search = self.search_server_dialog:getInputText():gsub(" ", "+")
                        local searched_url = browse_url:gsub("%%s", search)
                        self:browse(searched_url, username, password)
                    end,
                },
            }
        },
    }
    UIManager:show(self.search_server_dialog)
    self.search_server_dialog:onShowKeyboard()
end

function OPDSBrowser:onMenuSelect(item)
    -- add catalog
    if item.callback then
        item.callback()
    -- acquisition
    elseif item.acquisitions and #item.acquisitions > 0 then
        logger.dbg("downloads available", item)
        self:showDownloads(item)
    -- navigation
    else
        if item.searchable then
            self:browseSearchable(item.url, item.username, item.password)
        else
            self:browse(item.url, item.username, item.password)
        end
    end
    return true
end

function OPDSBrowser:editServerFromInput(item, fields)
    logger.info("input catalog", fields)
    local servers = {}
    for _, server in ipairs(G_reader_settings:readSetting("opds_servers") or {}) do
        if server.title == item.text or server.url == item.url then
            server.title = fields[1]
            server.url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2])
            server.searchable =  (fields[2]:match("%%s") and true or false)
            server.username = fields[3]
            server.password = fields[4]
        end
        table.insert(servers, server)
    end
    G_reader_settings:saveSetting("opds_servers", servers)
    self:init()
end

function OPDSBrowser:editOPDSServer(item)
    logger.info("edit", item)
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
            {
                text = item.username or "",
                hint = _("Username (optional)"),
            },
            {
                text = item.password or "",
                hint = _("Password (optional)"),
                text_type = "password",
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
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
    }
    UIManager:show(self.edit_server_dialog)
    self.edit_server_dialog:onShowKeyboard()
end

function OPDSBrowser:deleteOPDSServer(item)
    logger.info("delete", item)
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
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            -- return to last path
            self:updateCatalog(path.url, path.username, path.password)
        else
            -- return to root path, we simply reinit opdsbrowser
            self:init()
        end
    end
    return true
end

function OPDSBrowser:onNext()
    -- self.page_num comes from menu.lua
    local page_num = self.page_num
    -- fetch more entries until we fill out one page or reach the end
    while page_num == self.page_num do
        local hrefs = self.item_table.hrefs
        if hrefs and hrefs.next then
            if not self:appendCatalog(hrefs.next, self.item_table.username, self.item_table.password) then
                break  -- reach end of paging
            end
        else
            break
        end
    end

    return true
end

return OPDSBrowser
