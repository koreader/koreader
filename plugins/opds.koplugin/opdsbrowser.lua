local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Cache = require("cache")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local OPDSParser = require("opdsparser")
local OPDSPSE = require("opdspse")
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
            title = "Standard Ebooks",
            url = "https://standardebooks.org/feeds/opds",
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

    catalog_type         = "application/atom%+xml",
    search_type          = "application/opensearchdescription%+xml",
    search_template_type = "application/atom%+xml",
    acquisition_rel      = "^http://opds%-spec%.org/acquisition",
    borrow_rel           = "http://opds-spec.org/acquisition/borrow",
    image_rel            = "http://opds-spec.org/image",
    image_rel_alt        = "http://opds-spec.org/cover", -- ManyBooks.net, not in spec
    thumbnail_rel        = "http://opds-spec.org/image/thumbnail",
    thumbnail_rel_alt    = "http://opds-spec.org/thumbnail", -- ManyBooks.net, not in spec
    stream_rel           = "http://vaemendis.net/opds-pse/stream",

    root_catalog_title    = nil,
    root_catalog_username = nil,
    root_catalog_password = nil,

    title_shrink_font_to_fit = true,
}

function OPDSBrowser:init()
    self.item_table = self:genItemTableFromRoot()
    self.catalog_title = nil
    self.title_bar_left_icon = "plus"
    self.onLeftButtonTap = function()
        self:addEditCatalog()
    end
    Menu.init(self) -- call parent's init()
end

-- Builds the root list of catalogs
function OPDSBrowser:genItemTableFromRoot()
    local item_table = {}
    for _, server in ipairs(self.opds_servers) do
        table.insert(item_table, {
            text       = server.title,
            mandatory  = server.username and "\u{f2c0}",
            url        = server.url,
            username   = server.username,
            password   = server.password,
            searchable = server.url:match("%%s") and true or false,
        })
    end
    return item_table
end

-- Shows dialog to edit properties of the new/existing catalog
function OPDSBrowser:addEditCatalog(item)
    local fields = {
        {
            hint = _("Catalog name"),
        },
        {
            hint = _("Catalog URL"),
        },
        {
            hint = _("Username (optional)"),
        },
        {
            hint = _("Password (optional)"),
            text_type = "password",
        },
    }
    local title
    if item then
        title = _("Edit OPDS catalog")
        fields[1].text = item.text
        fields[2].text = item.url
        fields[3].text = item.username
        fields[4].text = item.password
    else
        title = _("Add OPDS catalog")
    end

    local dialog
    dialog = MultiInputDialog:new{
        title = title,
        fields = fields,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        self:editCatalogFromInput(dialog:getFields(), item)
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Shows dialog to add a subcatalog to the root list
function OPDSBrowser:addSubCatalog(item_url)
    local dialog
    dialog = InputDialog:new{
        title = _("Add OPDS catalog"),
        input = self.root_catalog_title .. " - " .. self.catalog_title,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if name ~= "" then
                            UIManager:close(dialog)
                            local fields = {name, item_url, self.root_catalog_username, self.root_catalog_password}
                            self:editCatalogFromInput(fields, false, true) -- no init, stay in the subcatalog
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Saves catalog properties from input dialog
function OPDSBrowser:editCatalogFromInput(fields, item, no_init)
    local new_server
    if item then -- edit old
        for _, server in ipairs(self.opds_servers) do
            if server.title == item.text and server.url == item.url then
                new_server = server
                break
            end
        end
    else -- add new
        new_server = {}
    end
    new_server.title    = fields[1]
    new_server.url      = fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2]
    new_server.username = fields[3] ~= "" and fields[3] or nil
    new_server.password = fields[4]
    if not item then
        table.insert(self.opds_servers, new_server)
    end
    if not no_init then
        self:init()
    end
end

-- Deletes catalog from the root list
function OPDSBrowser:deleteCatalog(item)
    for i, server in ipairs(self.opds_servers) do
        if server.title == item.text and server.url == item.url then
            table.remove(self.opds_servers, i)
            break
        end
    end
    self:init()
end

-- Fetches feed from server
function OPDSBrowser:fetchFeed(item_url, headers_only)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url      = item_url,
        method   = headers_only and "HEAD" or "GET",
        -- Explicitly specify that we don't support compressed content.
        -- Some servers will still break RFC2616 14.3 and send crap instead.
        headers  = {
            ["Accept-Encoding"] = "identity",
        },
        sink     = ltn12.sink.table(sink),
        user     = self.root_catalog_username,
        password = self.root_catalog_password,
    }
    logger.dbg("Request:", request)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if headers_only then
        return headers and headers["last-modified"]
    end
    if code == 200 then
        local xml = table.concat(sink)
        return xml ~= "" and xml
    end

    local text, icon
    if headers and code == 301 then
        text = T(_("The catalog has been permanently moved. Please update catalog URL to '%1'."), BD.url(headers.location))
    elseif headers and code == 302
        and item_url:match("^https")
        and headers.location:match("^http[^s]") then
        text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."),
            BD.url(item_url), BD.url(headers.location))
            icon = "notice-warning"
    else
        local error_message = {
            ["401"] = _("Authentication required for catalog. Please add a username and password."),
            ["403"] = _("Failed to authenticate. Please check your username and password."),
            ["404"] = _("Catalog not found."),
            ["406"] = _("Cannot get catalog. Server refuses to serve uncompressed content."),
        }
        text = code and error_message[tostring(code)] or T(_("Cannot get catalog. Server response status: %1."), status or code)
    end
    UIManager:show(InfoMessage:new{
        text = text,
        icon = icon,
    })
    logger.dbg(string.format("OPDS: Failed to fetch catalog `%s`: %s", item_url, text))
end

-- Parses feed to catalog
function OPDSBrowser:parseFeed(item_url)
    local feed_last_modified = self:fetchFeed(item_url, true) -- headers only
    local feed
    if feed_last_modified then
        local hash = "opds|catalog|" .. item_url .. "|" .. feed_last_modified
        feed = CatalogCache:check(hash)
        if feed then
            logger.dbg("Cache hit for", hash)
        else
            logger.dbg("Cache miss for", hash)
            feed = self:fetchFeed(item_url)
            if feed then
                logger.dbg("Caching", hash)
                CatalogCache:insert(hash, feed)
            end
        end
    else
        feed = self:fetchFeed(item_url)
    end
    if feed then
        return OPDSParser:parse(feed)
    end
end

-- Generates link to search in catalog
function OPDSBrowser:getSearchTemplate(osd_url)
    -- parse search descriptor
    local search_descriptor = self:parseFeed(osd_url)
    if search_descriptor and search_descriptor.OpenSearchDescription and search_descriptor.OpenSearchDescription.Url then
        for _, candidate in ipairs(search_descriptor.OpenSearchDescription.Url) do
            if candidate.type and candidate.template and candidate.type:find(self.search_template_type) then
                return candidate.template:gsub("{searchTerms}", "%%s")
            end
        end
    end
end

-- Generates menu items from the fetched list of catalog entries
function OPDSBrowser:genItemTableFromURL(item_url)
    local ok, catalog = pcall(self.parseFeed, self, item_url)
    if not ok then
        logger.info("Cannot get catalog info from", item_url, catalog)
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog info from %1"), (item_url and BD.url(item_url) or "nil")),
        })
        catalog = nil
    end
    return self:genItemTableFromCatalog(catalog, item_url)
end

function OPDSBrowser:genItemTableFromCatalog(catalog, item_url)
    local item_table = {}
    if not catalog then
        return item_table
    end

    local feed = catalog.feed or catalog

    local function build_href(href)
        return url.absolute(item_url, href)
    end

    local has_opensearch = false
    local hrefs = {}
    if feed.link then
        for __, link in ipairs(feed.link) do
            if link.type ~= nil then
                if link.type:find(self.catalog_type) then
                    if link.rel and link.href then
                        hrefs[link.rel] = build_href(link.href)
                    end
                end
                -- OpenSearch
                if link.type:find(self.search_type) then
                    if link.href then
                        table.insert(item_table, { -- the first item in each subcatalog
                            text       = "\u{f002} " .. _("Search"), -- append SEARCH icon
                            url        = build_href(self:getSearchTemplate(build_href(link.href))),
                            searchable = true,
                        })
                        has_opensearch = true
                    end
                end
                -- Calibre search (also matches the actual template for OpenSearch!)
                if link.type:find(self.search_template_type) and link.rel and link.rel:find("search") then
                    if link.href and not has_opensearch then
                        table.insert(item_table, {
                            text       = "\u{f002} " .. _("Search"),
                            url        = build_href(link.href:gsub("{searchTerms}", "%%s")),
                            searchable = true,
                        })
                    end
                end
            end
        end
    end
    item_table.hrefs = hrefs

    for _, entry in ipairs(feed.entry or {}) do
        local item = {}
        item.acquisitions = {}
        if entry.link then
            for __, link in ipairs(entry.link) do
                local link_href = build_href(link.href)
                if link.type and link.type:find(self.catalog_type)
                        and (not link.rel
                             or link.rel == "subsection"
                             or link.rel == "http://opds-spec.org/subsection"
                             or link.rel == "http://opds-spec.org/sort/popular"
                             or link.rel == "http://opds-spec.org/sort/new") then
                    item.url = link_href
                end
                -- Some catalogs do not use the rel attribute to denote
                -- a publication. Arxiv uses title. Specifically, it uses
                -- a title attribute that contains pdf. (title="pdf")
                if link.rel or link.title then
                    if link.rel == self.borrow_rel then
                        table.insert(item.acquisitions, {
                            type = "borrow",
                        })
                    elseif link.rel and link.rel:match(self.acquisition_rel) then
                        table.insert(item.acquisitions, {
                            type  = link.type,
                            href  = link_href,
                            title = link.title,
                        })
                    elseif link.rel == self.stream_rel then
                        -- https://vaemendis.net/opds-pse/
                        -- «count» MUST provide the number of pages of the document
                        -- namespace may be not "pse"
                        local count
                        for k, v in pairs(link) do
                            if k:sub(-6) == ":count" then
                                count = tonumber(v)
                                break
                            end
                        end
                        if count then
                            table.insert(item.acquisitions, {
                                type  = link.type,
                                href  = link_href,
                                title = link.title,
                                count = count,
                            })
                        end
                    elseif link.rel == self.thumbnail_rel or link.rel == self.thumbnail_rel_alt then
                        item.thumbnail = link_href
                    elseif link.rel == self.image_rel or link.rel == self.image_rel_alt then
                        item.image = link_href
                    end
                    -- This statement grabs the catalog items that are
                    -- indicated by title="pdf" or whose type is
                    -- "application/pdf"
                    if link.title == "pdf" or link.type == "application/pdf"
                        and link.rel ~= "subsection" then
                        -- Check for the presence of the pdf suffix and add it
                        -- if it's missing.
                        local href = link.href
                        if util.getFileNameSuffix(href) ~= "pdf" then
                            href = href .. ".pdf"
                        end
                        table.insert(item.acquisitions, {
                            type = link.title,
                            href = build_href(href),
                        })
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
        item.content = entry.content or entry.summary
        table.insert(item_table, item)
    end
    return item_table
end

-- Requests and shows updated list of catalog entries
function OPDSBrowser:updateCatalog(item_url, paths_updated)
    local menu_table = self:genItemTableFromURL(item_url)
    if #menu_table > 0 then
        if not paths_updated then
            table.insert(self.paths, {
                url   = item_url,
                title = self.catalog_title,
            })
        end
        self:switchItemTable(self.catalog_title, menu_table)
        self.onLeftButtonTap = function()
            self:addSubCatalog(item_url)
        end
        if self.page_num <= 1 then
            -- Request more content, but don't change the page
            self:onNextPage(true)
        end
    end
end

-- Requests and adds more catalog entries to fill out the page
function OPDSBrowser:appendCatalog(item_url)
    local menu_table = self:genItemTableFromURL(item_url)
    if #menu_table > 0 then
        for _, item in ipairs(menu_table) do
            -- Don't append multiple search entries
            if not item.searchable then
                table.insert(self.item_table, item)
            end
        end
        self.item_table.hrefs = menu_table.hrefs
        self:switchItemTable(self.catalog_title, self.item_table, -1)
        return true
    end
end

-- Shows dialog to search in catalog
function OPDSBrowser:searchCatalog(item_url)
    local dialog
    dialog = InputDialog:new{
        title = _("Search OPDS catalog"),
        -- @translators: This is an input hint for something to search for in an OPDS catalog, namely a famous author everyone knows. It probably doesn't need to be localized, but this is just here in case another name or book title would be more appropriate outside of a European context.
        input_hint = _("Alexandre Dumas"),
        description = _("%s in url will be replaced by your input"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(dialog)
                        self.catalog_title = _("Search results")
                        local search_str = dialog:getInputText():gsub(" ", "+")
                        self:updateCatalog(item_url:gsub("%%s", search_str))
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Shows dialog to download / stream a book
function OPDSBrowser:showDownloads(item)
    local acquisitions = item.acquisitions
    local filename = item.title
    if item.author then
        filename = item.author .. " - " .. filename
    end
    local filename_orig = filename

    local function createTitle(path, file) -- title for ButtonDialog
        return T(_("Download folder:\n%1\n\nDownload filename:\n%2\n\nDownload file type:"),
            BD.dirpath(path), file)
    end

    local buttons = {} -- buttons for ButtonDialog
    local stream_buttons -- page stream buttons
    local download_buttons = {} -- file type download buttons
    for i, acquisition in ipairs(acquisitions) do -- filter out unsupported file types
        if acquisition.count then
            stream_buttons = {
                {
                    -- @translators "Stream" here refers to being able to read documents from an OPDS server without downloading them completely, on a page by page basis.
                    text = _("Page stream") .. "\u{2B0C}", -- append LEFT RIGHT BLACK ARROW
                    callback = function()
                        OPDSPSE:streamPages(acquisition.href, acquisition.count, false, self.root_catalog_username, self.root_catalog_password)
                        UIManager:close(self.download_dialog)
                    end,
                },
                {
                    -- @translators "Stream" here refers to being able to read documents from an OPDS server without downloading them completely, on a page by page basis.
                    text = _("Stream from page") .. "\u{2B0C}", -- append LEFT RIGHT BLACK ARROW
                    callback = function()
                        OPDSPSE:streamPages(acquisition.href, acquisition.count, true, self.root_catalog_username, self.root_catalog_password)
                        UIManager:close(self.download_dialog)
                    end,
                },
            }
        elseif acquisition.type == "borrow" then
            table.insert(download_buttons, {
                text = _("Borrow"),
                enabled = false,
            })
        else
            local filetype = util.getFileNameSuffix(acquisition.href)
            logger.dbg("Filetype for download is", filetype)
            if not DocumentRegistry:hasProvider("dummy." .. filetype) then
                filetype = nil
            end
            if not filetype and DocumentRegistry:hasProvider(nil, acquisition.type) then
                filetype = DocumentRegistry:mimeToExt(acquisition.type)
            end
            if filetype then -- supported file type
                local text = url.unescape(acquisition.title or string.upper(filetype))
                table.insert(download_buttons, {
                    text = text .. "\u{2B07}", -- append DOWNWARDS BLACK ARROW
                    callback = function()
                        self:downloadFile(filename .. "." .. string.lower(filetype), acquisition.href)
                        UIManager:close(self.download_dialog)
                    end,
                })
            end
        end
    end

    local buttons_nb = #download_buttons
    if buttons_nb > 0 then
        if buttons_nb == 1 then -- one wide button
            table.insert(buttons, download_buttons)
        else
            if buttons_nb % 2 == 1 then -- we need even number of buttons
                table.insert(download_buttons, {text = ""})
            end
            for i = 1, buttons_nb, 2 do -- two buttons in a row
                table.insert(buttons, {download_buttons[i], download_buttons[i+1]})
            end
        end
        table.insert(buttons, {}) -- separator
    end
    if stream_buttons then
        table.insert(buttons, stream_buttons)
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, { -- action buttons
        {
            text = _("Choose folder"),
            callback = function()
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        logger.dbg("Download folder set to", path)
                        G_reader_settings:saveSetting("download_dir", path)
                        self.download_dialog:setTitle(createTitle(path, filename))
                    end,
                }:chooseDir(self.getCurrentDownloadDir())
            end,
        },
        {
            text = _("Change filename"),
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = _("Enter filename"),
                    input = filename,
                    input_hint = filename_orig,
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            },
                            {
                                text = _("Set filename"),
                                is_enter_default = true,
                                callback = function()
                                    filename = dialog:getInputValue()
                                    if filename == "" then
                                        filename = filename_orig
                                    end
                                    UIManager:close(dialog)
                                    self.download_dialog:setTitle(createTitle(self.getCurrentDownloadDir(), filename))
                                end,
                            },
                        }
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
    })
    local cover_link = item.image or item.thumbnail
    table.insert(buttons, {
        {
            text = _("Book cover"),
            enabled = cover_link and true or false,
            callback = function()
                OPDSPSE:streamPages(cover_link, 1, false, self.root_catalog_username, self.root_catalog_password)
            end,
        },
        {
            text = _("Book information"),
            enabled = type(item.content) == "string",
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                UIManager:show(TextViewer:new{
                    title = item.text,
                    title_multilines = true,
                    text = util.htmlToPlainTextIfHtml(item.content),
                    text_type = "book_info",
                })
            end,
        },
    })

    self.download_dialog = ButtonDialog:new{
        title = createTitle(self.getCurrentDownloadDir(), filename),
        buttons = buttons,
    }
    UIManager:show(self.download_dialog)
end

-- Returns user selected or last opened folder
function OPDSBrowser.getCurrentDownloadDir()
    return G_reader_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
end

-- Downloads a book (with "File already exists" dialog)
function OPDSBrowser:downloadFile(filename, remote_url)
    local download_dir = self.getCurrentDownloadDir()

    filename = util.getSafeFilename(filename, download_dir)
    local local_path = (download_dir ~= "/" and download_dir or "") .. '/' .. filename
    local_path = util.fixUtf8(local_path, "_")

    local function download()
        UIManager:scheduleIn(1, function()
            logger.dbg("Downloading file", local_path, "from", remote_url)
            local parsed = url.parse(remote_url)

            local code, headers, status
            if parsed.scheme == "http" or parsed.scheme == "https" then
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
                code, headers, status = socket.skip(1, http.request {
                    url      = remote_url,
                    headers  = {
                        ["Accept-Encoding"] = "identity",
                    },
                    sink     = ltn12.sink.file(io.open(local_path, "w")),
                    user     = self.root_catalog_username,
                    password = self.root_catalog_password,
                })
                socketutil:reset_timeout()
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("Invalid protocol:\n%1"), parsed.scheme),
                })
            end

            if code == 200 then
                logger.dbg("File downloaded to", local_path)
                self.file_downloaded_callback(local_path)
            elseif code == 302 and remote_url:match("^https") and headers.location:match("^http[^s]") then
                util.removeFile(local_path)
                UIManager:show(InfoMessage:new{
                    text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."), BD.url(remote_url), BD.url(headers.location)),
                    icon = "notice-warning",
                })
            else
                util.removeFile(local_path)
                logger.dbg("OPDSBrowser:downloadFile: Request failed:", status or code)
                logger.dbg("OPDSBrowser:downloadFile: Response headers:", headers)
                UIManager:show(InfoMessage:new {
                    text = T(_("Could not save file to:\n%1\n%2"),
                        BD.filepath(local_path),
                        status or code or "network unreachable"),
                })
            end
        end)

        UIManager:show(InfoMessage:new{
            text = _("Downloading may take several minutes…"),
            timeout = 1,
        })
    end

    if lfs.attributes(local_path) then
        UIManager:show(ConfirmBox:new{
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

-- Menu action on item tap (Download a book / Show subcatalog / Search in catalog)
function OPDSBrowser:onMenuSelect(item)
    if item.acquisitions and item.acquisitions[1] then -- book
        logger.dbg("Downloads available:", item)
        self:showDownloads(item)
    else -- catalog or Search item
        if #self.paths == 0 then -- root list
            self.root_catalog_title    = item.text
            self.root_catalog_username = item.username
            self.root_catalog_password = item.password
        end
        local connect_callback
        if item.searchable then
            connect_callback = function()
                self:searchCatalog(item.url)
            end
        else
            self.catalog_title = item.text or self.catalog_title or self.root_catalog_title
            connect_callback = function()
                self:updateCatalog(item.url)
            end
        end
        NetworkMgr:runWhenConnected(connect_callback)
    end
    return true
end

-- Menu action on item long-press (dialog Edit / Delete catalog)
function OPDSBrowser:onMenuHold(item)
    if #self.paths > 0 then return end -- not root list
    local dialog
    dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(dialog)
                        self:addEditCatalog(item)
                    end,
                },
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete OPDS catalog?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(dialog)
                                self:deleteCatalog(item)
                            end,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    return true
end

-- Menu action on return-arrow tap (go to one-level upper catalog)
function OPDSBrowser:onReturn()
    if #self.paths > 0 then -- not root list
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            -- return to last path
            self.catalog_title = path.title
            self:updateCatalog(path.url, true)
        else
            -- return to root path, we simply reinit opdsbrowser
            self:init()
        end
    end
    return true
end

-- Menu action on return-arrow long-press (go to the catalog home page)
function OPDSBrowser:onHoldReturn()
    if #self.paths > 1 then -- not catalog home page
        local path = self.paths[1]
        for i = #self.paths, 2, -1 do
            table.remove(self.paths)
        end
        self.catalog_title = path.title
        self:updateCatalog(path.url, true)
    end
    return true
end

-- Menu action on next-page chevron tap (request and show more catalog entries)
function OPDSBrowser:onNextPage(fill_only)
    -- self.page_num comes from menu.lua
    local page_num = self.page_num
    -- fetch more entries until we fill out one page or reach the end
    while page_num == self.page_num do
        local hrefs = self.item_table.hrefs
        if hrefs and hrefs.next then
            if not self:appendCatalog(hrefs.next) then
                break  -- reach end of paging
            end
        else
            break
        end
    end
    if not fill_only then
        -- We also *do* want to paginate, so call the base class.
        Menu.onNextPage(self)
    end
    return true
end

return OPDSBrowser
