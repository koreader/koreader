local CalibreMetadata = require("metadata")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

-- get root dir for disk scans
local function getDefaultRootDir()
    if Device:isAndroid() then
        return Device.external_storage()
    elseif Device:isDesktop() then
        return os.getenv("HOME")
    elseif Device:isKindle() then
        return "/mnt/us/documents"
    elseif Device:isRemarkable() then
        return "/home/root"
    elseif Device:isKobo() or Device:isCervantes() then
        return "/mnt"
    else
        return "."
    end
end

-- get books that exactly match the search tag
local function getBooksByTag(t, tag)
    local result = {}
    for _, book in ipairs(t) do
        for __, _tag in ipairs(book.tags) do
            if tag == _tag then
                table.insert(result, book)
            end
        end
    end
    return result
end

-- get books that exactly match the search series
local function getBooksBySeries(t, series)
    local result = {}
    for _, book in ipairs(t) do
        if type(book.series) ~= "function" then
            if book.series == series then
                table.insert(result, book)
            end
        end
    end
    return result
end

-- get tags that partially match the search criteria and their frequency
local function searchByTag(t, query, case_sensitive)
    local freq = {}
    for _, book in ipairs(t) do
        for __, tag in ipairs(book.tags) do
            -- case insensitive
            if not query or (query and string.find(
                string.upper(tag), string.upper(query))) then
                freq[tag] = (freq[tag] or 0) + 1
            end
        end
    end
    return freq
end

-- get series that partially match the search criteria and their frequency
local function searchBySeries(t, query, case_sensitive)
    local freq = {}
    for _, book in ipairs(t) do
        if type(book.series) ~= "function" then
            if not query or (query and string.find(
                string.upper(book.series), string.upper(query))) then
                freq[book.series] = (freq[book.series] or 0) + 1
            end
        end
    end
    return freq
end

-- get book info as one big string with relevant metadata
local function getBookInfo(book)
    -- comma separated elements from a table
    local function getEntries(t)
        if not t then return end
        local id
        for i, v in ipairs(t) do
            if v ~= nil then
                if i == 1 then
                    id = v
                else
                    id = id .. ", " .. v
                end
            end
        end
        return id
    end
    -- all entries can be empty, except size, which is always filled by calibre.
    local title = _("Title:") .. " " .. book.title or "-"
    local authors = _("Author(s):") .. " " .. getEntries(book.authors) or "-"
    local size = _("Size:") .. " " .. string.format("%4.1fM", book.size/1024/1024)
    local tags = getEntries(book.tags)
    if tags then
        tags = _("Tags:") .. " " .. tags
    end
    local series
    if type(book.series) ~= "function" then
        series = _("Series:") .. " " .. book.series
    end
    return string.format("%s\n%s\n%s%s%s", title, authors,
        tags and tags .. "\n" or "",
        series and series .. "\n" or "",
        size)
end

local CalibreSearch = InputContainer:new{
    -- striped books with title, authors, tags, series, book path, library path and bytes in disk.
    books = {},

    -- calibre libraries with *some calibre metadata*. The file could be corrupted
    -- but at least metadata.calibre or .metadata.calibre is present.
    libraries = {},

    -- calibre libraries found in last disk scan
    last_scan = {},

    -- full path of the file that holds calibre libraries in disk
    user_libraries = DataStorage:getSettingsDir() .. "/calibre-libraries.lua",

    -- full path of the file that holds searchable metadata in disk
    user_book_cache = DataStorage:getSettingsDir() .. "/calibre-books.lua",

    -- boolean search options
    search_options = {
        "case_sensitive",
        "cache_metadata",
        "find_by_title",
        "find_by_authors",
        "find_by_path",
    },
}

function CalibreSearch:getMetadata()
    local books = {}
    local enabled_libraries = 0
    for path, enabled in pairs(self.libraries) do
        if enabled then
            if CalibreMetadata:init(path) then
                for _, book in ipairs(CalibreMetadata.books) do
                    local slim_book = {}
                    slim_book.title = book.title
                    slim_book.lpath = book.lpath
                    slim_book.authors = book.authors
                    slim_book.series = book.series
                    slim_book.tags = book.tags
                    slim_book.size = book.size
                    slim_book.rootpath = CalibreMetadata.path
                    table.insert(books, #books + 1, slim_book)
                end
                CalibreMetadata:clean()
                enabled_libraries = enabled_libraries + 1
            end
        end
    end
    logger.dbg(string.format("found metadata for %d books in %d calibre libraries",
        #books, enabled_libraries))
    return books
end

function CalibreSearch:prompt(message)
    local root = getDefaultRootDir()
    if root == "." then
        root = lfs.currentdir()
    end
    local warning = T(_("Scanning libraries can take time. All storage media under %1 will be analyzed"), root)
    if message then
        message = message .. "\n\n" .. warning
    end
    UIManager:show(ConfirmBox:new{
        text = message or warning,
        ok_text = _("Scan") .. " " .. root,
        ok_callback = function()
            self:findCalibre(root)
            UIManager:show(InfoMessage:new{
                text = T(_("Found %1 calibre libraries in %2"), #self.last_scan, root),
                timeout = 2,
            })
            local cache = LuaSettings:open(self.user_libraries)
            for path, _ in pairs(cache.data) do
                cache:delSetting(path)
            end
            for _, dir in ipairs(self.last_scan) do
                cache:saveSetting(dir.path, true)
            end
            cache:close()
            self.libraries = self.last_scan
            self.last_scan = {}
            self.books = {}
        end,
    })
end

-- Find all calibre libraries under a given path, nested libraries not allowed.
function CalibreSearch:findCalibre(root)
    -- protect lfs.dir which will raise error on no-permission directory
    local ok, iter, dir_obj = pcall(lfs.dir, root)
    local contains_metadata = false
    if ok then
        for entity in iter, dir_obj do
            if not contains_metadata then
                if entity ~= "." and entity ~= ".." then
                    local path = root .. "/" .. entity
                    local mode = lfs.attributes(path, "mode")
                    if mode == "file" then
                        if entity == "metadata.calibre" or entity == ".metadata.calibre" then
                            local library = {}
                            library.path = root
                            contains_metadata = true
                            table.insert(self.last_scan, #self.last_scan + 1, library)
                        end
                    elseif mode == "directory" then
                        self:findCalibre(path)
                    end
                end
            end
        end
    end
end

function CalibreSearch:findBooks(t, query)
    -- handle case sensitivity preference
    local function match(s, p)
        if not p or p == "" then return true end
        if self.case_sensitive then
            return string.match(s, p)
        else
            return string.match(string.upper(s), string.upper(p))
        end
    end
    -- handle other search preferences
    local function bookSearch(book, pattern)
        if self.find_by_title and match(book.title, pattern) then
            return true
        end
        if self.find_by_authors then
            for _, author in ipairs(book.authors) do
                if match(author, pattern) then
                    return true
                end
            end
        end
        if self.find_by_path and match(book.lpath, pattern) then
            return true
        end
        return false
    end
    -- performs a book search
    local results = {}
    for i, book in ipairs(t) do
        if bookSearch(book, query) then
            table.insert(results, #results + 1, book)
        end
    end
    return results
end

function CalibreSearch:find(option)
    -- load settings
    for _, opt in pairs(self.search_options) do
        if opt == "case_sensitive" then
            self[opt] = G_reader_settings:isTrue("calibre_search"..opt)
        else
            self[opt] = G_reader_settings:nilOrTrue("calibre_search_"..opt)
        end
    end
    -- sanity check
    logger.dbg("loading libraries from file", self.user_libraries)
    local ok, libs = pcall(dofile, self.user_libraries)
    if ok then
        self.libraries = libs
    else
        logger.warn("no saved libraries in", self.user_libraries)
        self:prompt(_("No calibre libraries"))
        return
    end

    if #self.books == 0 or self.force_rescan then
        self.books = self:getMetadata()
    end
    if #self.books == 0 then
        logger.warn("no metedata to search, aborting")
        self:prompt(_("No metadata found"))
        return
    end

    -- perform search
    local case = self.case_sensitive and "case sensitive" or "case insensitive"
    local query = self.search_value == "" and option ~= "find" and "all" or self.search_value
    if option == "find" then
        logger.info(string.format("Searching %d books by query: %s (options: %s, title: %s, authors: %s, path: %s)",
            #self.books, query, case, tostring(self.find_by_title),
            tostring(self.find_by_authors), tostring(self.find_by_path)))
        local books = self:findBooks(self.books, self.search_value)
        local result = self:bookCatalog(books)
        self:showresults(result)
    else
        logger.info(string.format("Searching %d books by %s: %s (options: %s)",
            #self.books, option, query, case))
        self:browse(option,1)
    end
end

function CalibreSearch:bookCatalog(t)
    local catalog = {}
    for i, book in ipairs(t) do
        local entry = {}
        entry.info = getBookInfo(book)
        entry.path = book.rootpath .. "/" .. book.lpath
        entry.text = book.authors[1] .. ": " .. book.title
        entry.callback = function()
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(book.rootpath .. "/" .. book.lpath)
            self.search_menu:onClose()
        end
        table.insert(catalog, entry)
    end
    return catalog
end

function CalibreSearch:ShowSearch()
    self.search_dialog = InputDialog:new{
        title = _("Search books"),
        input = self.search_value,
        buttons = {
            {
                {
                    text = _("Browse series"),
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "series"
                        self:close()
                    end,
                },
                {
                    text = _("Browse tags"),
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "tags"
                        self:close()
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    -- @translators Search for books in calibre Library, via on-device metadata (as setup by Calibre's 'Send To Device').
                    text = _("Find books"),
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "find"
                        self:close()
                    end,
                },
            },
        },
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function CalibreSearch:close()
    if self.search_value then
        self.search_dialog:onClose()
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 or self.lastsearch ~= "find" then
            self:find(self.lastsearch)
        end
    end
end

function CalibreSearch:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end
    local thumbnail
    local doc = DocumentRegistry:openDocument(item.path)
    if doc then
        if doc.loadDocument then -- CreDocument
            doc:loadDocument(false) -- load only metadata
        end
        thumbnail = doc:getCoverPageImage()
        doc:close()
    end
    local thumbwidth = math.min(240, Screen:getWidth()/3)
    UIManager:show(InfoMessage:new{
        text = item.info,
        image = thumbnail,
        image_width = thumbwidth,
        image_height = thumbwidth/2*3
    })
end

function CalibreSearch:showresults(t)
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    table.sort(t, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:switchItemTable(_("Search Results"), t)
    UIManager:show(menu_container)
end

function CalibreSearch:browse(option, run, chosen)
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    if run == 1 then
        local menu_entries = {}
        local source
        local search_value
        if self.search_value ~= "" then
            search_value = self.search_value
        end
        if option == "tags" then
            source = searchByTag(self.books, search_value)
        elseif option == "series" then
            source = searchBySeries(self.books, search_value)
        end
        for k, v in pairs(source) do
            local entry = {}
            entry.text = string.format("%s (%d)", k, v)
            entry.callback = function()
                self:browse(option, 2, k)
            end
            table.insert(menu_entries, entry)
        end
        table.sort(menu_entries, function(v1,v2) return v1.text < v2.text end)
        self.search_menu:switchItemTable(_("Browse") .. " " .. option, menu_entries)
        UIManager:show(menu_container)
    else
        if option == "tags" then
            self:showresults(self:bookCatalog(getBooksByTag(self.books, chosen)))
        elseif option == "series" then
            self:showresults(self:bookCatalog(getBooksBySeries(self.books, chosen)))
        end
    end
end

return CalibreSearch
