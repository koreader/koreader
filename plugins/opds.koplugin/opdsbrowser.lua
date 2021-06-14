local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Cache = require("cache")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local OPDSParser = require("opdsparser")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

-- cache catalog parsed from feed xml
local CatalogCache = Cache:new{
    -- Make it 20 slots, with no storage space constraints
    slots = 20,
}

local OPDSBrowser = Menu:extend{
    opds_servers = G_reader_settings:readSetting("opds_servers", {
        {
            title = "Project Gutenberg",
            url = "https://m.gutenberg.org/ebooks.opds/?format=opds",
        },
        {
            title = "Feedbooks",
            url = "https://catalog.feedbooks.com/catalog/public_domain.atom",
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
    }),
    calibre_name = _("Local calibre library"),
    calibre_opds = G_reader_settings:readSetting("calibre_opds", {}),

    catalog_type = "application/atom%+xml",
    search_type = "application/opensearchdescription%+xml",
    search_template_type = "application/atom%+xml",
    acquisition_rel = "^http://opds%-spec%.org/acquisition",
    image_rel = "http://opds-spec.org/image",
    thumbnail_rel = "http://opds-spec.org/image/thumbnail",

    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    parent = nil,
}

function OPDSBrowser:init()
    self.item_table = self:genItemTableFromRoot()
    self.catalog_title = nil
    Menu.init(self) -- call parent's init()
end

function OPDSBrowser:addServerFromInput(fields)
    logger.info("New OPDS catalog input:", fields)
    local new_server = {
        title = fields[1],
        url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2]),
        searchable =  (fields[2]:match("%%s") and true or false),
        username = fields[3] ~= "" and fields[3] or nil,
        -- Allow empty passwords
        password = fields[4],
    }
    table.insert(self.opds_servers, new_server)
    self:init()
end

function OPDSBrowser:editCalibreFromInput(fields)
    logger.dbg("Edit calibre server input:", fields)
    if fields[1] then
        self.calibre_opds.host = fields[1]
    end
    if tonumber(fields[2]) then
        self.calibre_opds.port = fields[2]
    end
    if fields[3] and fields[3] ~= "" then
        self.calibre_opds.username = fields[3]
    else
        self.calibre_opds.username = nil
    end
    if fields[4] then
        self.calibre_opds.password = fields[4]
    else
        self.calibre_opds.password = nil
    end
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
    self.add_server_dialog = MultiInputDialog:new{
        title = _("Edit local calibre host and port"),
        fields = {
            {
                --- @todo get IP address of current device
                text = self.calibre_opds.host or "192.168.1.1",
                hint = _("calibre host"),
            },
            {
                text = self.calibre_opds.port and tostring(self.calibre_opds.port) or "8080",
                hint = _("calibre port"),
            },
            {
                text = self.calibre_opds.username or "",
                hint = _("Username (optional)"),
            },
            {
                text = self.calibre_opds.password or "",
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
    for _, server in ipairs(self.opds_servers) do
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
    if not self.calibre_opds.host or not self.calibre_opds.port then
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
                self.calibre_opds.host, self.calibre_opds.port),
            username = self.calibre_opds.username,
            password = self.calibre_opds.password,
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
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url      = item_url,
        method   = method and method or "GET",
        -- Explicitly specify that we don't support compressed content. Some servers will still break RFC2616 14.3 and send crap instead.
        headers  = {
            ["Accept-Encoding"] = "identity",
        },
        sink     = ltn12.sink.table(sink),
        user     = username,
        password = password,
    }
    logger.info("Request:", request)
    local code, headers = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
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
    elseif code == 302 and item_url:match("^https") and headers.location:match("^http[^s]") then
        UIManager:show(InfoMessage:new{
            text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."), BD.url(item_url), BD.url(headers.location)),
            icon = "notice-warning",
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
    elseif code == 406 then
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog. Server refuses to serve uncompressed content.")),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog. Server response code %1."), code),
        })
    end
end

function OPDSBrowser:parseFeed(item_url, username, password)
    local feed_last_modified = self:fetchFeed(item_url, username, password, "HEAD")
    local hash = "opds|catalog|" .. item_url
    if feed_last_modified then
        hash = hash .. "|" .. feed_last_modified
    end

    local feed = CatalogCache:check(hash)
    if feed then
        logger.dbg("Cache hit for", hash)
    else
        logger.dbg("Cache miss for", hash)
        feed = self:fetchFeed(item_url, username, password)
        if feed then
            logger.dbg("Caching", hash)
            CatalogCache:insert(hash, feed)
        end
    end
    if feed then
        return OPDSParser:parse(feed)
    end
end

function OPDSBrowser:getCatalog(item_url, username, password)
    local ok, catalog = pcall(self.parseFeed, self, item_url, username, password)
    if not ok and catalog then
        logger.info("Cannot get catalog info from", item_url or "nil", catalog)
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog info from %1"), (item_url and BD.url(item_url) or "nil")),
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

function OPDSBrowser:getSearchTemplate(osd_url, username, password)
    -- parse search descriptor
    local search_descriptor = self:parseFeed(osd_url, username, password)
    if search_descriptor and search_descriptor.OpenSearchDescription and search_descriptor.OpenSearchDescription.Url then
        for _, candidate in ipairs(search_descriptor.OpenSearchDescription.Url) do
            if candidate.type and candidate.template and candidate.type:find(self.search_template_type) then
                return candidate.template:gsub("{searchTerms}", "%%s")
            end
        end
    end
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
                if link.type:find(self.catalog_type) then
                    if link.rel and link.href then
                        hrefs[link.rel] = build_href(link.href)
                    end
                end
                if link.type:find(self.search_type) then
                    if link.href then
                        local stpl = self:getSearchTemplate(build_href(link.href), username, password)
                        -- The OpenSearchDescription/Url template field might *also* be a relative path...
                        stpl = build_href(stpl)
                        -- insert the search item
                        local item = {}
                        item.acquisitions = {}
                        item.text = "Search"
                        item.callback = function()
                            self:browseSearchable(stpl, username, password)
                        end

                        table.insert(item_table, item)
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
                text = _("Failed to parse the catalog."),
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
                item.text = title .. " - " .. author
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
        self:switchItemTable(self.catalog_title, menu_table)
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
    self:switchItemTable(self.catalog_title, self.item_table, -1)
    return true
end

function OPDSBrowser.getCurrentDownloadDir()
    local lastdir = G_reader_settings:readSetting("lastdir")
    return G_reader_settings:readSetting("download_dir") or lastdir
end

function OPDSBrowser:downloadFile(item, filetype, remote_url)
    -- Download to user selected folder or last opened folder.
    local download_dir = self.getCurrentDownloadDir()

    local filename = item.title .. "." .. filetype
    if item.author then
        filename = item.author .. " - " .. filename
    end

    filename = util.getSafeFilename(filename, download_dir)
    local local_path = download_dir .. "/" .. filename
    local_path = util.fixUtf8(local_path, "_")

    local function download()
        UIManager:scheduleIn(1, function()
            logger.dbg("Downloading file", local_path, "from", remote_url)
            local parsed = url.parse(remote_url)

            local code, headers
            if parsed.scheme == "http" or parsed.scheme == "https" then
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
                code, headers = socket.skip(1, http.request {
                    url         = remote_url,
                    headers     = {
                        ["Accept-Encoding"] = "identity",
                    },
                    sink        = ltn12.sink.file(io.open(local_path, "w")),
                    user        = item.username,
                    password    = item.password,
                })
                socketutil:reset_timeout()
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("Invalid protocol:\n%1"), parsed.scheme),
                    timeout = 3,
                })
            end

            if code == 200 then
                logger.dbg("File downloaded to", local_path)
                if self.file_downloaded_callback then
                    self.file_downloaded_callback(local_path)
                end
            elseif code == 302 and remote_url:match("^https") and headers.location:match("^http[^s]") then
                util.removeFile(local_path)
                UIManager:show(InfoMessage:new{
                    text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."), BD.url(remote_url), BD.url(headers.location)),
                    icon = "notice-warning",
                })
            else
                util.removeFile(local_path)
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
        title = T(_("Download folder:\n%1\n\nDownload file type:"), BD.dirpath(path)),
        use_info_style = true,
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
                local filetype
                if DocumentRegistry:hasProvider(nil, acquisition.type) then
                    filetype = DocumentRegistry:mimeToExt(acquisition.type)
                elseif DocumentRegistry:hasProvider(acquisition.href) then
                    filetype = string.lower(util.getFileNameSuffix(acquisition.href))
                end
                if filetype then
                    -- append DOWNWARDS BLACK ARROW ⬇ U+2B07 to format
                    button.text = string.upper(filetype) .. "\xE2\xAC\x87"
                    button.callback = function()
                        self:downloadFile(item, filetype, acquisition.href)
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
    -- Set download folder and book info buttons.
    table.insert(buttons, {
        {
            text = _("Select folder"),
            callback = function()
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        logger.info("Download folder set to", path)
                        G_reader_settings:saveSetting("download_dir", path)
                        UIManager:nextTick(function()
                            UIManager:close(self.download_dialog)
                            self:createNewDownloadDialog(path, buttons)
                            UIManager:show(self.download_dialog)
                        end)
                    end,
                }:chooseDir()
            end,
        },
        {
            text = _("Book information"),
            enabled = type(item.content) == "string",
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                UIManager:show(TextViewer:new{
                    title = item.text,
                    text = util.htmlToPlainTextIfHtml(item.content),
                    text_face = Font:getFace("x_smallinfofont", G_reader_settings:readSetting("items_font_size")),
                })
            end,
        },
    })

    self:createNewDownloadDialog(self.getCurrentDownloadDir(), buttons)
    UIManager:show(self.download_dialog)
end

function OPDSBrowser:browse(browse_url, username, password)
    logger.dbg("Browse OPDS url", browse_url or "nil")
    table.insert(self.paths, {
        url = browse_url,
        username = username,
        password = password,
        title = self.catalog_title,
    })
    if not self:updateCatalog(browse_url, username, password) then
        table.remove(self.paths)
    end
end

function OPDSBrowser:browseSearchable(browse_url, username, password)
    self.search_server_dialog = InputDialog:new{
        title = _("Search OPDS catalog"),
        input = "",
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
    self.catalog_title = self.catalog_title or _("OPDS Catalog")
    -- add catalog
    if item.callback then
        item.callback()
    -- acquisition
    elseif item.acquisitions and #item.acquisitions > 0 then
        logger.dbg("Downloads available:", item)
        self:showDownloads(item)
    -- navigation
    else
        self.catalog_title = item.text or self.catalog_title
        local connect_callback
        if item.searchable then
            connect_callback = function()
                self:browseSearchable(item.url, item.username, item.password)
            end
        else
            connect_callback = function()
                self:browse(item.url, item.username, item.password)
            end
        end
        NetworkMgr:runWhenConnected(connect_callback)
    end
    return true
end

function OPDSBrowser:editServerFromInput(item, fields)
    logger.info("Edit OPDS catalog input:", fields)
    for _, server in ipairs(self.opds_servers) do
        if server.title == item.text or server.url == item.url then
            server.title = fields[1]
            server.url = (fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2])
            server.searchable =  (fields[2]:match("%%s") and true or false)
            server.username = fields[3] ~= "" and fields[3] or nil
            server.password = fields[4]
        end
    end
    self:init()
end

function OPDSBrowser:editOPDSServer(item)
    logger.info("Edit OPDS Server:", item)
    self.edit_server_dialog = MultiInputDialog:new{
        title = _("Edit OPDS catalog"),
        fields = {
            {
                text = item.text or "",
                hint = _("Catalog name"),
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
    logger.info("Delete OPDS server:", item)
    for i = #self.opds_servers, 1, -1 do
        local server = self.opds_servers[i]
        if server.title == item.text and server.url == item.url then
            table.remove(self.opds_servers, i)
        end
    end
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
            self.catalog_title = path.title
            self:updateCatalog(path.url, path.username, path.password)
        else
            -- return to root path, we simply reinit opdsbrowser
            self:init()
        end
    end
    return true
end

function OPDSBrowser:onHoldReturn()
    if #self.paths > 1 then
        local path = self.paths[1]
        if path then
            for i = #self.paths, 2, -1 do
                table.remove(self.paths)
            end
            self.catalog_title = path.title
            self:updateCatalog(path.url, path.username, path.password)
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
