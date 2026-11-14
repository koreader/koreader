--[[--
Dedicated Calibre-Web view: one list of remote and local books with their presence status,
plus connection setup, refresh/scan, downloads, uploads and manual matching.

Setup and compatibility notes:

* Lives in the OPDS plugin (File manager → search menu → Calibre-Web); disabling OPDS disables it too.
* Needs a standard Calibre-Web server with OPDS enabled. Browsing/downloading uses OPDS with HTTP Basic
  authentication; uploading signs in to the web UI (login form + CSRF token), so the account needs the
  upload permission and the server must allow uploads. Single sign-on/OAuth-only logins are not supported.
* Enter the server URL as used in a browser, including any reverse proxy sub-path
  (e.g. `http://192.168.1.10:8083` or `https://example.com/calibre`).
* Several addresses can be saved for the same server (e.g. LAN at home, Tailscale/VPN away) and switched
  from the menu; matches and the cached catalog are shared by all addresses of the server.
* Passwords are kept in memory only unless "Remember password" is checked, in which case they are stored
  unencrypted in `settings/calibreweb.lua`, like OPDS catalog passwords. Cookies are never stored.
  HTTPS certificates (chain and host name) are verified against KOReader's CA bundle.
* Settings and confirmed book matches are in `settings/calibreweb.lua`; the last complete server catalog
  and device scan are cached in `settings/calibreweb_cache.lua`. Desktop Calibre's files are not touched.
* Status is derived from evidence: Both means a confirmed match exists on each side; Local only / Remote
  only need a complete, recent catalog refresh / device scan; anything else is Unknown.
* Not supported: reading progress/annotation sync, deletion, metadata editing, adding formats to existing
  server books. Interrupted uploads are never retried automatically.
--]]

local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CalibreWebClient = require("calibrewebclient")
local CalibreWebIndex = require("calibrewebindex")
local CalibreWebItem = require("calibrewebitem")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local PathChooser = require("ui/widget/pathchooser")
local RenderImage = require("ui/renderimage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local CalibreWebBrowser = Menu:extend{
    title_shrink_font_to_fit = true,
    -- Rows show a cover, so fewer and taller items than a plain list
    items_per_page = 6,
    -- set by caller
    store = nil,
    session = nil, -- in-memory state that outlives the view (password, partial results)
    _manager = nil,
}

local status_labels = {
    both = _("Both"),
    ["local"] = _("Local"),
    remote = _("Remote"),
    unknown = _("Unknown"),
}

local filter_labels = {
    all = _("All"),
    ["local"] = _("Local only"),
    remote = _("Remote only"),
    both = _("Both"),
    unknown = _("Unknown"),
}

local reason_texts = {
    storage_unavailable = _("The storage holding the local copy is not available."),
    remote_unverified = _("The server catalog has not been fully refreshed recently."),
    scan_incomplete = _("Device storage has not been fully scanned."),
    possible_local_copy = _("A local file with a similar title exists, but it has not been confirmed as this book."),
    possible_remote_copy = _("A server book with a similar title exists, but it has not been confirmed as this file."),
    upload_uncertain = _("An upload of this file was interrupted. It may or may not have been stored on the server."),
    upload_unverified = _("This file was uploaded, but the server catalog has not confirmed it yet."),
}

local error_texts = {
    auth = _("The server rejected the username or password."),
    auth_required = _("The server session has expired. Please sign in again."),
    forbidden = _("This account is not allowed to do that on the server."),
    rate_limited = _("Too many attempts. Please wait a minute before trying again."),
    csrf = _("The server rejected the request's security token. Please try again."),
    sso = _("The server redirects to an external sign-in page (single sign-on), which is not supported."),
    unsupported = _("The server's sign-in page has no password form (for example, OAuth only), which is not supported."),
    html = _("The server returned a web page instead of a catalog. A proxy or sign-in page may be in the way."),
    parse = _("The server's catalog could not be read."),
    not_found = _("Not found on the server. Check the server URL and that OPDS is enabled."),
    redirect = _("The server redirected the request. Check that the server URL is the canonical one (for example http vs https)."),
    cycle = _("The server's catalog pages loop back on themselves."),
    too_many_pages = _("The server's catalog has too many pages."),
    tls_unavailable = _("No CA certificate bundle is available, so HTTPS certificates cannot be verified."),
    too_large = _("The file is too large for the server."),
    disk = _("Could not write to the destination folder."),
    truncated = _("The download was incomplete."),
    empty = _("The server sent an empty file."),
    collision = _("Could not find a free file name in the destination folder."),
    foreign_link = _("The download link points outside the configured server."),
    no_dir = _("The destination folder does not exist."),
    cancelled = _("Cancelled."),
    unreadable = _("The file could not be read."),
    server_rejected = _("The server did not accept the file (for example, its format is not allowed for upload). Check the server's messages."),
    unexpected_response = _("The server's response could not be understood."),
}

local function describeError(result)
    local text = error_texts[result.error]
    if not text then
        if result.error == "network" then
            text = result.detail and T(_("Network error: %1"), result.detail) or _("Network error.")
        elseif result.code then
            text = T(_("Server response status: %1."), result.code)
        else
            text = T(_("Error: %1"), tostring(result.error))
        end
    end
    if result.location and (result.error == "redirect" or result.error == "sso") then
        text = text .. "\n\n" .. BD.url(result.location)
    end
    return text
end

local function showInfo(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function CalibreWebBrowser:init()
    self.config = self.store:getConfig()
    self:migrateConfig()
    self.filter = self.session.filter or "all"
    self.title = _("Calibre-Web")
    self.title_bar_left_icon = "appbar.menu"
    self.onLeftButtonTap = function()
        self:showMainMenu()
    end
    self.item_table = {}
    Menu.init(self)
    self:refreshList()
    if not self.config.base_url then
        UIManager:nextTick(function() self:showConnectionDialog() end)
    end
end

-- Session / client -------------------------------------------------------------------------------

function CalibreWebBrowser:getPassword()
    return self.config.password or self.session.password
end

-- Several addresses (e.g. LAN and VPN) can lead to the same server. Matches and caches are keyed by
-- `server_key` (the server's first address), so switching addresses keeps them.
function CalibreWebBrowser:migrateConfig()
    local config = self.config
    if config.base_url and not config.addresses then
        config.addresses = { { name = _("Home"), url = config.base_url } }
        config.active_address = 1
    end
    if config.base_url and not config.server_key then
        config.server_key = config.base_url
    end
end

function CalibreWebBrowser:getActiveAddress()
    local addresses = self.config.addresses or {}
    return addresses[self.config.active_address or 1], addresses
end

function CalibreWebBrowser:getAccountKey()
    if not self.config.base_url then return nil end
    return CalibreWebClient.accountKey(self.config.server_key or self.config.base_url, self.config.username)
end

function CalibreWebBrowser:getAccount()
    local key = self:getAccountKey()
    return key and self.store:getAccount(key)
end

function CalibreWebBrowser:newClient(base_url)
    return CalibreWebClient:new{
        base_url = base_url,
        username = self.config.username,
        password = self:getPassword(),
    }
end

function CalibreWebBrowser:getClient()
    local key = self:getAccountKey()
    if not key then return nil end
    if self.session.client_key ~= key then
        -- Partial results belong to one server account
        self.session.partial_snapshot = nil
    end
    if not (self.session.client and self.session.client_key == key
            and self.session.client.base_url == self.config.base_url) then
        self.session.client = self:newClient(self.config.base_url)
        self.session.client_key = key
    end
    local alt_bases = {}
    for __, address in ipairs(self.config.addresses or {}) do
        if address.url ~= self.config.base_url then table.insert(alt_bases, address.url) end
    end
    self.session.client.alt_bases = alt_bases
    self.session.client.password = self:getPassword()
    return self.session.client
end

function CalibreWebBrowser:getDownloadDir()
    local dir = self.config.download_dir
    if dir and lfs.attributes(dir, "mode") == "directory" then return dir end
    return filemanagerutil.getHomeFolder()
end

-- List -------------------------------------------------------------------------------------------

function CalibreWebBrowser:getRoots()
    return CalibreWebIndex.discoverRoots(Device, filemanagerutil.getHomeFolder(), self.config.extra_roots)
end

function CalibreWebBrowser:deriveRows()
    local key = self:getAccountKey()
    local rows, summary = CalibreWebIndex.derive{
        account = self:getAccount(),
        snapshot = key and self.store:getSnapshot(key),
        partial_snapshot = self.session.partial_snapshot,
        inventory = self.store:getInventory(),
        partial_inventory = self.session.partial_inventory,
    }
    return rows, summary
end

function CalibreWebBrowser:refreshList(keep_page)
    local rows, summary = self:deriveRows()
    self.summary = summary
    local search = self.session.search
    local terms = search and CalibreWebIndex.parseSearch(search.query) or {}
    local items = {}
    for __, row in ipairs(rows) do
        local visible = self.filter == "all" or row.status == self.filter
        if visible and search then
            if search.server_keys then
                -- The server decides what matched (it also searches tags, series, etc.)
                visible = search.server_keys[row.key] == true
            else
                visible = CalibreWebIndex.matchSearch(row, terms)
            end
        end
        if visible then
            local authors = row.authors and #row.authors > 0 and table.concat(row.authors, ", ")
            table.insert(items, {
                text = authors and T("%1 — %2", row.title ~= "" and row.title or _("Untitled"), authors) or row.title,
                mandatory = status_labels[row.status] .. ((row.stale and row.status ~= "unknown") and "*" or ""),
                mandatory_dim = row.status == "unknown",
                row = row,
                sort_key = (row.title or ""):lower(),
            })
        end
    end
    table.sort(items, function(a, b) return a.sort_key < b.sort_key end)
    local count = #items
    -- Always-visible search bar as the first row
    table.insert(items, 1, {
        is_search = true,
        text = search and search.query or _("Search"),
        search = search,
        result_count = count,
    })
    local subtitle = T(_("%1 · %2 books"), filter_labels[self.filter], count)
    local address, addresses = self:getActiveAddress()
    if address and #addresses > 1 then subtitle = address.name .. " · " .. subtitle end
    if search then
        subtitle = subtitle .. " · " .. (search.server_keys and T(_("server search: %1"), search.query)
            or T(_("search: %1"), search.query))
    end
    self:switchItemTable(_("Calibre-Web"), items, keep_page and -1 or 1, nil, subtitle)
end

function CalibreWebBrowser:clearSearch()
    self.session.search = nil
    self:refreshList()
end

-- Main menu --------------------------------------------------------------------------------------

function CalibreWebBrowser:showMainMenu()
    local dialog
    local function button(text, callback, enabled)
        return {{
            text = text,
            enabled = enabled ~= false,
            align = "left",
            callback = function()
                UIManager:close(dialog)
                callback()
            end,
        }}
    end
    local connected = self.config.base_url ~= nil
    dialog = ButtonDialog:new{
        title = self:getCoverageText(),
        title_align = "left",
        use_info_style = true,
        buttons = {
            button(_("Search…"), function() self:showSearchDialog() end),
            {},
            button(_("Refresh server catalog"), function() self:refreshCatalog() end, connected),
            button(_("Scan device storage"), function() self:scanDevice() end),
            {},
            button(T(_("Filter: %1"), filter_labels[self.filter]), function() self:showFilterDialog() end),
            {},
            button(self:getActiveAddress() and T(_("Server address: %1"), self:getActiveAddress().name)
                or _("Server connection"), function()
                if self.config.base_url then self:showAddressesDialog() else self:showConnectionDialog() end
            end),
            button(_("Username and password"), function() self:showConnectionDialog() end, connected),
            button(_("Download folder"), function() self:chooseDownloadDir() end),
            button(_("Storage to scan"), function() self:showRootsDialog() end),
            button(_("Sign out and forget password"), function() self:signOut() end, connected),
        },
        shrink_unneeded_width = true,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

function CalibreWebBrowser:getCoverageText()
    local lines = {}
    local key = self:getAccountKey()
    if not key then
        table.insert(lines, _("Not connected to a server."))
    else
        local address = self:getActiveAddress()
        table.insert(lines, T(_("Server: %1"), (address and (address.name .. " — ") or "") .. BD.url(self.config.base_url)))
        local snapshot = self.store:getSnapshot(key)
        if snapshot then
            table.insert(lines, T(_("Catalog: %1 books, refreshed %2"), snapshot.count or 0,
                os.date("%Y-%m-%d %H:%M", snapshot.fetched_at)))
            if self.summary and self.summary.remote_stale then
                table.insert(lines, _("Catalog is out of date (*): refresh to confirm."))
            end
        else
            table.insert(lines, _("Catalog: not refreshed yet."))
        end
        if self.session.partial_snapshot then
            table.insert(lines, _("Last refresh was incomplete."))
        end
    end
    local inventory = self.store:getInventory()
    if inventory then
        table.insert(lines, T(_("Device: %1 books, scanned %2"), inventory.count or 0,
            os.date("%Y-%m-%d %H:%M", inventory.scanned_at)))
    else
        table.insert(lines, _("Device: not fully scanned yet."))
    end
    if self.session.partial_inventory then
        table.insert(lines, _("Last scan was incomplete."))
    end
    return table.concat(lines, "\n")
end

function CalibreWebBrowser:showFilterDialog()
    local dialog
    local buttons = {}
    for __, f in ipairs({ "all", "both", "local", "remote", "unknown" }) do
        local count = self.summary and (f == "all" and self.summary.total or self.summary[f])
        table.insert(buttons, {{
            text = filter_labels[f] .. (count and (" (" .. count .. ")") or "") .. (f == self.filter and "  ✓" or ""),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self.filter = f
                self.session.filter = f
                self:refreshList()
            end,
        }})
    end
    dialog = ButtonDialog:new{ title = _("Show"), buttons = buttons }
    UIManager:show(dialog)
end

local search_help = _([[Matches title, author, year, format and file name, ignoring case and accents. All words must match.

Refine with author:herbert, title:dune, year:1965 or year:1960-1970, format:epub, status:local (also both, remote, unknown). Use "quotes" for phrases.]])

function CalibreWebBrowser:showSearchDialog()
    local dialog
    local search = self.session.search
    local connected = self.config.base_url ~= nil
    dialog = InputDialog:new{
        title = _("Search books"),
        input = search and search.query or "",
        input_hint = _("Title, author, year…"),
        description = search_help,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Clear"),
                    enabled = search ~= nil,
                    callback = function()
                        UIManager:close(dialog)
                        self:clearSearch()
                    end,
                },
            },
            {
                {
                    text = _("Search server"),
                    enabled = connected,
                    callback = function()
                        local query = dialog:getInputText()
                        UIManager:close(dialog)
                        self:searchServer(query)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = util.trim(dialog:getInputText() or "")
                        UIManager:close(dialog)
                        if query == "" then return self:clearSearch() end
                        self.session.search = { query = query }
                        self:refreshList()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Server search adds positive remote evidence, but can never prove absence
function CalibreWebBrowser:searchServer(query)
    query = util.trim(query or "")
    if query == "" then return self:clearSearch() end
    local client = self:getClient()
    if not client then return self:showConnectionDialog() end
    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            Trapper:info(_("Searching…"))
            local result = client:search(query)
            Trapper:clear()
            if result.error then return showInfo(describeError(result)) end
            local partial = self.session.partial_snapshot or { books = {}, complete = false }
            local keys = {}
            for __, book in ipairs(result.books) do
                if book.key then
                    partial.books[book.key] = book
                    keys[book.key] = true
                end
            end
            self.session.partial_snapshot = partial
            self.session.search = { query = query, server_keys = keys }
            self:refreshList()
            if next(keys) == nil then
                showInfo(T(_("No books on the server match \"%1\"."), query))
            end
        end)
    end)
end

-- Connection -------------------------------------------------------------------------------------

function CalibreWebBrowser:showConnectionDialog()
    local dialog, remember_button
    dialog = MultiInputDialog:new{
        title = _("Calibre-Web server"),
        fields = {
            { text = self.config.base_url or "", hint = _("Server URL, e.g. http://192.168.1.10:8083") },
            { text = self.config.username or "", hint = _("Username") },
            { text = self:getPassword() or "", hint = _("Password"), text_type = "password" },
        },
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Connect"),
                callback = function()
                    local fields = dialog:getFields()
                    local remember = remember_button.checked
                    UIManager:close(dialog)
                    self:saveConnection(fields[1], fields[2], fields[3], remember)
                end,
            },
        }},
    }
    remember_button = CheckButton:new{
        text = _("Remember password (stored unencrypted in KOReader's settings, like OPDS catalog passwords)"),
        checked = self.config.password ~= nil,
        parent = dialog,
    }
    dialog:addWidget(remember_button)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CalibreWebBrowser:saveConnection(url_input, username, password, remember)
    local base_url, err = CalibreWebClient.normalizeBaseUrl(url_input)
    if not base_url then
        local texts = {
            empty = _("Please enter the server URL."),
            scheme = _("Only http:// and https:// server URLs are supported."),
            userinfo = _("Please enter the username and password in their own fields, not in the URL."),
            host = _("The server URL is not valid."),
        }
        return showInfo(texts[err] or texts.host)
    end
    username = util.trim(username or "")
    local function apply()
        local address = self:getActiveAddress()
        if address then
            address.url = base_url
        else
            self.config.addresses = { { name = _("Home"), url = base_url } }
            self.config.active_address = 1
        end
        self.config.base_url = base_url
        self.config.server_key = self.config.server_key or base_url
        self.config.username = username ~= "" and username or nil
        self.config.password = (remember and password ~= "") and password or nil
        self.session.password = password ~= "" and password or nil
        self.session.client = nil
        self.store:saveConfig(self.config)
        self.store:flush()
        self:testConnection()
    end
    if base_url:match("^http://") and password ~= "" then
        UIManager:show(ConfirmBox:new{
            text = _("This server uses plain HTTP: your password will be sent unencrypted over the network.\n\nOnly continue on a network you trust."),
            ok_text = _("Continue"),
            ok_callback = apply,
        })
    else
        apply()
    end
end

function CalibreWebBrowser:testConnection()
    local client = self:getClient()
    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            Trapper:info(_("Connecting…"))
            local result = client:checkConnection()
            Trapper:clear()
            if not result.ok then
                return showInfo(_("Could not connect.") .. "\n\n" .. describeError(result))
            end
            local text = T(_("Connected to %1."), result.title or self.config.base_url)
            if not result.is_calibre_web then
                text = text .. "\n\n" .. _("The server does not identify itself as Calibre-Web: uploads may not work.")
            end
            if not self.config.download_dir then
                text = text .. "\n\n" .. _("Choose a download folder from the menu, or downloads will go to the home folder.")
            end
            text = text .. "\n\n" .. _("Refresh the server catalog now?")
            UIManager:show(ConfirmBox:new{
                text = text,
                ok_text = _("Refresh"),
                ok_callback = function() self:refreshCatalog() end,
            })
        end)
    end)
end

function CalibreWebBrowser:setActiveAddress(index, test)
    local address = self.config.addresses[index]
    if not address then return end
    self.config.active_address = index
    self.config.base_url = address.url
    self.store:saveConfig(self.config)
    self.store:flush()
    self:refreshList(true)
    if test then self:testConnection() end
end

function CalibreWebBrowser:showAddressesDialog()
    local dialog
    local buttons = {}
    local active = self.config.active_address or 1
    for i, address in ipairs(self.config.addresses or {}) do
        table.insert(buttons, {
            {
                text = (i == active and "✓ " or "") .. T("%1 — %2", address.name, BD.url(address.url)),
                align = "left",
                callback = function()
                    UIManager:close(dialog)
                    self:setActiveAddress(i, true)
                end,
            },
            {
                text = _("Edit"),
                callback = function()
                    UIManager:close(dialog)
                    self:showAddressDialog(i)
                end,
            },
        })
    end
    table.insert(buttons, {})
    table.insert(buttons, {{
        text = _("Add address…"),
        callback = function()
            UIManager:close(dialog)
            self:showAddressDialog()
        end,
    }})
    table.insert(buttons, {{
        text = _("Use first reachable address"),
        enabled = #(self.config.addresses or {}) > 1,
        callback = function()
            UIManager:close(dialog)
            self:findReachableAddress()
        end,
    }})
    dialog = ButtonDialog:new{
        title = _("Server addresses") .. "\n" .. _("Ways to reach the same Calibre-Web server, e.g. at home (LAN) and away (VPN such as Tailscale). Book matches and the catalog are shared by all of them."),
        use_info_style = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function CalibreWebBrowser:showAddressDialog(index)
    local address = index and self.config.addresses[index]
    local dialog
    local row = {
        {
            text = _("Cancel"),
            id = "close",
            callback = function() UIManager:close(dialog) end,
        },
    }
    if address and #self.config.addresses > 1 then
        table.insert(row, {
            text = _("Delete"),
            callback = function()
                UIManager:close(dialog)
                table.remove(self.config.addresses, index)
                local active = self.config.active_address or 1
                if active == index then
                    self:setActiveAddress(1)
                else
                    if active > index then self.config.active_address = active - 1 end
                    self.store:saveConfig(self.config)
                    self.store:flush()
                end
            end,
        })
    end
    table.insert(row, {
        text = _("Save"),
        callback = function()
            local fields = dialog:getFields()
            local name = util.trim(fields[1] or "")
            local base_url, err = CalibreWebClient.normalizeBaseUrl(fields[2])
            if not base_url then
                return showInfo(err == "empty" and _("Please enter the server URL.") or _("The server URL is not valid."))
            end
            for i, other in ipairs(self.config.addresses) do
                if i ~= index and other.url == base_url then
                    return showInfo(T(_("This address is already saved as \"%1\"."), other.name))
                end
            end
            UIManager:close(dialog)
            if name == "" then name = T(_("Address %1"), index or (#self.config.addresses + 1)) end
            if address then
                address.name = name
                address.url = base_url
                if index == (self.config.active_address or 1) then
                    self:setActiveAddress(index)
                else
                    self.store:saveConfig(self.config)
                    self.store:flush()
                end
            else
                table.insert(self.config.addresses, { name = name, url = base_url })
                self.store:saveConfig(self.config)
                self.store:flush()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Switch to \"%1\" now?"), name),
                    ok_text = _("Switch"),
                    ok_callback = function() self:setActiveAddress(#self.config.addresses, true) end,
                })
            end
        end,
    })
    dialog = MultiInputDialog:new{
        title = address and _("Edit server address") or _("Add server address"),
        fields = {
            { text = address and address.name or "", hint = _("Name, e.g. Home or Tailscale") },
            { text = address and address.url or "", hint = _("URL, e.g. http://100.101.102.103:8083") },
        },
        buttons = { row },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Tries each saved address in order and switches to the first one that answers.
function CalibreWebBrowser:findReachableAddress()
    local addresses = self.config.addresses or {}
    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            for i, address in ipairs(addresses) do
                if not Trapper:info(T(_("Trying %1…"), address.name)) then return Trapper:clear() end
                local result = self:newClient(address.url):checkConnection()
                if result.ok then
                    Trapper:clear()
                    self:setActiveAddress(i)
                    return showInfo(T(_("Connected through \"%1\"."), address.name))
                end
            end
            Trapper:clear()
            showInfo(_("None of the saved server addresses could be reached."))
        end)
    end)
end

function CalibreWebBrowser:signOut()
    self.config.password = nil
    self.session.password = nil
    self.session.client = nil
    self.store:saveConfig(self.config)
    self.store:flush()
    showInfo(_("Signed out. Book mappings are kept."))
end

function CalibreWebBrowser:chooseDownloadDir()
    UIManager:show(PathChooser:new{
        select_file = false,
        show_files = false,
        path = self:getDownloadDir(),
        onConfirm = function(dir)
            self.config.download_dir = dir
            self.store:saveConfig(self.config)
            self.store:flush()
        end,
    })
end

function CalibreWebBrowser:showRootsDialog()
    local roots, enumeration_complete = self:getRoots()
    local inventory = self.session.partial_inventory or self.store:getInventory()
    local status_texts = {
        ok = _("scanned"),
        partial = _("some folders unreadable"),
        missing = _("not available"),
    }
    local kind_texts = {
        home = _("home folder"),
        device = _("device storage"),
        external = _("external storage"),
        user = _("added manually"),
    }
    local dialog
    local buttons = {}
    for __, root in ipairs(roots) do
        local status = inventory and inventory.roots and inventory.roots[root.path]
        table.insert(buttons, {{
            text = T("%1 (%2, %3)", BD.dirpath(root.path), kind_texts[root.kind] or root.kind,
                status and status_texts[status] or _("not scanned")),
            align = "left",
            enabled = root.kind == "user",
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Stop scanning %1?"), BD.dirpath(root.path)),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        UIManager:close(dialog)
                        for i, path in ipairs(self.config.extra_roots or {}) do
                            if path == root.configured or path == root.path then
                                table.remove(self.config.extra_roots, i)
                                break
                            end
                        end
                        self.store:saveConfig(self.config)
                        self.store:flush()
                    end,
                })
            end,
        }})
    end
    table.insert(buttons, {})
    table.insert(buttons, {{
        text = _("Add folder or storage…"),
        callback = function()
            UIManager:close(dialog)
            UIManager:show(PathChooser:new{
                select_file = false,
                show_files = false,
                path = filemanagerutil.getHomeFolder(),
                onConfirm = function(dir)
                    if dir == "/" then
                        return showInfo(_("The filesystem root cannot be scanned. Choose the storage folder itself."))
                    end
                    self.config.extra_roots = self.config.extra_roots or {}
                    table.insert(self.config.extra_roots, dir)
                    self.store:saveConfig(self.config)
                    self.store:flush()
                end,
            })
        end,
    }})
    local title = _("Storage scanned for books")
    if not enumeration_complete then
        title = title .. "\n" .. _("Other storage (for example USB drives or additional cards) cannot be detected automatically on this device: add it here.")
    end
    dialog = ButtonDialog:new{ title = title, use_info_style = true, buttons = buttons }
    UIManager:show(dialog)
end

-- Refresh / scan ---------------------------------------------------------------------------------

function CalibreWebBrowser:refreshCatalog()
    local client = self:getClient()
    if not client then return self:showConnectionDialog() end
    local key = self:getAccountKey()
    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            Trapper:info(_("Refreshing server catalog…"))
            local snapshot = client:fetchCatalog(function(pages, count)
                return Trapper:info(T(_("Refreshing server catalog…\n%1 books (page %2)\n\nTap to cancel."), count, pages))
            end)
            Trapper:clear()
            local account = self.store:getAccount(key)
            if snapshot.complete then
                self:warnIfDifferentLibrary(account, snapshot)
                self.store:saveSnapshot(key, snapshot)
                self.session.partial_snapshot = nil
                if CalibreWebIndex.reconcileUploads(account, snapshot.books) > 0 then
                    self.store:markDirty()
                end
                -- Drop paths whose remote book was replaced (same id, different UUID)
                for map_key, mapping in pairs(account.mappings) do
                    if mapping.uuid and mapping.id and not snapshot.books[map_key] then
                        for __, book in pairs(snapshot.books) do
                            if book.id == mapping.id and book.uuid ~= mapping.uuid then
                                account.mappings[map_key] = nil
                                self.store:markDirty()
                                break
                            end
                        end
                    end
                end
                self.store:flush()
            else
                -- Keep the previous complete snapshot; the partial one only adds positive evidence
                self.session.partial_snapshot = snapshot
                if snapshot.error ~= "cancelled" then
                    local text = _("The catalog refresh did not complete; the previous complete catalog is kept.")
                        .. "\n\n" .. describeError(snapshot)
                    if snapshot.error == "network" and #(self.config.addresses or {}) > 1 then
                        UIManager:show(ConfirmBox:new{
                            text = text .. "\n\n" .. _("Try the other saved server addresses?"),
                            ok_text = _("Try"),
                            ok_callback = function() self:findReachableAddress() end,
                        })
                    else
                        showInfo(text)
                    end
                end
            end
            self:refreshList(true)
        end)
    end)
end

-- All addresses are assumed to lead to the same library; say so when the evidence disagrees
function CalibreWebBrowser:warnIfDifferentLibrary(account, snapshot)
    if (snapshot.count or 0) == 0 then return end
    local mapped = 0
    for key, mapping in pairs(account.mappings) do
        if mapping.uuid then
            mapped = mapped + 1
            if snapshot.books[key] then return end
        end
    end
    if mapped >= 3 then
        showInfo(_("None of your matched books are in this server's catalog. If this address leads to a different Calibre library, use addresses of a single server only: matches are shared between them."))
    end
end

function CalibreWebBrowser:scanDevice()
    local roots = self:getRoots()
    local previous = self.store:getInventory()
    local skip_paths = { require("datastorage"):getDataDir() }
    Trapper:wrap(function()
        Trapper:info(_("Scanning device storage…"))
        local inventory = CalibreWebIndex.scan{
            roots = roots,
            previous = previous,
            exclude_dirs = FileChooser.exclude_dirs,
            exclude_files = FileChooser.exclude_files,
            skip_paths = skip_paths,
            is_supported = function(path) return DocumentRegistry:hasProvider(path) end,
            should_continue = function(inv)
                return Trapper:info(T(_("Scanning device storage…\n%1 folders, %2 books\n\nTap to cancel."), inv.dirs, inv.count))
            end,
        }
        Trapper:clear()
        if inventory.complete then
            self.store:saveInventory(inventory)
            self.session.partial_inventory = nil
            self.store:flush()
        else
            self.session.partial_inventory = inventory
            if not inventory.cancelled then
                local missing = {}
                for root, status in pairs(inventory.roots) do
                    if status ~= "ok" then table.insert(missing, BD.dirpath(root)) end
                end
                showInfo(_("Some storage could not be fully scanned, so books missing from it are shown as Unknown:")
                    .. "\n" .. table.concat(missing, "\n"))
            end
        end
        self:refreshList(true)
    end)
end

-- Book actions -----------------------------------------------------------------------------------

function CalibreWebBrowser:onMenuSelect(item)
    if item.is_search then
        self:showSearchDialog()
    else
        self:showBookDialog(item.row)
    end
    return true
end

function CalibreWebBrowser:onMenuHold(item)
    if item.is_search then
        if self.session.search then self:clearSearch() else self:showSearchDialog() end
    else
        self:showBookDialog(item.row)
    end
    return true
end

-- Lazily fills in a local file's title/authors/identifiers from cached document properties
function CalibreWebBrowser:getLocalProps(path)
    local ui = self._manager and self._manager.ui
    if not (ui and ui.bookinfo) then return nil end
    local ok, props = pcall(ui.bookinfo.getDocProps, ui.bookinfo, path, nil, true)
    return ok and props or nil
end

function CalibreWebBrowser:showBookDialog(row)
    local lines = {}
    table.insert(lines, T(_("Status: %1"), status_labels[row.status]))
    if row.stale then table.insert(lines, _("The server catalog is out of date.")) end
    if row.reason and reason_texts[row.reason] then table.insert(lines, reason_texts[row.reason]) end
    if row.remote then
        local formats = {}
        for format in pairs(row.remote.formats) do table.insert(formats, format) end
        table.sort(formats)
        table.insert(lines, T(_("Server formats: %1"), #formats > 0 and table.concat(formats, ", ") or _("none")))
    end
    for __, path in ipairs(row.local_paths) do
        local source = row.mapping and row.mapping.files[path] and row.mapping.files[path].source
        table.insert(lines, BD.filepath(path) .. (source and (" (" .. source .. ")") or ""))
    end

    local dialog
    local buttons = {}
    local function add(text, callback, enabled)
        table.insert(buttons, {{
            text = text,
            enabled = enabled ~= false,
            callback = function()
                UIManager:close(dialog)
                callback()
            end,
        }})
    end
    for __, path in ipairs(row.local_paths) do
        local file_name = select(2, util.splitFilePathName(path))
        add(T(_("Open %1"), BD.filename(file_name)), function() self:openFile(path) end)
    end
    if row.remote then
        local formats = {}
        for format, info in pairs(row.remote.formats) do table.insert(formats, { format = format, info = info }) end
        table.sort(formats, function(a, b) return a.format < b.format end)
        for __, f in ipairs(formats) do
            local readable = DocumentRegistry:hasProvider("dummy." .. f.format:lower())
            local have = false
            for ___, path in ipairs(row.local_paths) do
                if util.getFileNameSuffix(path):upper() == f.format then have = true end
            end
            add(T(_("Download %1"), f.format) .. (readable and "" or (" " .. _("(not readable here)")))
                .. (have and (" " .. _("(another copy)")) or ""),
                function() self:downloadBook(row, f.format) end)
        end
        add(_("Match existing local book…"), function() self:matchLocal(row) end)
    end
    if not row.remote and #row.local_paths == 1 then
        local path = row.local_paths[1]
        local pending = row.pending_upload
        add(pending and _("Upload again…") or _("Upload to server…"), function() self:confirmUpload(path, row) end,
            self.config.base_url ~= nil)
        if row.remote_candidates then
            add(_("Match with server book…"), function() self:matchRemote(path, row.remote_candidates) end)
        end
        if pending then
            add(_("Forget interrupted upload"), function()
                self:getAccount().pending_uploads[path] = nil
                self.store:markDirty()
                self.store:flush()
                self:refreshList(true)
            end)
        end
    end
    if row.mapping then
        add(_("Forget match"), function()
            local account = self:getAccount()
            for path in pairs(row.mapping.files) do CalibreWebIndex.unlink(account, row.key, path) end
            self.store:markDirty()
            self.store:flush()
            self:refreshList(true)
        end)
    end
    local title = row.title
    if row.authors and #row.authors > 0 then title = title .. "\n" .. table.concat(row.authors, ", ") end
    dialog = ButtonDialog:new{
        title = title .. "\n\n" .. table.concat(lines, "\n"),
        title_align = "left",
        use_info_style = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function CalibreWebBrowser:openFile(path)
    if lfs.attributes(path, "mode") ~= "file" then
        return showInfo(T(_("File not found:\n%1"), BD.filepath(path)))
    end
    self._manager:openCalibreWebFile(path)
end

function CalibreWebBrowser:downloadBook(row, format)
    local client = self:getClient()
    if not client then return self:showConnectionDialog() end
    local book = row.remote
    local info = book.formats[format]
    local dir = self:getDownloadDir()
    local authors = book.authors and book.authors[1]
    local file_name = (book.title ~= "" and book.title or tostring(book.id or "book"))
        .. (authors and (" - " .. authors) or "") .. "." .. format:lower()
    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            Trapper:info(_("Downloading…"), nil, true)
            local result = client:download(info, dir, file_name)
            Trapper:clear()
            if not result.ok then
                return showInfo(T(_("Could not download %1."), book.title) .. "\n\n" .. describeError(result))
            end
            -- Only a finished, validated file gets a mapping
            CalibreWebIndex.link(self:getAccount(), book, result.path, format, "download")
            self.store:markDirty()
            self.store:flush()
            self:addToPartialInventory(result.path)
            self:refreshList(true)
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(result.path)),
                ok_text = _("Read now"),
                ok_callback = function() self:openFile(result.path) end,
            })
        end)
    end)
end

function CalibreWebBrowser:addToPartialInventory(path)
    local attr = lfs.attributes(path)
    if not attr then return end
    local inventory = self.session.partial_inventory or { files = {}, roots = {}, complete = false }
    inventory.files[path] = { size = attr.size, mtime = attr.modification }
    self.session.partial_inventory = inventory
end

function CalibreWebBrowser:matchLocal(row)
    local function confirm(path)
        local props = self:getLocalProps(path)
        local ids = CalibreWebIndex.parseIdentifiers(props and props.identifiers)
        local uuid = row.remote.uuid and row.remote.uuid:lower()
        local source = "manual"
        if uuid and ids[uuid] then
            source = "uuid"
        else
            for __, scheme in pairs(ids) do
                if scheme == "calibre" then
                    return showInfo(_("This file's embedded Calibre identifier belongs to a different book, so it cannot be matched."))
                end
            end
        end
        CalibreWebIndex.link(self:getAccount(), row.remote, path, util.getFileNameSuffix(path), source)
        self.store:markDirty()
        self.store:flush()
        self:refreshList(true)
    end
    local function chooseFile()
        UIManager:show(PathChooser:new{
            select_directory = false,
            select_file = true,
            path = self:getDownloadDir(),
            file_filter = function(file) return DocumentRegistry:hasProvider(file) end,
            onConfirm = confirm,
        })
    end
    if not row.local_candidates then return chooseFile() end
    local dialog
    local buttons = {}
    for __, path in ipairs(row.local_candidates) do
        table.insert(buttons, {{
            text = BD.filepath(path),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                confirm(path)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Choose another file…"),
        callback = function()
            UIManager:close(dialog)
            chooseFile()
        end,
    }})
    dialog = ButtonDialog:new{
        title = T(_("Which local file is \"%1\"?"), row.remote.title),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function CalibreWebBrowser:matchRemote(path, candidates)
    local key = self:getAccountKey()
    local snapshot = key and self.store:getSnapshot(key)
    local partial = self.session.partial_snapshot
    local dialog
    local buttons = {}
    for __, remote_key in ipairs(candidates) do
        local book = (snapshot and snapshot.books[remote_key]) or (partial and partial.books[remote_key])
        if book then
            local formats = {}
            for format in pairs(book.formats) do table.insert(formats, format) end
            table.insert(buttons, {{
                text = T("%1 — %2 (%3)", book.title, table.concat(book.authors, ", "), table.concat(formats, ", ")),
                align = "left",
                callback = function()
                    UIManager:close(dialog)
                    CalibreWebIndex.link(self:getAccount(), book, path, util.getFileNameSuffix(path), "manual")
                    self.store:markDirty()
                    self.store:flush()
                    self:refreshList(true)
                end,
            }})
        end
    end
    dialog = ButtonDialog:new{ title = _("Which server book is this file?"), buttons = buttons }
    UIManager:show(dialog)
end

-- Upload -----------------------------------------------------------------------------------------

function CalibreWebBrowser:confirmUpload(path, row)
    local file_name = select(2, util.splitFilePathName(path))
    local text = T(_("Upload %1 to %2?\n\nThis adds a new book to the server's library."), BD.filename(file_name),
        BD.url(self.config.base_url))
    if row.pending_upload then
        text = text .. "\n\n" .. _("A previous upload of this file was interrupted and may already be on the server. Refresh the server catalog first to avoid a duplicate.")
    end
    if row.remote_candidates then
        local format = util.getFileNameSuffix(path):upper()
        local key = self:getAccountKey()
        local snapshot = key and self.store:getSnapshot(key)
        local same_format = false
        for __, remote_key in ipairs(row.remote_candidates) do
            local book = snapshot and snapshot.books[remote_key]
            if book and book.formats[format] then same_format = true end
        end
        text = text .. "\n\n" .. (same_format
            and _("The server already has a book with a similar title in this format. Uploading will likely create a duplicate. Consider matching it instead.")
            or _("The server has a book with a similar title. Uploading creates a separate book; adding formats to existing books is not supported."))
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Upload"),
        ok_callback = function() self:upload(path) end,
    })
end

function CalibreWebBrowser:ensureLoggedIn(client, callback)
    if client.logged_in then return callback() end
    local function login()
        Trapper:wrap(function()
            Trapper:info(_("Signing in…"), nil, true)
            local result = client:login()
            Trapper:clear()
            if not result.ok then
                return showInfo(_("Could not sign in.") .. "\n\n" .. describeError(result))
            end
            callback()
        end)
    end
    if client.password then return login() end
    local dialog
    dialog = InputDialog:new{
        title = T(_("Password for %1"), self.config.username or ""),
        text_type = "password",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = _("Sign in"),
                is_enter_default = true,
                callback = function()
                    local password = dialog:getInputText()
                    UIManager:close(dialog)
                    self.session.password = password
                    client.password = password
                    login()
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CalibreWebBrowser:upload(path)
    local client = self:getClient()
    if not client then return self:showConnectionDialog() end
    local file_name = select(2, util.splitFilePathName(path))
    local format = util.getFileNameSuffix(path):upper()
    NetworkMgr:runWhenConnected(function()
        self:ensureLoggedIn(client, function()
            Trapper:wrap(function()
                Trapper:info(_("Uploading…"), nil, true)
                local result = client:upload(path, file_name)
                local account = self:getAccount()
                if result.status == "uploaded" then
                    account.pending_uploads[path] = { status = "unverified", format = format, book_id = result.book_id, at = os.time() }
                    self.store:markDirty()
                    -- Targeted verification: find the new book's identity and format
                    Trapper:info(_("Verifying upload…"), nil, true)
                    local verified = self:verifyUpload(client, result.book_id, format, path)
                    Trapper:clear()
                    self.store:flush()
                    self:refreshList(true)
                    showInfo(verified and _("Upload complete and verified on the server.")
                        or _("The server accepted the upload, but it could not be verified yet. Refresh the server catalog to confirm it."))
                elseif result.status == "uncertain" then
                    account.pending_uploads[path] = { status = "uncertain", format = format, at = os.time() }
                    self.store:markDirty()
                    self.store:flush()
                    Trapper:clear()
                    self:refreshList(true)
                    showInfo(_("The upload was interrupted after the file was sent. It may or may not be on the server: refresh the server catalog before trying again.")
                        .. "\n\n" .. describeError(result))
                else
                    Trapper:clear()
                    showInfo(_("The file was not uploaded.") .. "\n\n" .. describeError(result))
                end
            end)
        end)
    end)
end

-- Confirms an upload through the JSON book list and OPDS search, then commits the mapping
function CalibreWebBrowser:verifyUpload(client, book_id, format, path)
    local info = client:lookupBookById(book_id)
    if not info or not info.title then return false end
    local result = client:search(info.title)
    if result.error then return false end
    for __, book in ipairs(result.books) do
        if book.id == book_id and book.formats[format] and (not info.uuid or info.uuid == book.uuid) then
            CalibreWebIndex.link(self:getAccount(), book, path, format, "upload")
            local partial = self.session.partial_snapshot or { books = {}, complete = false }
            partial.books[book.key] = book
            self.session.partial_snapshot = partial
            self.store:markDirty()
            return true
        end
    end
    logger.dbg("CalibreWeb: uploaded book not found in search yet", book_id)
    return false
end

-- Covers -----------------------------------------------------------------------------------------

function CalibreWebBrowser:getCoverCacheDir()
    local dir = require("datastorage"):getDataDir() .. "/cache/calibreweb-covers"
    if lfs.attributes(dir, "mode") ~= "directory" then util.makePath(dir) end
    return dir
end

-- Cache file per server account, book and catalog timestamp, so changed covers are fetched again
function CalibreWebBrowser:getCoverPath(row)
    local book = row.remote
    if not (book and book.cover_href) then return nil end
    local key = md5((self:getAccountKey() or "") .. "|" .. row.key .. "|" .. (book.updated or ""))
    return self:getCoverCacheDir() .. "/" .. key .. ".img"
end

local function scaleToFit(bb, max_w, max_h)
    if not bb then return nil end
    local bw, bh = bb:getWidth(), bb:getHeight()
    local scale = math.min(max_w / bw, max_h / bh)
    return RenderImage:scaleBlitBuffer(bb, math.max(1, bw * scale), math.max(1, bh * scale), true)
end

--- Returns a scaled cover BlitBuffer, false when there is none, or nil while it still needs fetching.
function CalibreWebBrowser:getCover(row, max_w, max_h)
    local cache = self.cover_bbs
    local path = self:getCoverPath(row)
    -- Keyed by cache file, so a refreshed catalog with a new or changed cover isn't masked
    local cache_key = path or ("nocover:" .. row.key)
    local cached = cache[cache_key]
    if cached ~= nil then return cached end
    if path and lfs.attributes(path, "mode") == "file" then
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false)
        cached = ok and scaleToFit(bb, max_w, max_h) or false
    elseif path and not self.cover_failed[path] then
        return nil
    elseif #row.local_paths > 0 and self.bookinfo_manager then
        -- Local books: only covers CoverBrowser already extracted, never open documents here
        local ok, info = pcall(self.bookinfo_manager.getBookInfo, self.bookinfo_manager, row.local_paths[1], true)
        cached = ok and info and info.cover_bb and scaleToFit(info.cover_bb, max_w, max_h) or false
    else
        cached = false
    end
    cache[cache_key] = cached
    return cached
end

-- Downloads missing covers of the visible page one at a time, without prompting for network
function CalibreWebBrowser:scheduleCoverFetch(pending)
    if #pending == 0 or not NetworkMgr:isConnected() then return end
    local client = self:getClient()
    if not client then return end
    self.cover_generation = (self.cover_generation or 0) + 1
    local generation = self.cover_generation
    local function fetchNext()
        if self.cover_generation ~= generation or self.closed then return end
        local row = table.remove(pending, 1)
        if not row then return end
        local path = self:getCoverPath(row)
        if not client:fetchCover(row.remote.cover_href, path) then self.cover_failed[path] = true end
        if self.cover_generation ~= generation or self.closed then return end
        self:updateItems(nil, true)
        -- updateItems() started a new generation for the remaining covers
    end
    UIManager:scheduleIn(0.2, fetchNext)
end

function CalibreWebBrowser:freeCovers()
    for key, bb in pairs(self.cover_bbs or {}) do
        if bb then bb:free() end
        self.cover_bbs[key] = nil
    end
end

-- Same contract as Menu:updateItems, with cover rows instead of MenuItem
function CalibreWebBrowser:updateItems(select_number, no_recalculate_dimen)
    if not self.cover_bbs then
        self.cover_bbs = {}
        self.cover_failed = {}
        local ok, BookInfoManager = pcall(require, "bookinfomanager")
        self.bookinfo_manager = ok and BookInfoManager or nil
    end
    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self:_recalculateDimen(no_recalculate_dimen)

    local cover_w, cover_h = CalibreWebItem.getCoverSize(self.item_dimen.h)
    local idx_offset = (self.page - 1) * self.perpage
    local pending = {}
    for idx = 1, self.perpage do
        local index = idx_offset + idx
        local item = self.item_table[index]
        if item == nil then break end
        item.idx = index
        if index == self.itemnumber then select_number = idx end
        local item_widget
        if item.is_search then
            item_widget = CalibreWebItem.SearchBar:new{
                entry = item,
                menu = self,
                show_parent = self.show_parent,
                dimen = self.item_dimen:copy(),
            }
        else
            local cover_bb = self:getCover(item.row, cover_w, cover_h)
            if cover_bb == nil then table.insert(pending, item.row) end
            item_widget = CalibreWebItem:new{
                entry = item,
                menu = self,
                show_parent = self.show_parent,
                dimen = self.item_dimen:copy(),
                cover_bb = cover_bb or nil,
            }
        end
        table.insert(self.item_group, item_widget)
        table.insert(self.layout, { item_widget })
    end

    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()
    UIManager:setDirty(self.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(self.dimen) or self.dimen
    end)
    self:scheduleCoverFetch(pending)
end

function CalibreWebBrowser:onCloseWidget()
    self.closed = true
    self.store:flush()
    self:freeCovers()
    Menu.onCloseWidget(self)
end

return CalibreWebBrowser
