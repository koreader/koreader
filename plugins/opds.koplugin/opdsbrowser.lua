local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Cache = require("cache")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local CookieJar = require("cookiejar")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local OPDSClient = require("opdsclient")
local OPDSDownloadList = require("opdsdownloadlist")
local OPDSParser = require("opdsparser")
local OPDSPSE = require("opdspse")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = ffiUtil.template

local OPDSBrowser = Menu:extend{
    opds20_feed          = "application/opds+json, application/atom+xml;profile=opds-catalog, */*",
    catalog_type         = "application/atom%+xml",
    search_type          = "application/opensearchdescription%+xml",
    search_template_type = "application/atom%+xml",
    acquisition_rel      = "^http://opds%-spec%.org/acquisition",
    borrow_rel           = "http://opds-spec.org/acquisition/borrow",
    stream_rel           = "http://vaemendis.net/opds-pse/stream",
    facet_rel            = "http://opds-spec.org/facet",
    download_rel         = {
        ["download"] = true,
        ["publication"] = true,
        ["http://opds-spec.org/acquisition"] = true,
        ["http://opds-spec.org/acquisition/open-access"] = true,
    },
    catalog_rel          = {
        ["subsection"] = true,
        ["http://opds-spec.org/subsection"] = true,
        ["http://opds-spec.org/crawlable"] = true,
        ["http://opds-spec.org/sort/popular"] = true,
        ["http://opds-spec.org/sort/new"] = true,
    },
    image_rel            = {
        ["http://opds-spec.org/image"] = true,
        ["http://opds-spec.org/cover"] = true, -- ManyBooks.net, not in spec
        ["x-stanza-cover-image"] = true,
    },
    thumbnail_rel        = {
        ["http://opds-spec.org/image/thumbnail"] = true,
        ["http://opds-spec.org/thumbnail"] = true, -- ManyBooks.net, not in spec
        ["x-stanza-cover-image-thumbnail"] = true,
    },

    -- from OPDS main
    settings      = nil,
    servers       = nil,
    downloads     = nil,
    pending_syncs = nil,

    download_list = nil, -- module
    http_client   = nil, -- module

    -- current catalog (server)
    root_catalog_title        = nil,
    root_catalog_username     = nil,
    root_catalog_password     = nil,
    root_catalog_raw_names    = nil, -- use server names for downloaded files
    root_catalog_download_dir = nil,
    facet_groups              = nil,
    search_url                = nil,
    alt_search_url            = nil,

    catalog_title             = nil, -- current subcatalog
    download_dir              = nil, -- chosen in file download dialog for current session, not saved
    download_filename         = nil, -- ditto

    title_shrink_font_to_fit  = true,
    title_bar_left_icon       = "appbar.menu",
}

local function get_value(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

function OPDSBrowser:init()
    self.item_table = self:genItemTableFromRoot()
    self:getHttpClient()
    self.catalog_title = nil
    self.onLeftButtonTap = function()
        self:showOPDSMenu()
    end
    self.facet_groups = nil
    Menu.init(self)
end

function OPDSBrowser:getHttpClient()
    if not self.http_client then
        self.http_client = OPDSClient:new{
            cookie_jar = CookieJar:new(),
        }
    end
    return self.http_client
end

function OPDSBrowser:showLoadingNotification()
    if not self.settings.no_loading_notification then -- the setting not in UI
        local info = Notification:new{ text = _("Loading…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
    end
end

function OPDSBrowser:showOPDSMenu()
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{
                    text = _("Add catalog"),
                    callback = function()
                        UIManager:close(dialog)
                        self:addEditCatalog()
                    end,
                    align = "left",
            }},
            {{
                    text = _("Set default download folder"),
                    callback = function()
                        self:setDefaultDownloadDir()
                    end,
                    align = "left",
            }},
            {}, -- separator
            {{
                    text = _("Sync all catalogs"),
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = false
                            self:checkSyncDownload()
                        end)
                    end,
                    align = "left",
            }},
            {{
                    text = _("Force sync all catalogs"),
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = true
                            self:checkSyncDownload()
                        end)
                    end,
                    align = "left",
            }},
            {}, -- separator
            {{
                    text = _("Set default sync folder"),
                    callback = function()
                        self:setDefaultSyncDir()
                    end,
                    align = "left",
            }},
            {{
                    text = _("Set file types to sync"),
                    callback = function()
                        self:setSyncFiletypes()
                    end,
                    align = "left",
            }},
            {{
                    text = _("Set max number of files to sync"),
                    callback = function()
                        self:setMaxSyncDownload()
                    end,
                    align = "left",
            }},
        },
        shrink_unneeded_width = true,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

function OPDSBrowser:showCatalogMenu()
    local catalog_url = self.paths[#self.paths].url
    local dialog
    local buttons = {
        {{
            text = "\u{f067} " .. _("Add catalog"), -- 'plus' sign
            callback = function()
                UIManager:close(dialog)
                self:addSubCatalog(catalog_url)
            end,
            align = "left",
        }},
    }
    if self.search_url then
        table.insert(buttons, {}) -- separator
        table.insert(buttons, {{
            text = "\u{f002} " .. _("Search"), -- 'magnifying glass' sign
            callback = function()
                UIManager:close(dialog)
                self:searchCatalog(self.search_url)
            end,
            align = "left",
        }})
    end
    if self.alt_search_url then
        table.insert(buttons, {{
            text = "\u{f002} " .. _("Alt search"),
            callback = function()
                UIManager:close(dialog)
                self:searchCatalog(self.alt_search_url)
            end,
            align = "left",
        }})
    end
    if self.facet_groups then
        table.insert(buttons, {}) -- separator
        for group_name, links in ffiUtil.orderedPairs(self.facet_groups) do
            local title = string.format("\u{f0b0} %s (%s)", group_name, #links) -- 'filter' sign
            table.insert(buttons, {{
                text = title,
                callback = function()
                    self:showFacetLinkList(title, links, catalog_url, dialog)
                end,
                menu_style = true,
            }})
        end
    end
    dialog = ButtonDialog:new{
        buttons = buttons,
        shrink_unneeded_width = true,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

function OPDSBrowser:showFacetLinkList(title, links, catalog_url, dialog)
    local item_table = {}
    for i, link in ipairs(links) do
        item_table[i] = {
            text = link.title,
            mandatory = link["thr:count"],
            bold = link["opds:activeFacet"] == "true" or nil,
            href = link.href,
        }
    end
    local link_list = Menu:new{
        title = title,
        item_table = item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuSelect = function(menu_self, item)
            UIManager:close(menu_self)
            UIManager:close(dialog)
            self:updateCatalog(url.absolute(catalog_url, item.href))
        end,
    }
    UIManager:show(link_list)
end

local function getItemMandatory(item)
    local t = {}
    if item.sync then
        table.insert(t, "\u{f46a}")
    end
    if item.download_dir then
        table.insert(t, "\u{f114}")
    end
    if item.raw_names then
        table.insert(t, "\u{f233}")
    end
    if item.username then
        table.insert(t, "\u{f2c0}")
    end
    return table.concat(t, " ")
end

local function buildRootEntry(server)
    return {
        text         = server.title,
        mandatory    = getItemMandatory(server),
        url          = server.url,
        searchable   = server.url and server.url:match("%%s") and true or false,
        username     = server.username,
        password     = server.password,
        raw_names    = server.raw_names,
        sync         = server.sync,
        download_dir = server.download_dir,
    }
end

function OPDSBrowser:genItemTableFromRoot()
    local item_table = {
        {
            text = _("Downloads"),
            mandatory = #self.downloads,
        },
    }
    for _, server in ipairs(self.servers) do
        table.insert(item_table, buildRootEntry(server))
    end
    return item_table
end

function OPDSBrowser:getServerFromRootItem(item)
    return item and item.idx and self.servers[item.idx - 1]
end

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

    local dialog, check_button_raw_names, check_button_sync_catalog
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
                        local new_fields = dialog:getFields()
                        new_fields[5] = check_button_raw_names.checked or nil
                        new_fields[6] = check_button_sync_catalog.checked or nil
                        self:editCatalogFromInput(new_fields, item)
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    check_button_raw_names = CheckButton:new{
        text = _("Use server filenames"),
        checked = item and item.raw_names,
        parent = dialog,
    }
    check_button_sync_catalog = CheckButton:new{
        text = _("Sync catalog"),
        checked = item and item.sync,
        parent = dialog,
    }
    dialog:addWidget(check_button_raw_names)
    dialog:addWidget(check_button_sync_catalog)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

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
                            local fields = {name, item_url,
                                self.root_catalog_username, self.root_catalog_password, self.root_catalog_raw_names}
                            self:editCatalogFromInput(fields, nil, true) -- no init, stay in the subcatalog
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function OPDSBrowser:editCatalogFromInput(fields, item, no_refresh)
    local old_server = self:getServerFromRootItem(item)
    local new_server = { -- server entry in settings/opds.lua
        title     = fields[1],
        url       = fields[2]:match("^%a+://") and fields[2] or "http://" .. fields[2],
        username  = fields[3] ~= "" and fields[3] or nil,
        password  = fields[4] ~= "" and fields[4] or nil,
        raw_names = fields[5],
        sync      = fields[6],
     -- sync_dir               -- local path (sync)
     -- last_download          -- url (sync)
     -- download_dir           -- local path
    }
    if old_server then
        new_server.sync_dir = old_server.sync_dir
        if old_server.url == new_server.url then
            new_server.last_download = old_server.last_download
        end
        new_server.download_dir = old_server.download_dir
    end
    local new_item = buildRootEntry(new_server)
    local new_idx, itemnumber
    if item then
        new_idx = item.idx
        itemnumber = -1
    else
        new_idx = #self.servers + 2
        itemnumber = new_idx
    end
    self.servers[new_idx - 1] = new_server -- first item is "Downloads"
    self.item_table[new_idx] = new_item
    if not no_refresh then
        self:switchItemTable(nil, self.item_table, itemnumber)
    end
    self._manager.updated = true
end

function OPDSBrowser:setDefaultDownloadDir()
    -- OPDS plugin uses common download_dir
    local title_header = _("Default download folder:")
    local current_path = self._manager.ui.folder_shortcuts:expandPath("%D%")
    local caller_callback = function(path)
        if path ~= current_path then
            self._manager.ui.folder_shortcuts:updateShortcut("download_dir", path)
            G_reader_settings:saveSetting("download_dir", path)
        end
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path)
end

function OPDSBrowser:setCatalogDownloadDir(item)
    local title_header = _("Catalog download folder:")
    local default_path = self._manager.ui.folder_shortcuts:expandPath("%D%")
    local current_path = item.download_dir or default_path
    local caller_callback = function(path)
        if path ~= current_path then
            local server = self:getServerFromRootItem(item)
            path = path ~= default_path and path or nil
            server.download_dir = path
            item.download_dir = path
            item.mandatory = getItemMandatory(item)
            self:switchItemTable(nil, self.item_table, -1)
            self._manager.updated = true
        end
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
end

function OPDSBrowser:deleteCatalog(item)
    table.remove(self.servers, item.idx - 1)
    table.remove(self.item_table, item.idx)
    self:switchItemTable(nil, self.item_table, -1)
    self._manager.updated = true
end

function OPDSBrowser:getCatalogCache()
    if not self.catalog_cache then
        self.catalog_cache = Cache:new{
            -- Make it 20 slots, with no storage space constraints.
            slots = 20,
        }
    end
    return self.catalog_cache
end

function OPDSBrowser:getConditionalFeedHeaders(cached_feed)
    if not cached_feed then
        return nil
    end

    local headers = {}
    if cached_feed.etag then
        headers["If-None-Match"] = cached_feed.etag
    end
    if cached_feed.last_modified then
        headers["If-Modified-Since"] = cached_feed.last_modified
    end
    return headers
end

function OPDSBrowser:fetchFeed(item_url, headers_only, extra_headers)
    local sink = {}
    local block_timeout, total_timeout = socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url      = item_url,
        method   = headers_only and "HEAD" or "GET",
        -- Explicitly specify that we don't support compressed content.
        -- Some servers will still break RFC2616 14.3 and send crap instead.
        headers  = {
            ["Accept-Encoding"] = "identity",
            ["Accept"] = self.opds20_feed, -- prefer OPDS 2.0
        },
        sink     = ltn12.sink.table(sink),
        username = self.root_catalog_username,
        password = self.root_catalog_password,
    }
    for name, value in pairs(extra_headers or {}) do
        request.headers[name] = value
    end
    logger.dbg("Request:", socketutil.redact_request(request))
    local code, headers, status = self:getHttpClient():request(request)
    socketutil:reset_timeout()

    if headers_only then
        return headers
    end
    if code == 200 then
        local xml = table.concat(sink)
        return xml ~= "" and xml, headers, code
    elseif code == 304 then
        return nil, headers, code
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
        local network_error = socketutil.describe_error(code, block_timeout, total_timeout)
        if network_error then
            text = _("Cannot get catalog.") .. "\n\n" .. network_error
        else
            text = code and error_message[tostring(code)] or T(_("Cannot get catalog. Server response status: %1."), status or code)
        end
    end
    UIManager:show(InfoMessage:new{
        text = text,
        icon = icon,
    })
    logger.dbg(string.format("OPDS: Failed to fetch catalog `%s`: %s", item_url, text))
end

function OPDSBrowser:parseFeed(item_url)
    local cache_key = "opds|catalog|" .. item_url
    local cache = self:getCatalogCache()
    local cached_feed = cache:check(cache_key)
    local conditional_headers = self:getConditionalFeedHeaders(cached_feed)
    if conditional_headers then
        logger.dbg("Revalidating cache entry for", cache_key)
    end

    local feed, headers, code = self:fetchFeed(item_url, false, conditional_headers)
    if code == 304 and cached_feed then
        feed = cached_feed.content
        logger.dbg("Cache hit for", cache_key)
    elseif feed and headers and (headers.etag or headers["last-modified"]) then
        cache:insert(cache_key, {
            content = feed,
            etag = headers.etag,
            last_modified = headers["last-modified"],
        })
        logger.dbg("Caching", cache_key)
    end
    if feed then
        if feed:match("^%s*{") then -- OPDS 2.0
            local JSON = require("json")
            local ret, result = pcall(JSON.decode, feed)
            if ret then
                result.is_opds2 = true
                return result
            end
        else -- OPDS 1.x
            return OPDSParser:parse(feed)
        end
    end
end

function OPDSBrowser:getServerFileName(item_url, filetype)
    local headers = self:fetchFeed(item_url, true)
    local filename

    if headers then
        logger.dbg("OPDSBrowser: server file headers", socketutil.redact_headers(headers))
        local disposition = headers["content-disposition"]
        if disposition then
            -- Try to get filename inside quotes (can contain spaces)
            filename = disposition:match('filename="([^"]+)"')
            if not filename then
                -- Fallback: try filename without quotes, until end or semicolon
                filename = disposition:match('filename=([^;]+)')
            end
        end

        -- If not found, try from redirect URL (location)
        if not filename and headers["location"] then
            filename = headers["location"]:gsub(".*/", "")
        end
    end

    -- If still no filename, extract from original URL (remove path and query params)
    if not filename then
        filename = item_url:gsub(".*/", ""):gsub("?.*", "")
    end

    if filename and filetype then
        -- Add extension if missing or unusable.
        local current_suffix = util.getFileNameSuffix(filename)
        if not DocumentRegistry:hasProvider("dummy." .. current_suffix) then
            filename = filename .. "." .. filetype:lower()
        end
    end
    filename = util.urlDecode(filename)
    return filename
end

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

function OPDSBrowser:genItemTableFromURL(item_url)
    local ok, catalog = pcall(self.parseFeed, self, item_url)
    if not ok then
        logger.info("Cannot get catalog info from", item_url, catalog)
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot get catalog info from %1"), (item_url and BD.url(item_url) or "nil")),
        })
        catalog = nil
    end
    if catalog and catalog.is_opds2 then
        return self:genItemTableFromCatalog2(catalog, item_url)
    else
        return self:genItemTableFromCatalog(catalog, item_url)
    end
end

function OPDSBrowser:genItemTableFromCatalog2(catalog, item_url)
    self.catalog_title = catalog.metadata and catalog.metadata.title or self.catalog_title
    self.facet_groups = nil
    self.search_url = nil
    self.alt_search_url = nil
    local item_table = { hrefs = {} }

    if type(catalog.links) == "table" then
        for _, link in ipairs(catalog.links) do
            local rel = get_value(link.rel)
            if rel and link.href then
                if rel == "search" then
                    if link.href:gsub("{.*}", ""):find("query") then
                        self.search_url = url.absolute(item_url, link.href:gsub("{.*}", "%%s"))
                    else
                        self.search_url = url.absolute(item_url, link.href:gsub("{.*}", "%?query=%%s"))
                    end
                else
                    item_table.hrefs[rel] = url.absolute(item_url, link.href)
                end
            end
        end
    end

    local function get_facet(f_link, f_rel)
        local href = url.absolute(item_url, f_link.href)
        return {
            title = f_link.title,
            href = href,
             -- mimic OPDS 1.x
            ["thr:count"] = f_link.properties and f_link.properties.numberOfItems,
            ["opds:activeFacet"] = (f_rel == "self" or item_url == href) and "true",
        }
    end

    if type(catalog.facets) == "table" then
        self.facet_groups = self.facet_groups or {}
        for _, facet in ipairs(catalog.facets) do
            self.facet_groups[facet.metadata.title] = {}
            for i, link in ipairs(facet.links) do
                if link.href then
                    local rel = get_value(link.rel)
                    table.insert(self.facet_groups[facet.metadata.title], get_facet(link, rel))
                end
            end
        end
    end

    local nav_nb = 0
    local function add_navigation(navigation, top_title)
        for _, nav in ipairs(navigation) do
            local rel = get_value(nav.rel)
            if nav.title and nav.href and (not rel or rel ~= "self") then
                if top_title and rel == self.facet_rel then -- facet
                    self.facet_groups = self.facet_groups or {}
                    self.facet_groups[top_title] = self.facet_groups[top_title] or {}
                    table.insert(self.facet_groups[top_title], get_facet(nav, rel))
                else -- navigation
                    nav_nb = nav_nb + 1 -- navigations precede collections (groups) in the list
                    local numberOfItems = nav.properties and nav.properties.numberOfItems
                    table.insert(item_table, nav_nb, {
                        text = top_title and top_title .. " - " .. nav.title or nav.title,
                        url = url.absolute(item_url, nav.href),
                        mandatory = numberOfItems and numberOfItems .. " \u{e602}" or "\u{e602}", -- 'play arrow' sign
                        acquisitions = {},
                    })
                end
            end
        end
    end

    if type(catalog.navigation) == "table" then
        add_navigation(catalog.navigation)
    end

    if type(catalog.groups) == "table" then
        for _, group in ipairs(catalog.groups) do
            local title = group.metadata and group.metadata.title
            if type(group.navigation) == "table" then -- navigation
                add_navigation(group.navigation, title)
            else -- collection
                local href = group.links and group.links[1] and group.links[1].href
                if title and href then
                    local numberOfItems = group.metadata.numberOfItems or 0
                    table.insert(item_table, {
                        text = title,
                        url = url.absolute(item_url, href),
                        mandatory = numberOfItems ~= 0 and numberOfItems or "-",
                        acquisitions = {},
                    })
                end
            end
        end
    end

    if type(catalog.publications) == "table" then
        for _, entry in ipairs(catalog.publications) do
            table.insert(item_table, self:getItemFromPublication(entry, item_url))
        end
    end

    return item_table
end

function OPDSBrowser:getItemFromPublication(entry, item_url)
    local title, author, content
    if type(entry.metadata) == "table" then
        content = entry.metadata.description
        title = entry.metadata.title or _("Unknown")
        author = entry.metadata.author
        if type(author) == "table" then
            if type(author.name) == "string" then
                author = author.name
            elseif type(author.name) == "table" then
                author = table.concat(author.name, ", ")
            elseif type(author[1]) == "string" then
                author = table.concat(author, ", ")
            elseif type(author[1]) == "table" then
                local t = {}
                for _, v in ipairs(author) do
                    if type(v.name) == "string" then
                        table.insert(t, v.name)
                    elseif type(v.name) == "table" then
                        table.insert(t, table.concat(v.name, ", "))
                    end
                end
                author = table.concat(t, ", ")
            end
        end
        author = (type(author) == "string" and author ~= "") and author or _("Unknown Author")
    end

    local thumbnail, image
    if type(entry.images) == "table" then
        for _, link in ipairs(entry.images) do
            local rel = get_value(link.rel)
            if self.thumbnail_rel[rel] then
                thumbnail = url.absolute(item_url, link.href)
            elseif self.image_rel[rel] then
                image = url.absolute(item_url, link.href)
            end
        end
        thumbnail = thumbnail or url.absolute(item_url, entry.images[1].href)
        image = image or thumbnail
    end

    local acquisitions = {}
    if type(entry.links) == "table" then
        for _, link in ipairs(entry.links) do
            local rel = get_value(link.rel)
            if rel and rel ~= "self" then
                if rel == self.borrow_rel then
                    table.insert(acquisitions, {
                        type = "borrow",
                    })
                elseif rel:match(self.acquisition_rel) then
                    if util.tableGetValue(link, "properties", "indirectAcquisition", 1, "type") then
                        -- indirect acquisition
                        local link_feed = self:parseFeed(url.absolute(item_url, link.href))
                        if type(link_feed) == "table" and type(link_feed.links) == "table" then
                            for _, in_link in ipairs(link_feed.links) do
                                local in_rel = get_value(in_link.rel)
                                if in_rel and self.download_rel[in_rel] then
                                    table.insert(acquisitions, {
                                        type = in_link.type,
                                        title = in_link.title,
                                        href = url.absolute(item_url, in_link.href),
                                        size = in_link.size,
                                    })
                                end
                            end
                        end
                    else
                        table.insert(acquisitions, {
                            type = link.type,
                            title = link.title,
                            href = url.absolute(item_url, link.href),
                            size = link.size,
                        })
                    end
                end
            end
        end
    end

    return { -- book list item
        text = title .. " - " .. author,
        title = title,
        author = author,
        content = content,
        thumbnail = thumbnail,
        image = image,
        acquisitions = acquisitions,
    }
end

function OPDSBrowser:genItemTableFromCatalog(catalog, item_url)
    local item_table = {}
    self.facet_groups = nil
    self.search_url = nil
    self.alt_search_url = nil

    if not catalog then
        return item_table
    end

    local feed = catalog.feed or catalog
    self.facet_groups = {}

    local function build_href(href)
        return url.absolute(item_url, href)
    end

    local hrefs = {}
    if feed.link then
        for __, link in ipairs(feed.link) do
            if link.type ~= nil then
                if link.type:find(self.catalog_type) then
                    if link.rel and link.href then
                        hrefs[link.rel] = build_href(link.href)
                    end
                end
                if not self.syncing then
                    if link.href then
                        if not self.search_url and link.type:find(self.search_type) then
                            local template = self:getSearchTemplate(build_href(link.href))
                            self.search_url = template and build_href(template)
                        end
                        if not self.alt_search_url and link.type:find(self.search_template_type)
                                and link.rel and link.rel:find("search") then
                            self.alt_search_url = build_href(link.href:gsub("{searchTerms}", "%%s"))
                        end
                    end
                    -- Process OPDS facets
                    if link.rel == self.facet_rel then
                        local group_name = link["opds:facetGroup"] or _("Filters")
                        if not self.facet_groups[group_name] then
                            self.facet_groups[group_name] = {}
                        end
                        table.insert(self.facet_groups[group_name], link)
                    end
                end
            end
        end
        if self.alt_search_url then
            if not self.search_url then
                self.search_url = self.alt_search_url
                self.alt_search_url = nil
            elseif self.alt_search_url == self.search_url then
                self.alt_search_url = nil
            end
        end
    end
    item_table.hrefs = hrefs

    for __, entry in ipairs(feed.entry or {}) do
        local item = {}
        item.acquisitions = {}
        if entry.link then
            for ___, link in ipairs(entry.link) do
                local link_href = build_href(link.href)
                if link.type and link.type:find(self.catalog_type)
                        and (not link.rel or self.catalog_rel[link.rel]) then
                    item.url = link_href
                end
                -- Some catalogs do not use the rel attribute to denote
                -- a publication. Arxiv uses title. Specifically, it uses
                -- a title attribute that contains pdf. (title="pdf")
                if link.rel or link.title then
                    local acquisitions_nb = #item.acquisitions
                    if link.rel == self.borrow_rel then
                        table.insert(item.acquisitions, {
                            type = "borrow",
                        })
                    elseif link.rel and link.rel:match(self.acquisition_rel) then
                        table.insert(item.acquisitions, {
                            type  = link.type,
                            href  = link_href,
                            title = link.title,
                            size  = link.length,
                        })
                    elseif link.rel == self.stream_rel then
                        -- https://vaemendis.net/opds-pse/
                        -- «count» MUST provide the number of pages of the document
                        -- namespace may be not "pse"
                        local count, last_read
                        for k, v in pairs(link) do
                            if k:sub(-6) == ":count" then
                                count = tonumber(v)
                            elseif k:sub(-9) == ":lastRead" then
                                last_read = tonumber(v)
                            end
                        end
                        if count then
                            table.insert(item.acquisitions, {
                                type  = link.type,
                                href  = link_href,
                                title = link.title,
                                count = count,
                                last_read = last_read and last_read > 0 and last_read or nil
                            })
                        end
                    elseif self.thumbnail_rel[link.rel] then
                        item.thumbnail = link_href
                    elseif self.image_rel[link.rel] then
                        item.image = link_href
                    elseif link.rel ~= "alternate" and DocumentRegistry:hasProvider(nil, link.type) then
                        table.insert(item.acquisitions, {
                            type  = link.type,
                            href  = link_href,
                            title = link.title,
                            size  = link.length,
                        })
                    end
                    -- This statement grabs the catalog items that are
                    -- indicated by title="pdf" or whose type is
                    -- "application/pdf", and that have not already been
                    -- added as an acquisition above (which would result in
                    -- duplicate download buttons)
                    if #item.acquisitions == acquisitions_nb
                        and (link.title == "pdf" or link.type == "application/pdf")
                        and link.rel ~= "subsection" then
                        -- Check for the presence of the pdf suffix and add it
                        -- if it's missing.
                        local original_href = link.href
                        local parsed = url.parse(original_href)
                        if not parsed then parsed = { path = original_href } end
                        local path = parsed.path or ""
                        -- Calibre web OPDS download links end with "/<filetype>/"
                        if not util.stringEndsWith(path, "/pdf/") then
                            local appended = false
                            if util.getFileNameSuffix(path) ~= "pdf" then
                                if path == "" then
                                    path = ".pdf"
                                else
                                    path = path .. ".pdf"
                                end
                                appended = true
                            end
                            if appended then
                                parsed.path = path
                                local new_href = url.build(parsed)
                                table.insert(item.acquisitions, {
                                    type = link.title,
                                    href = build_href(new_href),
                                })
                            end
                        end
                    end
                end
            end
        end
        local title = _("Unknown")
        if type(entry.title) == "string" then
            title = entry.title
        elseif type(entry.title) == "table" then
            if type(entry.title.type) == "string" and entry.title.div ~= "" then
                title = entry.title.div
            end
        end
        local author
        if type(entry.author) == "table" then
            author = entry.author.name
            if not author then
                local names = {}
                local empty_name = false
                for _, entry_author in ipairs(entry.author) do
                    local name = type(entry_author) == "table" and entry_author.name or nil
                    if type(name) == "table" then
                        if #name > 0 then
                            name = table.concat(name, ", ")
                        else
                            -- we may get an empty table on https://gallica.bnf.fr/opds
                            empty_name = true
                            name = nil
                        end
                    end
                    if type(name) == "string" then
                        table.insert(names, name)
                    end
                end
                if #names > 0 then
                    author = table.concat(names, ", ")
                elseif empty_name then
                    author = nil
                end
            end
        end
        item.text = author and title .. " - " .. author or title
        item.title = title
        item.author = author or _("Unknown Author")
        item.content = entry.content or entry.summary
        table.insert(item_table, item)
    end

    if next(self.facet_groups) == nil then self.facet_groups = nil end -- Clear if empty

    return item_table
end

function OPDSBrowser:saveCatalogSnapshot()
    local path = self.paths[#self.paths]
    if path then
        path.snapshot = {
            catalog_title = self.catalog_title,
            facet_groups = self.facet_groups,
            item_table = self.item_table,
            search_url = self.search_url,
            alt_search_url = self.alt_search_url,
        }
    end
end

function OPDSBrowser:setCatalogMenu(item_url, menu_table)
    self:switchItemTable(self.catalog_title, menu_table)

    -- Set appropriate title bar icon based on content
    if self.facet_groups or self.search_url then
        self:setTitleBarLeftIcon("appbar.menu")
        self.onLeftButtonTap = function()
            self:showCatalogMenu()
        end
    else
        self:setTitleBarLeftIcon("plus")
        self.onLeftButtonTap = function()
            self:addSubCatalog(item_url)
        end
    end
end

function OPDSBrowser:updateCatalog(item_url, paths_updated)
    self:showLoadingNotification()
    local menu_table = self:genItemTableFromURL(item_url)
    if #menu_table > 0 or self.facet_groups or self.search_url then
        if not paths_updated then
            table.insert(self.paths, {
                url   = item_url,
                title = self.catalog_title,
            })
        end
        self:setCatalogMenu(item_url, menu_table)

        if self.page_num <= 1 then
            -- Request more content, but don't change the page
            self:onNextPage(true)
        end
        self:saveCatalogSnapshot()
    end
end

function OPDSBrowser:appendCatalog(item_url)
    local menu_table = self:genItemTableFromURL(item_url)
    if #menu_table > 0 then
        for __, item in ipairs(menu_table) do
            table.insert(self.item_table, item)
        end
        self.item_table.hrefs = menu_table.hrefs
        self:switchItemTable(self.catalog_title, self.item_table, -1)
        return true
    end
end

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
                        local search_str = util.urlEncode(dialog:getInputText())
                        -- Use function replacement to avoid % being treated as capture refs
                        item_url = item_url:gsub("%%s", function() return search_str end)
                        self:updateCatalog(item_url)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function OPDSBrowser:showDownloads(item)
    local filename_orig
    self.download_filename, filename_orig = self:getFileName(item)
    local function item_path_func()
        return self:getCurrentDownloadDir(), self.download_filename or _("<server filename>")
    end
    local function download_buttons_func(close_parent_dialog)
        return self:getDownloadButtons(item, close_parent_dialog)
    end
    local function change_folder_func()
        local default_path = self.root_catalog_download_dir or self._manager.ui.folder_shortcuts:expandPath("%D%")
        return {
            default_path = default_path,
            current_path = self.download_dir or default_path,
            caller_callback = function(path_arg)
                self.download_dir = path_arg ~= default_path and path_arg or nil
            end,
        }
    end
    local function change_filename_func()
        return {
            input = self.download_filename or filename_orig,
            input_hint = filename_orig,
            caller_callback = function(filename_arg)
                if filename_arg ~= self.download_filename then
                    self.download_filename = filename_arg ~= "" and filename_arg or filename_orig
                    return true
                end
            end,
        }
    end
    self:showDownloadDialog(item, item_path_func,
        download_buttons_func, change_folder_func, change_filename_func)
end

function OPDSBrowser:getDownloadButtons(item, close_parent_dialog)
    local stream_buttons -- page stream buttons
    local download_buttons = {} -- file type download buttons
    for i, acquisition in ipairs(item.acquisitions) do -- filter out unsupported file types
        if acquisition.count then
            stream_buttons = {
                {
                    {
                        -- @translators "Stream" here refers to being able to read documents from an OPDS server without downloading them completely, on a page by page basis.
                        text = "\u{23EE} " .. _("Page stream"), -- prepend BLACK LEFT-POINTING DOUBLE TRIANGLE WITH BAR
                        callback = function()
                            OPDSPSE:streamPages(acquisition.href, acquisition.count, false, self.root_catalog_username, self.root_catalog_password)
                            close_parent_dialog()
                        end,
                    },
                    {
                        -- @translators "Stream" here refers to being able to read documents from an OPDS server without downloading them completely, on a page by page basis.
                        text = _("Stream from page") .. " \u{23E9}", -- append BLACK RIGHT-POINTING DOUBLE TRIANGLE
                        callback = function()
                            OPDSPSE:streamPages(acquisition.href, acquisition.count, true, self.root_catalog_username, self.root_catalog_password)
                            close_parent_dialog()
                        end,
                    },
                },
            }
            if acquisition.last_read then
                table.insert(stream_buttons, {
                    {
                        -- @translators "Stream" here refers to being able to read documents from an OPDS server without downloading them completely, on a page by page basis.
                        text = "\u{25B6} " .. _("Resume stream from page") .. " " .. acquisition.last_read, -- prepend BLACK RIGHT-POINTING TRIANGLE
                        callback = function()
                            OPDSPSE:streamPages(acquisition.href, acquisition.count, false, self.root_catalog_username, self.root_catalog_password, acquisition.last_read)
                            close_parent_dialog()
                        end,
                    },
                })
            end
        elseif acquisition.type == "borrow" then
            table.insert(download_buttons, {
                text = _("Borrow"),
                enabled = false,
            })
        else
            local filetype = self.getFiletype(acquisition)
            if filetype then -- supported file type
                local text = url.unescape(acquisition.title or string.upper(filetype))
                if acquisition.size then
                    text = T(_("%1 (%2)"), text, util.getFriendlySize(acquisition.size))
                end
                table.insert(download_buttons, {
                    text = text .. "\u{2B07}", -- append DOWNWARDS BLACK ARROW
                    callback = function()
                        close_parent_dialog()
                        local local_path = self:getLocalDownloadPath(self.download_filename, filetype, acquisition.href)
                        self:checkDownloadFile(local_path, acquisition.href, self.root_catalog_username, self.root_catalog_password,
                            self.file_downloaded_callback, self.file_read_now_callback)
                    end,
                    hold_callback = function()
                        Notification:notify(_("Book added to download list"), Notification.SOURCE_OTHER)
                        close_parent_dialog()
                        table.insert(self.downloads, {
                            file     = self:getLocalDownloadPath(self.download_filename, filetype, acquisition.href),
                            url      = acquisition.href,
                            size     = acquisition.size,
                            image    = item.image or item.thumbnail,
                            info     = item.content,
                            catalog  = self.root_catalog_title,
                            username = self.root_catalog_username,
                            password = self.root_catalog_password,
                            datetime = os.date("%Y-%m-%d %H:%M:%S"),
                        })
                        self._manager.updated = true
                    end,
                })
            end
        end
    end

    local buttons = {}
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
    end
    if stream_buttons then
        table.insert(buttons, {}) -- separator
        for _, button_list in ipairs(stream_buttons) do
            table.insert(buttons, button_list)
        end
    end
    return buttons
end

function OPDSBrowser:showDownloadDialog(item, item_path_func,
        download_buttons_func, change_folder_func, change_filename_func)
    local textviewer
    local function close_parent_dialog()
        textviewer:onClose()
    end
    local buttons_table = download_buttons_func(close_parent_dialog)
    table.insert(buttons_table, {}) -- separator

    table.insert(buttons_table, {
        {
            text = _("Choose folder"),
            callback = function()
                local change_folder = change_folder_func()
                local title_header = _("Download folder:")
                local default_path = change_folder.default_path
                local current_path = change_folder.current_path
                local caller_callback = function(path)
                    if path ~= current_path then
                        change_folder.caller_callback(path)
                        textviewer:onClose() -- reopen
                        self:showDownloadDialog(item, item_path_func,
                            download_buttons_func, change_folder_func, change_filename_func)
                    end
                end
                filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
            end,
        },
        {
            text = _("Change filename"),
            callback = function()
                local change_filename = change_filename_func()
                local dialog
                dialog = InputDialog:new{
                    title = _("Enter filename"),
                    input = change_filename.input,
                    input_hint = change_filename.input_hint,
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
                                    UIManager:close(dialog)
                                    if change_filename.caller_callback(dialog:getInputValue()) then
                                        textviewer:onClose() -- reopen
                                        self:showDownloadDialog(item, item_path_func,
                                            download_buttons_func, change_folder_func, change_filename_func)
                                    end
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
    table.insert(buttons_table, {
        {
            text = _("Book cover"),
            enabled = cover_link and true or false,
            callback = function()
                NetworkMgr:runWhenConnected(function()
                    OPDSPSE:streamPages(cover_link, 1, false,
                        item.username or self.root_catalog_username, item.password or self.root_catalog_password)
                end)
            end,
        },
        {
            text = _("Close"),
            callback = function()
                textviewer:onClose()
            end,
        },
    })

    local dl_folder, dl_filename = item_path_func()
    local info = item.info or item.content
    info = type(info) == "string" and util.htmlToPlainTextIfHtml(info) or ""
    local text = table.concat({
        TextBoxWidget.PTF_HEADER,
        TextBoxWidget.PTF_BOLD_START, _("Download folder"), TextBoxWidget.PTF_BOLD_END, "\n",
        BD.dirpath(dl_folder), "\n", "\n",
        TextBoxWidget.PTF_BOLD_START, _("Download filename"), TextBoxWidget.PTF_BOLD_END, "\n",
        dl_filename, "\n", "\n",
        TextBoxWidget.PTF_BOLD_START, _("Book description"), TextBoxWidget.PTF_BOLD_END, "\n",
        info,
    })
    textviewer = TextViewer:new{
        title = item.catalog or self.root_catalog_title,
        text = text,
        text_type = "book_info",
        buttons_table = buttons_table,
    }
    UIManager:show(textviewer)
end

function OPDSBrowser:getFileName(item)
    local filename = item.title
    if item.author then
        filename = item.author .. " - " .. filename
    end
    local filename_orig = filename
    if self.root_catalog_raw_names then
        filename = nil
    end
    return util.replaceAllInvalidChars(filename), util.replaceAllInvalidChars(filename_orig)
end

function OPDSBrowser.getFiletype(link)
    local filetype = util.getFileNameSuffix(link.href)
    if not DocumentRegistry:hasProvider("dummy." .. filetype) then
        filetype = nil
    end
    if not filetype and DocumentRegistry:hasProvider(nil, link.type) then
        filetype = DocumentRegistry:mimeToExt(link.type)
    end
    return filetype
end

function OPDSBrowser:getCurrentDownloadDir()
    if self.syncing then
        return self:getSyncDir(self.sync_server)
    end
    return self.download_dir or self.root_catalog_download_dir or self._manager.ui.folder_shortcuts:expandPath("%D%")
end

function OPDSBrowser:getLocalDownloadPath(filename, filetype, remote_url)
    local download_dir = self:getCurrentDownloadDir()
    filename = filename and filename .. "." .. filetype:lower() or self:getServerFileName(remote_url, filetype)
    filename = util.getSafeFilename(filename, download_dir)
    filename = (download_dir ~= "/" and download_dir or "") .. '/' .. filename
    return filename
end

function OPDSBrowser:checkDownloadFile(local_path, remote_url, username, password, caller_callback, read_now_callback)
    local function download()
        UIManager:scheduleIn(1, function()
            self:downloadFile(local_path, remote_url, username, password, caller_callback)
        end)
        UIManager:show(InfoMessage:new{
            text = _("Downloading…"),
            timeout = 1,
        })
    end
    if lfs.attributes(local_path) then
        local other_buttons = {{
            {
                text = _("Read existing book"),
                callback = function()
                    read_now_callback(local_path)
                end,
            },
        }}
        UIManager:show(ConfirmBox:new{
            text = T(_("The file %1 already exists."), BD.filepath(local_path)),
            ok_text = _("Overwrite"),
            ok_callback = function()
                download()
            end,
            other_buttons = other_buttons,
        })
    else
        download()
    end
end

function OPDSBrowser:downloadFile(local_path, remote_url, username, password, caller_callback)
    logger.dbg("Downloading file", local_path, "from", remote_url)
    local code, headers, status, block_timeout, total_timeout
    local parsed = url.parse(remote_url)
    if parsed.scheme == "http" or parsed.scheme == "https" then
        block_timeout, total_timeout = socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        code, headers, status = self:getHttpClient():request {
            url      = remote_url,
            headers  = {
                ["Accept-Encoding"] = "identity",
            },
            sink     = ltn12.sink.file(io.open(local_path, "w")),
            username = username,
            password = password,
        }
        socketutil:reset_timeout()
    else
        UIManager:show(InfoMessage:new {
            text = T(_("Invalid protocol:\n%1"), parsed.scheme),
        })
    end
    if code == 200 then
        logger.dbg("File downloaded to", local_path)
        if caller_callback then
            caller_callback(local_path)
        end
        return true
    elseif code == 302 and remote_url:match("^https") and headers.location:match("^http[^s]") then
        util.removeFile(local_path)
        UIManager:show(InfoMessage:new{
            text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."), BD.url(remote_url), BD.url(headers.location)),
            icon = "notice-warning",
        })
    else
        util.removeFile(local_path)
        logger.warn("OPDSBrowser:downloadFile: Request failed:", remote_url, status or code,
                    "block_timeout:", block_timeout, "total_timeout:", total_timeout)
        logger.dbg("OPDSBrowser:downloadFile: Response headers:", headers)
        UIManager:show(InfoMessage:new {
            text = T(_("Could not save file to:\n%1\n%2"),
                BD.filepath(local_path),
                socketutil.describe_error(code, block_timeout, total_timeout)
                    or status or code or _("Network unreachable.")),
        })
    end
end

function OPDSBrowser:onMenuSelect(item)
    if item.acquisitions and item.acquisitions[1] then -- book
        logger.dbg("Downloads available:", item)
        self:showDownloads(item)
    else -- catalog or Search item
        if #self.paths == 0 then -- root list
            if item.idx == 1 then
                if #self.downloads > 0 then
                    self.download_list = self.download_list or OPDSDownloadList:new{ opdsbrowser = self }
                    self.download_list:show()
                end
                return true
            end
            self.root_catalog_title        = item.text
            self.root_catalog_username     = item.username
            self.root_catalog_password     = item.password
            self.root_catalog_raw_names    = item.raw_names
            self.root_catalog_download_dir = item.download_dir
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

function OPDSBrowser:onMenuHold(item)
    if #self.paths > 0 or item.idx == 1 then return true end -- not root list or Downloads item
    local server = self:getServerFromRootItem(item)
    local has_sync_dir = self:getSyncDir(server) and true or false
    local dialog
    dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Set sync folder"),
                    callback = function()
                        if not has_sync_dir then -- Sync buttons are disabled; reopen
                            UIManager:close(dialog)
                        end
                        self:setCatalogSyncDir(item)
                    end,
                },
            },
            {
                {
                    text = _("Force sync"),
                    enabled = has_sync_dir,
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = true
                            self:checkSyncDownload(server)
                        end)
                    end,
                },
                {
                    text = _("Sync"),
                    enabled = has_sync_dir,
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = false
                            self:checkSyncDownload(server)
                        end)
                    end,
                },
            },
            {}, -- separator
            {
                {
                    text = _("Set download folder"),
                    callback = function()
                        self:setCatalogDownloadDir(item)
                    end,
                },
            },
            {
                {
                    text = _("Remove catalog"),
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Remove OPDS catalog?"),
                            ok_text = _("Remove"),
                            ok_callback = function()
                                UIManager:close(dialog)
                                self:deleteCatalog(item)
                            end,
                        })
                    end,
                },
                {
                    text = _("Catalog settings"),
                    callback = function()
                        UIManager:close(dialog)
                        self:addEditCatalog(item)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    return true
end

function OPDSBrowser:onReturn()
    table.remove(self.paths)
    local path = self.paths[#self.paths]
    if path then
        if path.snapshot then
            self.catalog_title = path.snapshot.catalog_title
            self.facet_groups = path.snapshot.facet_groups
            self.search_url = path.snapshot.search_url
            self.alt_search_url = path.snapshot.alt_search_url
            self:setCatalogMenu(path.url, path.snapshot.item_table)
        else
            -- Return to a path that predates session caching.
            self.catalog_title = path.title
            self:updateCatalog(path.url, true)
        end
    else
        -- return to root path, we simply reinit opdsbrowser
        self:init()
    end
    return true
end

function OPDSBrowser:onHoldReturn()
    self:init()
    return true
end

function OPDSBrowser:onNextPage(fill_only)
    if not fill_only then -- not from updateCatalog() that shows its notification
        self:showLoadingNotification()
    end
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
    self:saveCatalogSnapshot()
    if not fill_only then
        -- We also *do* want to paginate, so call the base class.
        Menu.onNextPage(self)
    end
    return true
end

-- sync

function OPDSBrowser:getSyncDir(server)
    return server and server.sync_dir or self.settings.sync_dir
end

function OPDSBrowser:setDefaultSyncDir()
    local title_header = _("Default sync folder:")
    local current_path = self.settings.sync_dir or _("not set")
    local caller_callback = function(path)
        if path ~= current_path then
            self.settings.sync_dir = path
            self._manager.updated = true
        end
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path)
end

function OPDSBrowser:setCatalogSyncDir(item)
    local server = self:getServerFromRootItem(item)
    local title_header = _("Catalog sync folder:")
    local default_path = self.settings.sync_dir or _("not set")
    local current_path = server.sync_dir or default_path
    local caller_callback = function(path)
        if path ~= current_path then
            path = path ~= default_path and path or nil
            server.sync_dir = path
            self._manager.updated = true
        end
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
end

function OPDSBrowser:setSyncFiletypes()
    local dialog
    dialog = InputDialog:new{
        title = _("File types to sync"),
        description = _("A comma separated list of desired filetypes"),
        input = self.settings.filetypes,
        input_hint = _("epub, mobi"),
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
                        local str = dialog:getInputText()
                        self.settings.filetypes = str ~= "" and str or nil
                        self._manager.updated = true
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function OPDSBrowser:setMaxSyncDownload()
    UIManager:show(SpinWidget:new{
        title_text = _("Max number of files"),
        info_text = _("Max number of files to download at a time"),
        value = self.settings.sync_max_dl or 50,
        value_min = 0,
        value_max = 1000,
        value_step = 10,
        value_hold_step = 50,
        default_value = 50,
        wrap = true,
        ok_text = _("Save"),
        callback = function(spin)
            self.settings.sync_max_dl = spin.value
            self._manager.updated = true
        end,
    })
end

function OPDSBrowser:checkSyncDownload(server_to_sync)
    local servers_to_sync = {}
    if server_to_sync then
        table.insert(servers_to_sync, server_to_sync)
    else -- all
        local server_checked
        for _, server in ipairs(self.servers) do
            if server.sync then
                server_checked = true
                if self:getSyncDir(server) then
                    table.insert(servers_to_sync, server)
                end
            end
        end
        if #servers_to_sync == 0 then
            UIManager:show(InfoMessage:new{
                text = server_checked and _("Please choose a folder for sync downloads first")
                                       or _("Please choose catalogs to sync"),
            })
            return
        end
    end

    self.syncing = true
    self.sync_server_list = {}
    local info
    local ok, err = pcall(function()
        info = InfoMessage:new{
            text = _("Synchronizing lists…"),
        }
        UIManager:show(info)
        UIManager:forceRePaint()
        for _, server in ipairs(servers_to_sync) do
            self:fillPendingSyncs(server)
        end
        UIManager:close(info)
        info = nil

        local has_pending_syncs = false
        for _, item in ipairs(self.pending_syncs) do
            if self.sync_server_list[item.catalog] then
                has_pending_syncs = true
                break
            end
        end
        if has_pending_syncs then
            Trapper:wrap(function()
                self:downloadPendingSyncs()
            end)
        else
            UIManager:show(InfoMessage:new{
                text = _("Up to date!"),
            })
        end
    end)
    if info then
        UIManager:close(info)
    end
    self.syncing = false
    if not ok then
        error(err, 0)
    end
end

function OPDSBrowser:fillPendingSyncs(server)
    self.root_catalog_password  = server.password
    self.root_catalog_raw_names = server.raw_names
    self.root_catalog_username  = server.username
    self.root_catalog_title     = server.title
    self.sync_server            = server
    self.sync_server_list       = self.sync_server_list or {}
    self.sync_max_dl            = self.settings.sync_max_dl or 50

    local file_list
    local file_str = self.settings.filetypes
    local new_last_download = nil
    local dl_count = 1
    if file_str then
        file_list = {}
        for filetype in util.gsplit(file_str, ",") do
            file_list[util.trim(filetype)] = true
        end
    end
    local sync_list = self:getSyncDownloadList()
    if sync_list then
        for i, entry in ipairs(sync_list) do
            -- for project gutenberg
            local sub_table = {}
            local item
            if entry.url then
                sub_table = self:getSyncDownloadList(entry.url)
            end
            if #sub_table > 0 then
                -- The first element seems to be most compatible. Second element has most options
                item = sub_table[2] or sub_table[1]
            else
                item = entry
            end
            for j, link in ipairs(item.acquisitions) do
                -- Only save first link in case of several file types
                if i == 1 and j == 1 then
                    new_last_download = link.href
                end
                local filetype = self.getFiletype(link)
                if filetype then
                    if not file_str or file_list and file_list[filetype] then
                        local filename = self:getFileName(entry)
                        local download_path = self:getLocalDownloadPath(filename, filetype, link.href)
                        if dl_count <= self.sync_max_dl then -- Append only max_dl entries... may still have sync backlog
                            table.insert(self.pending_syncs, {
                                file = download_path,
                                url = link.href,
                                username = self.root_catalog_username,
                                password = self.root_catalog_password,
                                catalog = server.url,
                            })
                            dl_count = dl_count + 1
                        end
                        break
                    end
                end
            end
        end
    end
    self.sync_server_list[server.url] = true
    if new_last_download then
        logger.dbg("Updating opds last download for server", server.title, "to", new_last_download)
        server.last_download = new_last_download
        self._manager.updated = true
    end
end

function OPDSBrowser:getSyncDownloadList(url_arg)
    local sync_table = {}
    local fetch_url = url_arg or self.sync_server.url
    local sub_table
    local up_to_date = false
    while #sync_table < self.sync_max_dl and not up_to_date do
        sub_table = self:genItemTableFromURL(fetch_url)
        -- timeout
        if #sub_table == 0 then
            return sync_table
        end
        local count = 1
        local acquisitions_empty = false
        -- For project gutenberg
        while #sub_table[count].acquisitions == 0 do
            if sub_table[count].url and util.stringEndsWith(sub_table[count].url, ".opds") then
                acquisitions_empty = true
                break
            end
            if count == #sub_table then
                return sync_table
            end
            count = count + 1
        end
        -- First entry in table is the newest
        -- If already downloaded, return
        local first_href
        if acquisitions_empty then
            first_href = sub_table[count].url
        else
            first_href = sub_table[1].acquisitions[1].href
        end
        if first_href == self.sync_server.last_download and not self.sync_force then
            return nil
        end
        local href
        for i, entry in ipairs(sub_table) do
            if acquisitions_empty then
                if i >= count then
                    href = entry.url
                else
                    href = nil
                end
            else
                href = entry.acquisitions[1].href
            end
            if href then
                if href == self.sync_server.last_download and not self.sync_force then
                    up_to_date = true
                    break
                else
                    table.insert(sync_table, entry)
                end
            end
        end
        if not sub_table.hrefs.next then
            break
        end
        fetch_url = sub_table.hrefs.next
    end
    return sync_table
end

function OPDSBrowser:downloadPendingSyncs()
    local dl_list = self.pending_syncs
    local function dismissable_download()
        local info = InfoMessage:new{ text = _("Downloading… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()
        local completed, downloaded, duplicate_list = Trapper:dismissableRunInSubprocess(function()
            local dl = {}
            local dupe_list = {}
            for _, item in ipairs(dl_list) do
                if self.sync_server_list[item.catalog] then
                    if lfs.attributes(item.file) and not self.sync_force then
                        table.insert(dupe_list, item)
                    else
                        if self:downloadFile(item.file, item.url, item.username, item.password) then
                            dl[item.file] = true
                        end
                    end
                end
            end
            return dl, dupe_list
        end, info)

        if completed then
            UIManager:close(info)
        end
        local dl_count = 0
        local dl_size = #dl_list
        for i = dl_size, 1, -1 do
            local item = dl_list[i]
            if downloaded and downloaded[item.file] then
                dl_count = dl_count + 1
                table.remove(dl_list, i)
            else -- if subprocess has been interrupted, check for the downloaded file
                local attr = lfs.attributes(item.file)
                if attr then
                    if attr.size > 0 then
                        table.remove(dl_list, i)
                        if attr.modification > os.time() - 300 then -- Only count files touched in the last 5 mins
                            dl_count = dl_count + 1
                        end
                    else -- incomplete download
                        os.remove(item.file)
                    end
                end
            end
        end
        local duplicate_count = duplicate_list and #duplicate_list or 0
        dl_count = dl_count - duplicate_count
        -- Make downloaded count timeout if there's a duplicate file prompt
        local timeout = nil
        if duplicate_count > 0 then
            timeout = 3
        end
        if dl_count > 0 then
            UIManager:show(InfoMessage:new{ text = T(N_("1 book downloaded", "%1 books downloaded", dl_count), dl_count), timeout = timeout,})
        end
        self._manager.updated = true
        return duplicate_list
    end

    local duplicate_list = dismissable_download()
    if duplicate_list and #duplicate_list > 0 then
        local textviewer
        local duplicate_files = { _("These files are already on the device:") }
        for _, entry in ipairs(duplicate_list) do
            table.insert(duplicate_files, entry.file)
        end
        local text = table.concat(duplicate_files, "\n")
        textviewer = TextViewer:new{
            title = _("Duplicate files"),
            text = text,
            buttons_table = {
                {
                    {
                        text = _("Do nothing"),
                        callback = function()
                            textviewer:onClose()
                        end
                    },
                    {
                        text = _("Overwrite"),
                        callback = function()
                            self.sync_force = true
                            textviewer:onClose()
                            for _, entry in ipairs(duplicate_list) do
                                table.insert(dl_list, entry)
                            end
                            Trapper:wrap(function()
                                dismissable_download()
                            end)
                        end
                    },
                    {
                        text = _("Download copies"),
                        callback = function()
                            self.sync_force = true
                            textviewer:onClose()
                            local copy_download_dir, original_dir, copies_dir, copy_download_path
                            copies_dir = "copies"
                            original_dir = util.splitFilePathName(duplicate_list[1].file)
                            copy_download_dir = original_dir .. copies_dir .. "/"
                            util.makePath(copy_download_dir)
                            for _, entry in ipairs(duplicate_list) do
                                local _, file_name = util.splitFilePathName(entry.file)
                                copy_download_path = copy_download_dir .. file_name
                                entry.file = copy_download_path
                                table.insert(dl_list, entry)
                            end
                            Trapper:wrap(function()
                                dismissable_download()
                            end)
                        end
                    },
                },
            },
        }
        UIManager:show(textviewer)
    end
end

return OPDSBrowser
