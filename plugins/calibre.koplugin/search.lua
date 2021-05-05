--[[
    This module implements calibre metadata searching.
--]]

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
local Menu = require("ui/widget/menu")
local Persist = require("persist")
local Screen = require("device").screen
local Size = require("ui/size")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

-- get root dir for disk scans
local function getDefaultRootDir()
    if Device:isCervantes() or Device:isKobo() then
        return "/mnt"
    elseif Device:isEmulator() then
        return lfs.currentdir()
    else
        return Device.home_dir or lfs.currentdir()
    end
end

-- get metadata from calibre libraries
local function getAllMetadata(t)
    local books = {}
    for path, enabled in pairs(t) do
        if enabled and CalibreMetadata:init(path, true) then
            -- calibre BQ driver reports invalid lpath
            if Device:isCervantes() then
                local device_name = CalibreMetadata.drive.device_name
                if device_name and string.match(string.upper(device_name), "BQ") then
                    path = path .. "/Books"
                end
            end
            for _, book in ipairs(CalibreMetadata.books) do
                book.rootpath = path
                table.insert(books, #books + 1, book)
            end
            CalibreMetadata:clean()
        end
    end
    return books
end

-- check if a string matches a query
local function match(str, query, case_insensitive)
    if query and case_insensitive then
        return string.find(string.upper(str), string.upper(query))
    elseif query then
        return string.find(str, query)
    else
        return true
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
        if book.series and book.series ~= rapidjson.null then
            if book.series == series then
                table.insert(result, book)
            end
        end
    end
    return result
end

-- get tags that match the search criteria and their frequency
local function searchByTag(t, query, case_insensitive)
    local freq = {}
    for _, book in ipairs(t) do
        if type(book.tags) == "table" then
            for __, tag in ipairs(book.tags) do
                if match(tag, query, case_insensitive) then
                    freq[tag] = (freq[tag] or 0) + 1
                end
            end
        end
    end
    return freq
end

-- get series that match the search criteria and their frequency
local function searchBySeries(t, query, case_insensitive)
    local freq = {}
    for _, book in ipairs(t) do
        if book.series and book.series ~= rapidjson.null then
            if match(book.series, query, case_insensitive) then
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
    local size = _("Size:") .. " " .. util.getFriendlySize(book.size) or _("Unknown")
    local tags = getEntries(book.tags)
    if tags then
        tags = _("Tags:") .. " " .. tags
    end
    local series
    if book.series and book.series ~= rapidjson.null then
        series = _("Series:") .. " " .. book.series
    end
    return string.format("%s\n%s\n%s%s%s", title, authors,
        tags and tags .. "\n" or "",
        series and series .. "\n" or "",
        size)
end

local CalibreSearch = InputContainer:new{
    books = {},
    libraries = {},
    last_scan = {},
    search_options = {
        "cache_metadata",
        "case_insensitive",
        "find_by_title",
        "find_by_authors",
        "find_by_path",
    },

    cache_dir = DataStorage:getDataDir() .. "/cache/calibre",
    cache_libs = Persist:new{
        path = DataStorage:getDataDir() .. "/cache/calibre/libraries.lua",
    },
    cache_books = Persist:new{
        path = DataStorage:getDataDir() .. "/cache/calibre/books.dat",
        codec = "zstd",
    },
}

function CalibreSearch:ShowSearch()
    self.search_dialog = InputDialog:new{
        title = _("Calibre metadata search"),
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
                    text = _("Search books"),
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self.lastsearch = "find"
                        self:close()
                    end,
                },
            },
        },
        width = math.floor(Screen:getWidth() * 0.8),
        height = math.floor(Screen:getHeight() * 0.2),
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

function CalibreSearch:bookCatalog(t, option)
    local catalog = {}
    local series, subseries
    if option and option == "series" then
        series = true
    end
    for _, book in ipairs(t) do
        local entry = {}
        entry.info = getBookInfo(book)
        entry.path = book.rootpath .. "/" .. book.lpath
        if series then
            local major, minor = string.format("%05.2f", book.series_index):match("([^.]+).([^.]+)")
            if minor ~= "00" then
                subseries = true
            end
            entry.text = string.format("%s.%s | %s - %s", major, minor, book.title, book.authors[1])
        else
            entry.text = string.format("%s - %s", book.title, book.authors[1])
        end
        entry.callback = function()
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("SetupShowReader"))

            self.search_menu:onClose()

            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(book.rootpath .. "/" .. book.lpath)
        end
        table.insert(catalog, entry)
    end
    if series and not subseries then
        for index, entry in ipairs(catalog) do
            catalog[index].text = entry.text:gsub(".00", "", 1)
        end
    end
    return catalog
end

-- find books, series or tags
function CalibreSearch:find(option)
    for _, opt in ipairs(self.search_options) do
        self[opt] = G_reader_settings:nilOrTrue("calibre_search_"..opt)
    end

    if #self.libraries == 0 then
        local libs, err = self.cache_libs:load()
        if not libs then
            logger.warn("no calibre libraries", err)
            self:prompt(_("No calibre libraries"))
            return
        else
            self.libraries = libs
        end
    end

    if #self.books == 0 then
        self.books = self:getMetadata()
    end
    -- this shouldn't happen unless the user disabled all libraries or they are empty.
    if #self.books == 0 then
        logger.warn("no metadata to search, aborting")
        self:prompt(_("No results in metadata"))
        return
    end

    -- measure time elapsed searching
    local start = TimeVal:now()
    if option == "find" then
        local books = self:findBooks(self.search_value)
        local result = self:bookCatalog(books)
        self:showresults(result)
    else
        self:browse(option, 1)
    end
    logger.info(string.format("search done in %.3f milliseconds (%s, %s, %s, %s, %s)",
        TimeVal:getDurationMs(start),
        option == "find" and "books" or option,
        "case sensitive: " .. tostring(not self.case_insensitive),
        "title: " .. tostring(self.find_by_title),
        "authors: " .. tostring(self.find_by_authors),
        "path: " .. tostring(self.find_by_path)))
end

-- find books with current search options
function CalibreSearch:findBooks(query)
    -- handle case sensitivity
    local function bookMatch(s, p)
        if not s or not p then return false end
        if self.case_insensitive then
            return string.match(string.upper(s), string.upper(p))
        else
            return string.match(s, p)
        end
    end
    -- handle other search preferences
    local function bookSearch(book, pattern)
        if self.find_by_title and bookMatch(book.title, pattern) then
            return true
        end
        if self.find_by_authors then
            for _, author in ipairs(book.authors) do
                if bookMatch(author, pattern) then
                    return true
                end
            end
        end
        if self.find_by_path and bookMatch(book.lpath, pattern) then
            return true
        end
        return false
    end
    -- performs a book search
    local results = {}
    for i, book in ipairs(self.books) do
        if bookSearch(book, query) then
            table.insert(results, #results + 1, book)
        end
    end
    return results
end

-- browse tags or series
function CalibreSearch:browse(option, run, chosen)
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
        height = Screen:getHeight() - (Size.margin.fullscreen_popout * 2),
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
        local search_value
        if self.search_value ~= "" then
            search_value = self.search_value
        end
        local name, source
        if option == "tags" then
            name = _("Browse by tags")
            source = searchByTag(self.books, search_value, self.case_insensitive)
        elseif option == "series" then
            name = _("Browse by series")
            source = searchBySeries(self.books, search_value, self.case_insensitive)
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
        self.search_menu:switchItemTable(name, menu_entries)
        UIManager:show(menu_container)
    else
        local results
        if option == "tags" then
            results = getBooksByTag(self.books, chosen)
        elseif option == "series" then
            results = getBooksBySeries(self.books, chosen)
        end
        if results then
            local catalog = self:bookCatalog(results, option)
            self:showresults(catalog, chosen)
        end
    end

end

-- show search results
function CalibreSearch:showresults(t, title)
    if not title then
        title = _("Search results")
    end
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
        height = Screen:getHeight() - (Size.margin.fullscreen_popout * 2),
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
    self.search_menu:switchItemTable(title, t)
    UIManager:show(menu_container)
end

-- prompt the user for a library scan
function CalibreSearch:prompt(message)
    local rootdir = getDefaultRootDir()
    local warning = T(_("Scanning libraries can take time. All storage media under %1 will be analyzed"), rootdir)
    if message then
        message = message .. "\n\n" .. warning
    end
    UIManager:show(ConfirmBox:new{
        text = message or warning,
        ok_text = _("Scan") .. " " .. rootdir,
        ok_callback = function()
            self.libraries = {}
            local count, paths = self:scan(rootdir)

            -- append current wireless dir if it wasn't found on the scan
            -- this will happen if it is in a nested dir.
            local inbox_dir = G_reader_settings:readSetting("inbox_dir")
            if inbox_dir and not self.libraries[inbox_dir] then
                if CalibreMetadata:getDeviceInfo(inbox_dir, "date_last_connected") then
                    self.libraries[inbox_dir] = true
                    count = count + 1
                    paths = paths .. "\n" .. count .. ": " .. inbox_dir
                end
            end

            -- append libraries in different volumes
            local ok, sd_path = Device:hasExternalSD()
            if ok then
                local sd_count, sd_paths = self:scan(sd_path)
                count = count + sd_count
                paths = paths .. "\n" .. _("SD card") .. ": " .. sd_paths
            end

            lfs.mkdir(self.cache_dir)
            self.cache_libs:save(self.libraries)
            self:invalidateCache()
            self.books = self:getMetadata()
            local info_text
            if count == 0 then
                info_text = _("No calibre libraries were found")
            else
                info_text = T(_("Found %1 calibre libraries with %2 books:%3"), count, #self.books, paths)
            end
            UIManager:show(InfoMessage:new{ text = info_text })
        end,
    })
end

function CalibreSearch:scan(rootdir)
    self.last_scan = {}
    self:findCalibre(rootdir)
    local paths = ""
    for i, dir in ipairs(self.last_scan) do
        self.libraries[dir.path] = true
        paths = paths .. "\n" .. i .. ": " .. dir.path
    end
    return #self.last_scan, paths
end

-- find all calibre libraries under a given root dir
function CalibreSearch:findCalibre(root)
    -- protect lfs.dir which will raise error on no-permission directory
    local ok, iter, dir_obj = pcall(lfs.dir, root)
    local contains_metadata = false
    if ok then
        for entity in iter, dir_obj do
            -- nested libraries aren't allowed
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

-- invalidate current cache
function CalibreSearch:invalidateCache()
    self.cache_books:delete()
    self.books = {}
end

-- get metadata from cache or calibre files
function CalibreSearch:getMetadata()
    local start = TimeVal:now()
    local template = "metadata: %d books imported from %s in %.3f milliseconds"

    -- try to load metadata from cache
    if self.cache_metadata then
        local function cacheIsNewer(timestamp)
            local cache_timestamp = self.cache_books:timestamp()
            -- stat returns a true Epoch (UTC)
            if not timestamp or not cache_timestamp then return false end
            local Y, M, D, h, m, s = timestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
            -- calibre also stores this in UTC (c.f., calibre.utils.date.isoformat)...
            -- But os.time uses mktime, which converts it to *local* time...
            -- Meaning we'll have to jump through a lot of stupid hoops to make the two agree...
            local meta_timestamp = os.time({year = Y, month = M, day = D, hour = h, min = m, sec = s})
            -- To that end, compute the local timezone's offset to UTC via strftime's %z token...
            local tz = os.date("%z") -- +hhmm or -hhmm
            -- We deal with a time_t, so, convert that to seconds...
            local tz_sign, tz_hours, tz_minutes = tz:match("([+-])(%d%d)(%d%d)")
            local utc_diff = (tonumber(tz_hours) * 60 * 60) + (tonumber(tz_minutes) * 60)
            if tz_sign == "-" then
                utc_diff = -utc_diff
            end
            meta_timestamp = meta_timestamp + utc_diff
            logger.dbg("CalibreSearch:getMetadata: Cache timestamp   :", cache_timestamp, os.date("!%FT%T.000000+00:00", cache_timestamp), os.date("(%F %T %z)", cache_timestamp))
            logger.dbg("CalibreSearch:getMetadata: Metadata timestamp:", meta_timestamp, timestamp, os.date("(%F %T %z)", meta_timestamp))

            return cache_timestamp > meta_timestamp
        end

        local cache, err = self.cache_books:load()
        if not cache then
            logger.warn("invalid cache:", err)
            self:invalidateCache()
        else
            local is_newer = true
            for path, enabled in pairs(self.libraries) do
                if enabled and not cacheIsNewer(CalibreMetadata:getDeviceInfo(path, "date_last_connected")) then
                    is_newer = false
                    break
                end
            end
            if is_newer then
                logger.info(string.format(template, #cache, "cache", TimeVal:getDurationMs(start)))
                return cache
            else
                logger.warn("cache is older than metadata, ignoring it")
            end
        end
    end

    -- try to load metadata from calibre files and dump it to cache file, if enabled.
    local books = getAllMetadata(self.libraries)
    if self.cache_metadata then
        local serialized_table = {}
        local function removeNull(t)
            for _, key in ipairs({"series", "series_index"}) do
                if t[key] == rapidjson.null then
                    t[key] = nil
                end
            end
            return t
        end
        for index, book in ipairs(books) do
            table.insert(serialized_table, index, removeNull(book))
        end
        lfs.mkdir(self.cache_dir)
        local ok, err = self.cache_books:save(serialized_table)
        if not ok then
            logger.info("Failed to serialize calibre metadata cache:", err)
        end
    end
    logger.info(string.format(template, #books, "calibre", TimeVal:getDurationMs(start)))
    return books
end

return CalibreSearch
