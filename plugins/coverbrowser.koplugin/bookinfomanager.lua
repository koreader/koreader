local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local Mupdf = require("ffi/mupdf")
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("ffi/util")
local splitFilePathName = require("util").splitFilePathName
local _ = require("gettext")
local T = require("ffi/util").template

-- Util functions needed by this plugin, but that may be added to existing base/ffi/ files
local xutil = require("xutil")

-- Database definition
local BOOKINFO_DB_VERSION = "2-20170701"
local BOOKINFO_DB_SCHEMA = [[
    -- For caching book cover and metadata
    CREATE TABLE IF NOT EXISTS bookinfo (
        -- Internal book cache id
        -- (not to be used to identify a book, it may change for a same book)
        bcid                INTEGER PRIMARY KEY AUTOINCREMENT,

        -- File location and filename
        directory           TEXT NOT NULL, -- split by dir/name so we can get all files in a directory
        filename            TEXT NOT NULL, -- and can implement pruning of no more existing files

        -- Extraction status and result
        in_progress         INTEGER,  -- 0 (done), >0 : nb of tries (to avoid re-doing extractions that crashed us)
        unsupported         TEXT,     -- NULL if supported / reason for being unsupported
        cover_fetched       TEXT,     -- NULL / 'Y' = action of fetching cover was made (whether we got one or not)
        has_meta            TEXT,     -- NULL / 'Y' = has metadata (title, authors...)
        has_cover           TEXT,     -- NULL / 'Y' = has cover image (cover_*)
        cover_sizetag       TEXT,     -- 'M' (Medium, MosaicMenuItem) / 's' (small, ListMenuItem)

        -- Other properties that can be set and returned as is (not used here)
        -- If user doesn't want to see these (wrong metadata, offending cover...)
        ignore_meta         TEXT,     -- NULL / 'Y' = ignore these metadata
        ignore_cover        TEXT,     -- NULL / 'Y' = ignore this cover

        -- Book info
        pages               INTEGER,

        -- Metadata (only these are returned by the engines)
        title               TEXT,
        authors             TEXT,
        series              TEXT,
        language            TEXT,
        keywords            TEXT,
        description         TEXT,

        -- Cover image
        cover_w             INTEGER,  -- blitbuffer width
        cover_h             INTEGER,  -- blitbuffer height
        cover_btype         INTEGER,  -- blitbuffer type (internal)
        cover_bpitch        INTEGER,  -- blitbuffer pitch (internal)
        cover_datalen       INTEGER,  -- blitbuffer uncompressed data length
        cover_dataz         BLOB      -- blitbuffer data compressed with zlib
    );
    CREATE UNIQUE INDEX IF NOT EXISTS dir_filename ON bookinfo(directory, filename);

    -- For keeping track of DB schema version
    CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT
    );
    -- this will not override previous version value, so we'll get the old one if old schema
    INSERT OR IGNORE INTO config VALUES ('version', ']] .. BOOKINFO_DB_VERSION .. [[');

]]

local BOOKINFO_COLS_SET = {
        "directory",
        "filename",
        "in_progress",
        "unsupported",
        "cover_fetched",
        "has_meta",
        "has_cover",
        "cover_sizetag",
        "ignore_meta",
        "ignore_cover",
        "pages",
        "title",
        "authors",
        "series",
        "language",
        "keywords",
        "description",
        "cover_w",
        "cover_h",
        "cover_btype",
        "cover_bpitch",
        "cover_datalen",
        "cover_dataz",
    }

local bookinfo_values_sql = {} -- for "VALUES (?, ?, ?,...)" insert sql part
for i=1, #BOOKINFO_COLS_SET do
    table.insert(bookinfo_values_sql, "?")
end

-- Build our most often used SQL queries according to columns
local BOOKINFO_INSERT_SQL = "INSERT OR REPLACE INTO bookinfo " ..
                            "(" .. table.concat(BOOKINFO_COLS_SET, ",") .. ") " ..
                            "VALUES (" .. table.concat(bookinfo_values_sql, ",") .. ")"
local BOOKINFO_SELECT_SQL = "SELECT " .. table.concat(BOOKINFO_COLS_SET, ",") .. " FROM bookinfo " ..
                            "WHERE directory=? and filename=? and in_progress=0"
local BOOKINFO_IN_PROGRESS_SQL = "SELECT in_progress, filename, unsupported FROM bookinfo WHERE directory=? and filename=?"


local BookInfoManager = {}

function BookInfoManager:init()
    self.db_location = DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3"
    self.db_created = false
    self.db_conn = nil
    self.max_extract_tries = 3 -- don't try more than that to extract info from a same book
    self.subprocesses_collector = nil
    self.subprocesses_collect_interval = 10 -- do that every 10 seconds
    self.subprocesses_pids = {}
    self.subprocesses_last_added_ts = nil
    self.subprocesses_killall_timeout_seconds = 300 -- cleanup timeout for stuck subprocesses
    -- 300 seconds should be enough to open and get info from 9-10 books
    -- Whether to use former blitbuffer:scale() (default to using MuPDF)
    self.use_legacy_image_scaling = G_reader_settings:isTrue("legacy_image_scaling")
    -- We will use a temporary directory for crengine cache while indexing
    self.tmpcr3cache = DataStorage:getDataDir() .. "/cache/tmpcr3cache"
end

-- DB management
function BookInfoManager:getDbSize()
    local file_size = lfs.attributes(self.db_location, "size") or 0
    return require("util").getFriendlySize(file_size)
end

function BookInfoManager:createDB()
    local db_conn = SQ3.open(self.db_location)
    -- Less error cases to check if we do it that way
    -- Create it (noop if already there)
    db_conn:exec(BOOKINFO_DB_SCHEMA)
    -- Check version (not updated by previous exec if already there)
    local res = db_conn:exec("SELECT value FROM config where key='version';")
    if res[1][1] ~= BOOKINFO_DB_VERSION then
        logger.warn("BookInfo cache DB schema updated from version ", res[1][1], "to version", BOOKINFO_DB_VERSION)
        logger.warn("Deleting existing", self.db_location, "to recreate it")
        db_conn:close()
        os.remove(self.db_location)
        -- Re-create it
        db_conn = SQ3.open(self.db_location)
        db_conn:exec(BOOKINFO_DB_SCHEMA)
    end
    db_conn:close()
    self.db_created = true
end

function BookInfoManager:openDbConnection()
    if self.db_conn then
        return
    end
    if not self.db_created then
        self:createDB()
    end
    self.db_conn = SQ3.open(self.db_location)
    xutil.sqlite_set_timeout(self.db_conn, 5000) -- 5 seconds

    -- Prepare our most often used SQL statements
    self.set_stmt = self.db_conn:prepare(BOOKINFO_INSERT_SQL)
    self.get_stmt = self.db_conn:prepare(BOOKINFO_SELECT_SQL)
    self.in_progress_stmt = self.db_conn:prepare(BOOKINFO_IN_PROGRESS_SQL)
end

function BookInfoManager:closeDbConnection()
    if self.db_conn then
        self.db_conn:close()
        self.db_conn = nil
    end
end

function BookInfoManager:deleteDb()
    self:closeDbConnection()
    os.remove(self.db_location)
    self.db_created = false
end

function BookInfoManager:compactDb()
    -- Reduce db size (note: "when VACUUMing a database, as much as twice the
    -- size of the original database file is required in free disk space")
    -- By default, sqlite will use a temporary file in /tmp/ . On Kobo, /tmp/
    -- is 16 Mb, and this will crash if DB is > 16Mb. For now, it's safer to
    -- use memory for temp files (which will also cause a crash when DB size
    -- is bigger than available memory...)
    local prev_size = self:getDbSize()
    self:openDbConnection()
    self.db_conn:exec("PRAGMA temp_store = 2") -- use memory for temp files
    -- self.db_conn:exec("VACUUM")
    -- Catch possible "memory or disk is full" error
    local ok, errmsg = pcall(self.db_conn.exec, self.db_conn, "VACUUM") -- this may take some time
    self:closeDbConnection()
    if not ok then
        return T(_("Failed compacting database: %1"), errmsg)
    end
    local cur_size = self:getDbSize()
    return T(_("Cache database size reduced from %1 to %2."), prev_size, cur_size)
end

-- Settings management, stored in 'config' table
function BookInfoManager:loadSettings()
    if lfs.attributes(self.db_location, "mode") ~= "file" then
        -- no db, empty config
        self.settings = {}
        return
    end
    self.settings = {}
    self:openDbConnection()
    local res = self.db_conn:exec("SELECT key, value FROM config")
    local keys = res[1]
    local values = res[2]
    for i, key in ipairs(keys) do
        self.settings[key] = values[i]
    end
end

function BookInfoManager:getSetting(key)
    if not self.settings then
        self:loadSettings()
    end
    return self.settings[key]
end

function BookInfoManager:saveSetting(key, value)
    if not value or value == false or value == "" then
        if lfs.attributes(self.db_location, "mode") ~= "file" then
            -- If no db created, no need to save (and create db) an empty value
            return
        end
    end
    self:openDbConnection()
    local query = "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)"
    local stmt = self.db_conn:prepare(query)
    if value == false then -- convert false to NULL
        value = nil
    elseif value == true then -- convert true to "Y"
        value = "Y"
    end
    stmt:bind(key, value)
    stmt:step() -- commited
    stmt:clearbind():reset() -- cleanup
    -- Reload settings, so we may get (or not if it failed) what we just saved
    self:loadSettings()
end

-- Bookinfo management
function BookInfoManager:getBookInfo(filepath, get_cover)
    local directory, filename = splitFilePathName(filepath)
    self:openDbConnection()
    local row = self.get_stmt:bind(directory, filename):step()
    self.get_stmt:clearbind():reset() -- get ready for next query

    if not row then -- filepath not in db
        return nil
    end

    local bookinfo = {}
    for num, col in ipairs(BOOKINFO_COLS_SET) do
        if col == "pages" then
            -- See http://scilua.org/ljsqlite3.html "SQLite Type Mappings"
            bookinfo[col] = tonumber(row[num]) -- convert cdata<int64_t> to lua number
        else
            bookinfo[col] = row[num] -- as is
        end
        -- specific processing for cover columns
        if col == "cover_w" then
            if not get_cover then
                -- don't bother making a blitbuffer
                break
            end
            bookinfo["cover_bb"] = nil
            if bookinfo["has_cover"] then
                bookinfo["cover_w"] = tonumber(row[num])
                bookinfo["cover_h"] = tonumber(row[num+1])
                local cover_data = xutil.zlib_uncompress(row[num+5], row[num+4])
                row[num+5] = nil -- release memory used by cover_dataz
                -- Blitbuffer.fromstring() expects : w, h, bb_type, bb_data, pitch
                bookinfo["cover_bb"] = Blitbuffer.fromstring(row[num], row[num+1], row[num+2], cover_data, row[num+3])
                -- release memory used by uncompressed data:
                cover_data = nil -- luacheck: no unused
            end
            break
        end
    end
    return bookinfo
end

function BookInfoManager:extractBookInfo(filepath, cover_specs)
    -- This will be run in a subprocess
    -- We use a temporary directory for cre cache (that will not affect parent process),
    -- so we don't fill the main cache with books we're not actually reading
    if not self.cre_cache_overriden then
        -- We need to init engine (if no crengine book has yet been opened),
        -- so it does not reset our temporary cache dir when we first open
        -- a crengine book for extraction.
        require("document/credocument"):engineInit()
        local cre = require "libs/libkoreader-cre"
        -- If we wanted to disallow caching completely:
        -- cre.initCache("", 1024*1024*32) -- empty path = no cache
        -- But it's best to use a cache for quicker and less memory
        -- usage when opening big books:
        cre.initCache(self.tmpcr3cache, 0) -- 0 = previous book caches are removed when opening a book
        self.cre_cache_overriden = true
    end

    local directory, filename = splitFilePathName(filepath)

    -- Initialize the new row that we will INSERT
    local dbrow = { }
    -- Actually no need to initialize with nil values:
    -- for dummy, col in ipairs(BOOKINFO_COLS_SET) do
    --     dbrow[col] = nil
    -- end
    dbrow.directory = directory
    dbrow.filename = filename

    -- To be able to catch a BAD book we have already tried to process but
    -- that made us crash, and that we would try to re-process again, we first
    -- insert a nearly empty row with in_progress = 1 (incremented if previously set)
    -- (This will also flag a book being processed when the user changed paged and
    -- kill the previous page background process, but well...)
    local tried_enough = false
    local prev_tries = 0
    -- Get nb of previous tries if record already there
    self:openDbConnection()
    self.in_progress_stmt:bind(directory, filename)
    local cur_in_progress = self.in_progress_stmt:step()
    self.in_progress_stmt:clearbind():reset() -- get ready for next query
    if cur_in_progress then
        prev_tries = tonumber(cur_in_progress[1])
    end
    -- Increment it and check if we have already tried enough
    if prev_tries < self.max_extract_tries then
        if prev_tries > 0 then
            logger.dbg("Seen", prev_tries, "previous attempts at info extraction", filepath , ", trying again")
        end
        dbrow.in_progress = prev_tries + 1 -- extraction not yet successful
    else
        logger.info("Seen", prev_tries, "previous attempts at info extraction", filepath, ", too many, ignoring it.")
        tried_enough = true
        dbrow.in_progress = 0     -- row will exist, we'll never be called again
        dbrow.unsupported = _("too many interruptions or crashes") -- but caller will now it failed
        dbrow.cover_fetched = 'Y' -- so we don't try again if we're called later with cover_specs
    end
    -- Insert the temporary "in progress" record (or the definitive "unsupported" record)
    for num, col in ipairs(BOOKINFO_COLS_SET) do
        self.set_stmt:bind1(num, dbrow[col])
    end
    self.set_stmt:step() -- commited
    self.set_stmt:clearbind():reset() -- get ready for next query
    if tried_enough then
        return -- Last insert done for this book, we're giving up
    end

    -- Proceed with extracting info
    local document = DocumentRegistry:openDocument(filepath)
    if document then
        if document.loadDocument then -- needed for crengine
            -- Setting a default font before loading document
            -- actually do prevent some crashes
            document:setFontFace(document.default_font)
            document:loadDocument()
            -- Not needed for getting props:
            -- document:render()
            -- It would be needed to get nb of pages, but the nb obtained
            -- by simply calling here document:getPageCount() is wrong,
            -- often 2 to 3 times the nb of pages we see when opening
            -- the document (may be some other cre settings should be applied
            -- before calling render() ?)
        else
            -- for all others than crengine, we seem to get an accurate nb of pages
            local pages = document:getPageCount()
            dbrow.pages = pages
        end
        local props = document:getProps()
        if next(props) then -- there's at least one item
            dbrow.has_meta = 'Y'
        end
        if props.title and props.title ~= "" then dbrow.title = props.title end
        if props.authors and props.authors ~= "" then dbrow.authors = props.authors end
        if props.series and props.series ~= "" then dbrow.series = props.series end
        if props.language and props.language ~= "" then dbrow.language = props.language end
        if props.keywords and props.keywords ~= "" then dbrow.keywords = props.keywords end
        if props.description and props.description ~= "" then dbrow.description = props.description end
        if cover_specs then
            local spec_sizetag = cover_specs.sizetag
            local spec_max_cover_w = cover_specs.max_cover_w
            local spec_max_cover_h = cover_specs.max_cover_h

            dbrow.cover_fetched = 'Y' -- we had a try at getting a cover
            -- XXX make picdocument return a blitbuffer of the image
            local cover_bb = document:getCoverPageImage()
            if cover_bb then
                dbrow.has_cover = 'Y'
                dbrow.cover_sizetag = spec_sizetag
                -- we should scale down the cover to our max size
                local cbb_w, cbb_h = cover_bb:getWidth(), cover_bb:getHeight()
                local scale_factor = 1
                if cbb_w > spec_max_cover_w or cbb_h > spec_max_cover_h then
                    -- scale down if bigger than what we will display
                    scale_factor = math.min(spec_max_cover_w / cbb_w, spec_max_cover_h / cbb_h)
                    cbb_w = math.min(math.floor(cbb_w * scale_factor)+1, spec_max_cover_w)
                    cbb_h = math.min(math.floor(cbb_h * scale_factor)+1, spec_max_cover_h)
                    local new_bb
                    if self.use_legacy_image_scaling then
                        new_bb = cover_bb:scale(cbb_w, cbb_h)
                    else
                        new_bb = Mupdf.scaleBlitBuffer(cover_bb, cbb_w, cbb_h)
                    end
                    cover_bb:free()
                    cover_bb = new_bb
                end
                dbrow.cover_w = cbb_w
                dbrow.cover_h = cbb_h
                dbrow.cover_btype = cover_bb:getType()
                dbrow.cover_bpitch = cover_bb.pitch
                local cover_data = Blitbuffer.tostring(cover_bb)
                cover_bb:free() -- free bb before compressing to save memory
                dbrow.cover_datalen = cover_data:len()
                local cover_dataz = xutil.zlib_compress(cover_data)
                -- release memory used by uncompressed data:
                cover_data = nil -- luacheck: no unused
                dbrow.cover_dataz = SQ3.blob(cover_dataz) -- cast to blob for sqlite
                logger.dbg("cover for", filename, "scaled by", scale_factor, "=>", cbb_w, "x", cbb_h, "(compressed from ", dbrow.cover_datalen, " to ", cover_dataz:len())
            end
        end
        DocumentRegistry:closeDocument(filepath)
    else
        dbrow.unsupported = _("not readable by engine")
        dbrow.cover_fetched = 'Y' -- so we don't try again if we're called later if cover_specs
    end
    dbrow.in_progress = 0 -- extraction completed (successful or definitive failure)
    for num, col in ipairs(BOOKINFO_COLS_SET) do
        self.set_stmt:bind1(num, dbrow[col])
    end
    self.set_stmt:step()
    self.set_stmt:clearbind():reset() -- get ready for next query
end

function BookInfoManager:setBookInfoProperties(filepath, props)
    -- If we need to set column=NULL, use props[column] = false (as
    -- props[column] = nil would make column disappear from props)
    local directory, filename = splitFilePathName(filepath)
    self:openDbConnection()
    -- Let's do multiple one-column UPDATE (easier than building
    -- a multiple columns UPDATE)
    local base_query = "UPDATE bookinfo SET %s=? WHERE directory=? AND filename=?"
    for k, v in pairs(props) do
        local this_prop_query = string.format(base_query, k) -- add column name to query
        local stmt = self.db_conn:prepare(this_prop_query)
        if v == false then -- convert false to nil (NULL)
            v = nil
        end
        stmt:bind(v, directory, filename)
        stmt:step() -- commited
        stmt:clearbind():reset() -- cleanup
    end
end

function BookInfoManager:deleteBookInfo(filepath)
    local directory, filename = splitFilePathName(filepath)
    self:openDbConnection()
    local query = "DELETE FROM bookinfo WHERE directory=? AND filename=?"
    local stmt = self.db_conn:prepare(query)
    stmt:bind(directory, filename)
    stmt:step() -- commited
    stmt:clearbind():reset() -- cleanup
end

function BookInfoManager:removeNonExistantEntries()
    self:openDbConnection()
    local res = self.db_conn:exec("SELECT bcid, directory || filename FROM bookinfo")
    local bcids = res[1]
    local filepaths = res[2]
    local bcids_to_remove = {}
    for i, filepath in ipairs(filepaths) do
        if lfs.attributes(filepath, "mode") ~= "file" then
            table.insert(bcids_to_remove, tonumber(bcids[i]))
        end
    end
    local query = "DELETE FROM bookinfo WHERE bcid=?"
    local stmt = self.db_conn:prepare(query)
    for i=1, #bcids_to_remove do
        stmt:bind(bcids_to_remove[i])
        stmt:step() -- commited
        stmt:clearbind():reset() -- cleanup
    end
    return T(_("Removed %1 / %2 entries from cache."), #bcids_to_remove, #bcids)
end

-- Background extraction management
function BookInfoManager:collectSubprocesses()
    -- We need to regularly watch if a sub-process has terminated by
    -- calling waitpid() so this process does not become a zombie hanging
    -- around till we exit.
    if #self.subprocesses_pids > 0 then
        local i = 1
        while i <= #self.subprocesses_pids do -- clean in-place
            local pid = self.subprocesses_pids[i]
            if xutil.isSubProcessDone(pid) then
                table.remove(self.subprocesses_pids, i)
            else
                i = i + 1
            end
        end
        if #self.subprocesses_pids > 0 then
            -- still some pids around, we'll need to collect again
            self.subprocesses_collector = UIManager:scheduleIn(
                self.subprocesses_collect_interval, function()
                    self:collectSubprocesses()
                end
            )
            -- If we're still waiting for some subprocess, and none have
            -- been submitted for some time, it's that one is stuck (and that
            -- the user has not left FileManager or changed page - that would
            -- have caused a terminateBackgroundJobs() - if we're here, it's
            -- that user has left reader in FileBrower and went away)
            if util.gettime() > self.subprocesses_last_added_ts + self.subprocesses_killall_timeout_seconds then
                logger.warn("Some subprocess were running for too long, killing them")
                self:terminateBackgroundJobs()
                -- we'll collect them next time we're run
            end
        else
            self.subprocesses_collector = nil
            if self.delayed_cleanup then
                self.delayed_cleanup = false
                -- No more subprocesses = no more crengine indexing, we can remove our
                -- temporary cache directory
                self:cleanUp()
            end
        end
    end
end

function BookInfoManager:terminateBackgroundJobs()
    logger.dbg("terminating", #self.subprocesses_pids, "subprocesses")
    for i=1, #self.subprocesses_pids do
        xutil.terminateSubProcess(self.subprocesses_pids[i])
    end
end

function BookInfoManager:isExtractingInBackground()
    return #self.subprocesses_pids > 0
end

function BookInfoManager:extractInBackground(files)
    if #files == 0 then
        return
    end

    -- Terminate any previous extraction background task that would be still running
    self:terminateBackgroundJobs()

    -- Close current handle on sqlite, so it's not shared by both processes
    -- (both processes will re-open one when needed)
    BookInfoManager:closeDbConnection()

    -- Define task that will be run in subprocess
    local task = function()
        logger.dbg("  BG extraction started")
        for idx = 1, #files do
            local filepath = files[idx].filepath
            local cover_specs = files[idx].cover_specs
            logger.dbg("  BG extracting:", filepath)
            self:extractBookInfo(filepath, cover_specs)
            util.usleep(100000) -- give main process 100ms of free cpu to do its processing
        end
        logger.dbg("  BG extraction done")
    end

    self.cleanup_needed = true -- so we will remove temporary cache directory created by subprocess

    -- Run task in sub-process, and remember its pid
    local task_pid = xutil.runInSubProcess(task)
    if not task_pid then
        logger.warn("Failed lauching background extraction sub-process (fork failed)")
        return false -- let caller know it failed
    end
    table.insert(self.subprocesses_pids, task_pid)
    self.subprocesses_last_added_ts = util.gettime()

    -- We need to collect terminated jobs pids (so they do not stay "zombies"
    -- and fill linux processes table)
    -- We set a single scheduled action for that
    if not self.subprocesses_collector then -- there's not one already scheduled
        self.subprocesses_collector = UIManager:scheduleIn(
            self.subprocesses_collect_interval, function()
                self:collectSubprocesses()
            end
        )
    end
    return true
end

function BookInfoManager:cleanUp()
    if #self.subprocesses_pids > 0 then
        -- Some background extraction may still use our tmpcr3cache,
        -- cleanup will be dealt with by BookInfoManager:collectSubprocesses()
        self.delayed_cleanup = true
        return
    end
    if self.cleanup_needed then
        logger.dbg("Removing directory", self.tmpcr3cache)
        util.purgeDir(self.tmpcr3cache)
        self.cleanup_needed = false
    end
end

BookInfoManager:init()

return BookInfoManager
