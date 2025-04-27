local BD = require("ui/bidi")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local Math = require("optmath")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local ReaderProgress = require("readerprogress")
local ReadHistory = require("readhistory")
local Screensaver = require("ui/screensaver")
local SQ3 = require("lua-ljsqlite3/init")
local SyncService = require("frontend/apps/cloudstorage/syncservice")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = FFIUtil.template

local statistics_dir = DataStorage:getDataDir() .. "/statistics/"
local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local MAX_PAGETURNS_BEFORE_FLUSH = 50
local DEFAULT_MIN_READ_SEC = 5
local DEFAULT_MAX_READ_SEC = 120
local DEFAULT_CALENDAR_START_DAY_OF_WEEK = 2 -- Monday
local DEFAULT_CALENDAR_NB_BOOK_SPANS = 3

-- Current DB schema version
local DB_SCHEMA_VERSION = 20221111

-- This is the query used to compute the total time spent reading distinct pages of the book,
-- capped at self.settings.max_sec per distinct page.
-- c.f., comments in insertDB
local STATISTICS_SQL_BOOK_CAPPED_TOTALS_QUERY = [[
    SELECT count(*),
           sum(durations)
    FROM (
        SELECT min(sum(duration), %d) AS durations
        FROM page_stat
        WHERE id_book = %d
        GROUP BY page
    );
]]

-- As opposed to the uncapped version
local STATISTICS_SQL_BOOK_TOTALS_QUERY = [[
    SELECT count(DISTINCT page),
           sum(duration)
    FROM   page_stat
    WHERE  id_book = %d;
]]

local ReaderStatistics = Widget:extend{
    name = "statistics",
    start_current_period = 0,
    preserved_start_current_period = nil, -- should stay a class property
    curr_page = 0,
    id_curr_book = nil,
    is_enabled = nil,
    convert_to_db = nil, -- true when migration to DB has been done
    pageturn_count = 0,
    mem_read_time = 0,
    mem_read_pages = 0,
    book_read_pages = 0,
    book_read_time = 0,
    avg_time = nil,
    page_stat = nil, -- Dictionary, indexed by page (hash), contains a list (array) of { timestamp, duration } tuples.
    data = nil, -- table
    doc_md5 = nil,
}

-- NOTE: This is used in a migration script by ui/data/onetime_migration,
--       which is why it's public.
ReaderStatistics.default_settings = {
    min_sec = DEFAULT_MIN_READ_SEC,
    max_sec = DEFAULT_MAX_READ_SEC,
    freeze_finished_books = false,
    is_enabled = true,
    convert_to_db = nil,
    calendar_start_day_of_week = DEFAULT_CALENDAR_START_DAY_OF_WEEK,
    calendar_nb_book_spans = DEFAULT_CALENDAR_NB_BOOK_SPANS,
    calendar_show_histogram = true,
    calendar_browse_future_months = false,

    -- Check the help message in the menu registration below for more info
    -- These should be XOR, if both happen to be true(manually editing the settings file),
    -- divide takes prio and we'll disable duplication
    dual_page_mode_divide_duration_by_two = false,
    dual_page_mode_duplicate_duration = false,
}

function ReaderStatistics:onDispatcherRegisterActions()
    Dispatcher:registerAction("enable_statistics",
        {category="string", event="ToggleStatistics", title=_("Reading statistics"), general=true,
        args={true, false}, toggle={_("enable"), _("disable")}, arg=false})
    Dispatcher:registerAction("toggle_statistics",
        {category="none", event="ToggleStatistics", title=_("Reading statistics: toggle"), general=true})
    Dispatcher:registerAction("reading_progress",
        {category="none", event="ShowReaderProgress", title=_("Reading statistics: show progress"), general=true})
    Dispatcher:registerAction("stats_time_range",
        {category="none", event="ShowTimeRange", title=_("Reading statistics: show time range"), general=true})
    Dispatcher:registerAction("stats_calendar_view",
        {category="none", event="ShowCalendarView", title=_("Reading statistics: show calendar view"), general=true})
    Dispatcher:registerAction("stats_calendar_day_view",
        {category="none", event="ShowCalendarDayView", title=_("Reading statistics: show today's timeline"), general=true})
    Dispatcher:registerAction("stats_sync",
        {category="none", event="SyncBookStats", title=_("Reading statistics: synchronize"), general=true, separator=true})
    Dispatcher:registerAction("book_statistics",
        {category="none", event="ShowBookStats", title=_("Reading statistics: current book"), reader=true})
end

function ReaderStatistics:init()
    if self.document and self.document.is_pic then
        return -- disable in PIC documents
    end

    self.is_doc = false
    self.is_doc_not_frozen = false -- freeze finished books statistics

    -- Placeholder until onReaderReady
    self.data = {
        title = "",
        authors = "N/A",
        language = "N/A",
        series = "N/A",
        performance_in_pages = {},
        total_time_in_sec = 0,
        highlights = 0,
        notes = 0,
        pages = 0,
    }

    self.start_current_period = os.time()
    if ReaderStatistics.preserved_start_current_period then
        self.start_current_period = ReaderStatistics.preserved_start_current_period
        ReaderStatistics.preserved_start_current_period = nil
    end
    self:resetVolatileStats()

    self.settings = G_reader_settings:readSetting("statistics", self.default_settings)

    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:checkInitDatabase()
    BookStatusWidget.getStats = function()
        return self:getStatsBookStatus(self.id_curr_book, self.settings.is_enabled)
    end
    ReaderFooter.getAvgTimePerPage = function()
        if self.settings.is_enabled then
            return self.avg_time
        end
    end
    Screensaver.getAvgTimePerPage = function()
        if self.settings.is_enabled then
            return self.avg_time
        end
    end
    Screensaver.getReaderProgress = function()
        self:insertDB()
        local current_duration, current_pages = self:getCurrentBookStats()
        local today_duration, today_pages = self:getTodayBookStats()
        local dates_stats = self:getReadingProgressStats(7)
        local readingprogress
        if dates_stats then
            readingprogress = ReaderProgress:new{
                dates = dates_stats,
                current_duration = current_duration,
                current_pages = current_pages,
                today_duration = today_duration,
                today_pages = today_pages,
                readonly = true,
            }
        end
        return readingprogress
    end
end

function ReaderStatistics:initData()
    self.is_doc = true
    self.is_doc_not_finished = self.ui.doc_settings:readSetting("summary").status ~= "complete"
    self.is_doc_not_frozen = self.is_doc_not_finished or not self.settings.freeze_finished_books

    -- first execution
    local book_properties = self.ui.doc_props
    self.data.title = book_properties.display_title
    self.data.authors = book_properties.authors or "N/A"
    self.data.language = book_properties.language or "N/A"
    local series
    if book_properties.series then
        series = book_properties.series
        if book_properties.series_index then
            series = series .. " #" .. book_properties.series_index
        end
    end
    self.data.series = series or "N/A"

    self.data.pages = self.document:getPageCount()
    -- Update these numbers to what's actually stored in the settings
    self.data.highlights, self.data.notes = self.ui.annotation:getNumberOfHighlightsAndNotes()
    self.id_curr_book = self:getIdBookDB()
    if not self.id_curr_book then return end
    self.book_read_pages, self.book_read_time = self:getPageTimeTotalStats(self.id_curr_book)
    if self.book_read_pages > 0 then
        self.avg_time = self.book_read_time / self.book_read_pages
    else
        -- NOTE: Possibly less weird-looking than initializing this to 0?
        self.avg_time = math.floor(0.50 * self.settings.max_sec)
        logger.dbg("ReaderStatistics: Initializing average time per page at 50% of the max value, i.e.,", self.avg_time)
    end
end

function ReaderStatistics:isEnabled()
    return self.settings.is_enabled and self.is_doc
end

function ReaderStatistics:isEnabledAndNotFrozen()
    return self.settings.is_enabled and self.is_doc_not_frozen
end

-- Reset the (volatile) stats on page count changes (e.g., after a font size update)
function ReaderStatistics:onDocumentRerendered()
    -- Note: this is called *after* onPageUpdate(new current page in new page count), which
    -- has updated the duration for (previous current page in old page count) and created
    -- a tuple for (new current page) with a 0-duration.
    -- The insertDB() call below will save the previous page stat correctly with the old
    -- page count, and will drop the new current page stat.
    -- Only after this insertDB(), self.data.pages is updated with the new page count.
    --
    -- To make this clearer, here's what happens with an example:
    -- - We were reading page 127/200 with latest self.page_stat[127]={..., {now-35s, 0}}
    -- - Increasing font size, re-rendering... going to page 153/254
    -- - OnPageUpdate(153) is called:
    --   - it updates duration in self.page_stat[127]={..., {now-35s, 35}}
    --   - it adds/creates self.page_stat[153]={..., {now, 0}}
    --   - it sets self.curr_page=153
    --   - (at this point, we don't know the new page count is 254)
    -- - OnDocumentRerendered() is called:
    --   - insertDB() is called, which will still use the previous self.data.pages=200 as the
    --     page count, and will go at inserting or not in the DB:
    --       - (127, now-35s, 35, 200) inserted
    --       - (153, now, 0, 200) not inserted as 0-duration (and using 200 for its associated
    --         page count would be erroneous)
    --     and will restore self.page_stat[153]={{now, 0}}
    --   - we only then update self.data.pages=254 as the new page count
    -- - 5 minutes later, on the next insertDB(), (153, now-5mn, 42, 254) will be inserted in DB

    local new_pagecount = self.document:getPageCount()

    if new_pagecount ~= self.data.pages then
        logger.dbg("ReaderStatistics: Pagecount change, flushing volatile book statistics")
        -- Flush volatile stats to DB for current book, and update pagecount and average time per page stats
        self:insertDB(new_pagecount)
    end

    -- Update our copy of the page count
    self.data.pages = new_pagecount
end

function ReaderStatistics:onDocumentPartiallyRerendered(first_partial_rerender)
    if not first_partial_rerender then return end -- already done
    -- Override :onPageUpdate() to not account page changes from now on
    self.onPageUpdate = function(this, pageno)
        if pageno == false then -- happens from onCloseDocument
            -- We need to call the original one to get saved previous statistics correct
            return ReaderStatistics.onPageUpdate(this, false)
        end
        return
    end
end

function ReaderStatistics:onPreserveCurrentSession()
    -- Can be called before ReaderUI:reloadDocument() to not reset the current session
    ReaderStatistics.preserved_start_current_period = self.start_current_period
end

function ReaderStatistics:resetVolatileStats(now_ts)
    -- Computed by onPageUpdate
    self.pageturn_count = 0
    self.mem_read_time = 0
    self.mem_read_pages = 0

    -- Volatile storage pending flush to db
    self.page_stat = {}

    -- Re-seed the volatile stats with minimal data about the current page.
    -- If a timestamp is passed, it's the caller's responsibility to ensure that self.curr_page is accurate.
    if now_ts then
        self.page_stat[self.curr_page] = { { now_ts, 0 } }
    end
end

function ReaderStatistics:getStatsBookStatus(id_curr_book, stat_enable)
    if not stat_enable or id_curr_book == nil then
        return {}
    end

    self:insertDB()
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = %d
                    GROUP  BY dates
               );
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_curr_book))
    local total_read_pages, total_time_book = conn:rowexec(string.format(STATISTICS_SQL_BOOK_TOTALS_QUERY, id_curr_book))
    conn:close()

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    return  {
        days = tonumber(total_days),
        time = tonumber(total_time_book),
        pages = tonumber(total_read_pages),
    }
end

function ReaderStatistics:checkInitDatabase()
    local conn = SQ3.open(db_location)
    if self.settings.convert_to_db then      -- if conversion to sqlite DB has already been done
        if not conn:exec("PRAGMA table_info('book');") then
            UIManager:show(ConfirmBox:new{
                text = T(_([[
Cannot open database in %1.
The database may have been moved or deleted.
Do you want to create an empty database?
]]),
                        BD.filepath(db_location)),
                cancel_text = _("Close"),
                cancel_callback = function()
                    return
                end,
                ok_text = _("Create"),
                ok_callback = function()
                    local conn_new = SQ3.open(db_location)
                    self:createDB(conn_new)
                    conn_new:close()
                    UIManager:show(InfoMessage:new{text =_("A new empty database has been created."), timeout = 3 })
                    if self.document then
                        self:initData()
                    end
                end,
            })
        end

        -- Check if we need to migrate to a newer schema
        local db_version = tonumber(conn:rowexec("PRAGMA user_version;"))
        if db_version < DB_SCHEMA_VERSION then
            logger.info("ReaderStatistics: Migrating DB from schema", db_version, "to schema", DB_SCHEMA_VERSION, "...")
            -- Backup the existing DB first
            conn:close()
            local bkp_db_location = db_location .. ".bkp." .. db_version .. "-to-" .. DB_SCHEMA_VERSION
            -- Don't overwrite an existing backup
            if lfs.attributes(bkp_db_location, "mode") == "file" then
                logger.warn("ReaderStatistics: A DB backup from schema", db_version, "to schema", DB_SCHEMA_VERSION, "already exists!")
            else
                FFIUtil.copyFile(db_location, bkp_db_location)
                logger.info("ReaderStatistics: Old DB backed up as", bkp_db_location)
            end

            conn = SQ3.open(db_location)

            if db_version < 20201010 then
                self:upgradeDBto20201010(conn)
            end

            if db_version < 20201022 then
                self:upgradeDBto20201022(conn)
            end

            if db_version < 20221111 then
                self:upgradeDBto20221111(conn)
            end

            -- Get back the space taken by the deleted page_stat table
            conn:exec("PRAGMA temp_store = 2;") -- use memory for temp files
            local ok, errmsg = pcall(conn.exec, conn, "VACUUM;") -- this may take some time
            if not ok then
                logger.warn("Failed compacting statistics database:", errmsg)
            end

            logger.info("ReaderStatistics: DB migration complete")
            UIManager:show(InfoMessage:new{text =_("Statistics database updated."), timeout = 3 })
        elseif db_version > DB_SCHEMA_VERSION then
            logger.warn("ReaderStatistics: You appear to be using a database with an unknown schema version:", db_version, "instead of", DB_SCHEMA_VERSION)
            logger.warn("ReaderStatistics: Expect things to break in fun and interesting ways!")

            -- We can't know what might happen, so, back the DB up...
            conn:close()
            local bkp_db_location = db_location .. ".bkp." .. db_version .. "-to-" .. DB_SCHEMA_VERSION
            -- Don't overwrite an existing backup
            if lfs.attributes(bkp_db_location, "mode") == "file" then
                logger.warn("ReaderStatistics: A DB backup from schema", db_version, "to schema", DB_SCHEMA_VERSION, "already exists!")
            else
                FFIUtil.copyFile(db_location, bkp_db_location)
                logger.info("ReaderStatistics: Old DB backed up as", bkp_db_location)
            end

            conn = SQ3.open(db_location)
        end
    else  -- Migrate stats for books in history from metadata.lua to sqlite database
        self.settings.convert_to_db = true
        if not conn:exec("PRAGMA table_info('book');") then
            local filename_first_history, quickstart_filename, __
            if #ReadHistory.hist == 1 then
                filename_first_history = ReadHistory.hist[1]["text"]
                local quickstart_path = require("ui/quickstart").quickstart_filename
                __, quickstart_filename = util.splitFilePathName(quickstart_path)
            end
            if #ReadHistory.hist > 1 or (#ReadHistory.hist == 1 and filename_first_history ~= quickstart_filename) then
                local info = InfoMessage:new{
                    text = _([[
New version of statistics plugin detected.
Statistics data needs to be converted into the new database format.
This may take a few minutes.
Please wait…
]])}
                UIManager:show(info)
                UIManager:forceRePaint()
                local nr_book = self:migrateToDB(conn)
                UIManager:close(info)
                UIManager:forceRePaint()
                UIManager:show(InfoMessage:new{
                    text = T(N_("Conversion complete.\nImported one book to the database.\nTap to continue.", "Conversion complete.\nImported %1 books to the database.\nTap to continue."), nr_book) })
            else
                self:createDB(conn)
            end
        end
    end
    conn:close()
end

-- Mainly so we don't duplicate the schema twice between the creation/upgrade codepaths
local STATISTICS_DB_PAGE_STAT_DATA_SCHEMA = [[
    CREATE TABLE IF NOT EXISTS page_stat_data
        (
            id_book     integer,
            page        integer NOT NULL DEFAULT 0,
            start_time  integer NOT NULL DEFAULT 0,
            duration    integer NOT NULL DEFAULT 0,
            total_pages integer NOT NULL DEFAULT 0,
            UNIQUE (id_book, page, start_time),
            FOREIGN KEY(id_book) REFERENCES book(id)
        );
]]

local STATISTICS_DB_PAGE_STAT_DATA_INDEX = [[
    CREATE INDEX IF NOT EXISTS page_stat_data_start_time ON page_stat_data(start_time);
]]

local STATISTICS_DB_PAGE_STAT_VIEW_SCHEMA = [[
    -- Create the numbers table, used as a source of extra rows when scaling pages in the page_stat view
    CREATE TABLE IF NOT EXISTS numbers
        (
            number INTEGER PRIMARY KEY
        );
    WITH RECURSIVE counter AS
        (
            SELECT 1 as N UNION ALL
            SELECT N + 1 FROM counter WHERE N < 1000
        )
        INSERT INTO numbers SELECT N AS number FROM counter;

    -- Create the page_stat view
    -- This view rescales data from the page_stat_data table to the current number of book pages
    -- c.f., https://github.com/koreader/koreader/pull/6761#issuecomment-705660154
    CREATE VIEW IF NOT EXISTS page_stat AS
        SELECT id_book, first_page + idx - 1 AS page, start_time, duration / (last_page - first_page + 1) AS duration
        FROM (
            SELECT id_book, page, total_pages, pages, start_time, duration,
                -- First page_number for this page after rescaling single row
                ((page - 1) * pages) / total_pages + 1 AS first_page,
                -- Last page_number for this page after rescaling single row
                max(((page - 1) * pages) / total_pages + 1, (page * pages) / total_pages) AS last_page,
                idx
            FROM page_stat_data
            JOIN book ON book.id = id_book
            -- Duplicate rows for multiple pages as needed (as a result of rescaling)
            JOIN (SELECT number as idx FROM numbers) AS N ON idx <= (last_page - first_page + 1)
        );
]]

function ReaderStatistics:createDB(conn)
    -- Make it WAL, if possible
    if Device:canUseWAL() then
        conn:exec("PRAGMA journal_mode=WAL;")
    else
        conn:exec("PRAGMA journal_mode=TRUNCATE;")
    end

    local sql_stmt = [[
        -- book
        CREATE TABLE IF NOT EXISTS book
            (
                id integer PRIMARY KEY autoincrement,
                title text,
                authors text,
                notes      integer,
                last_open  integer,
                highlights integer,
                pages      integer,
                series text,
                language text,
                md5 text,
                total_read_time  integer,
                total_read_pages integer
            );
    ]]
    conn:exec(sql_stmt)
    -- Index
    sql_stmt = [[
        CREATE UNIQUE INDEX IF NOT EXISTS book_title_authors_md5 ON book(title, authors, md5);
    ]]
    conn:exec(sql_stmt)

    -- page_stat_data
    conn:exec(STATISTICS_DB_PAGE_STAT_DATA_SCHEMA)
    conn:exec(STATISTICS_DB_PAGE_STAT_DATA_INDEX)

    -- page_stat view
    conn:exec(STATISTICS_DB_PAGE_STAT_VIEW_SCHEMA)

    -- DB schema version
    conn:exec(string.format("PRAGMA user_version=%d;", DB_SCHEMA_VERSION))
end

function ReaderStatistics:upgradeDBto20201010(conn)
    local sql_stmt = [[
        -- Start by updating the layout of the old page_stat table
        ALTER TABLE page_stat RENAME COLUMN period TO duration;
        -- We're now using the user_version PRAGMA to keep track of schema version
        DROP TABLE IF EXISTS info;
    ]]
    conn:exec(sql_stmt)

    -- Migrate page_stat content to page_stat_data, which we'll have to create first ;).
    conn:exec(STATISTICS_DB_PAGE_STAT_DATA_SCHEMA)

    sql_stmt = [[
        -- Migrate page_stat content to page_stat_data, and populate total_pages from book's pages while we're at it.
        -- NOTE: While doing a per-book migration could ensure a potentially more accurate page count,
        --       we need to populate total_pages *now*, or queries against unopened books would return completely bogus values...
        --       We'll just have to hope the current value of the column pages in the book table is not too horribly out of date,
        --       and not too horribly out of phase with the actual page count at the time the data was originally collected...
        INSERT INTO page_stat_data
            SELECT id_book, page, start_time, duration, pages as total_pages FROM page_stat
            JOIN book on book.id = id_book;

        -- Drop old page_stat table
        DROP INDEX IF EXISTS page_stat_id_book;
        DROP TABLE IF EXISTS page_stat;
    ]]
    conn:exec(sql_stmt)

    -- Create the new page_stat view stuff
    conn:exec(STATISTICS_DB_PAGE_STAT_VIEW_SCHEMA)

    -- Update DB schema version
    conn:exec("PRAGMA user_version=20201010;")
end

function ReaderStatistics:upgradeDBto20201022(conn)
    conn:exec(STATISTICS_DB_PAGE_STAT_DATA_INDEX)

    -- Update DB schema version
    conn:exec("PRAGMA user_version=20201022;")
end

function ReaderStatistics:upgradeDBto20221111(conn)
    conn:exec([[
        -- We make the index on book's (title, author, md5) unique in order to sync dbs
        -- First we fill null authors with ''
        UPDATE book SET authors = '' WHERE authors IS NULL;
        -- Secondly, we unify the id_book in page_stat_data entries for duplicate books
        -- to the smallest of each, so as to delete the others.
        UPDATE page_stat_data SET id_book = (
            SELECT map.min_id FROM (
                SELECT id, (
                    SELECT min(id) FROM book b2
                    WHERE (book.title, book.authors, book.md5) = (b2.title, b2.authors, b2.md5)
                ) as min_id
                FROM book WHERE book.id >= min_id
            ) as map WHERE page_stat_data.id_book = map.id
        );
        -- Delete duplicate books and keep the one with smallest id.
        DELETE FROM book WHERE id > (
            SELECT MIN(id) FROM book b2
            WHERE (book.title, book.authors, book.md5) = (b2.title, b2.authors, b2.md5)
        );
        -- Then we recompute the book statistics based on merged books
        UPDATE book SET (total_read_pages, total_read_time) =
        (SELECT count(DISTINCT page),
                sum(duration)
         FROM   page_stat
         WHERE  id_book = book.id);
        -- Finally we update the index to be unique
        DROP INDEX IF EXISTS book_title_authors_md5;
        CREATE UNIQUE INDEX book_title_authors_md5 ON book(title, authors, md5);]])

    -- Update DB schema version
    conn:exec("PRAGMA user_version=20221111;")
end

function ReaderStatistics:addBookStatToDB(book_stats, conn)
    local id_book
    local last_open_book = 0
    local total_read_pages = 0
    local total_read_time = 0
    local sql_stmt
    if book_stats.total_time_in_sec and book_stats.total_time_in_sec > 0
        and util.tableSize(book_stats.performance_in_pages) > 0 then
        local read_pages = util.tableSize(book_stats.performance_in_pages)
        logger.dbg("Insert to database: " .. book_stats.title)
        sql_stmt = [[
            SELECT count(id)
            FROM   book
            WHERE  title = ?
              AND  authors = ?
              AND  md5 = ?;
        ]]
        local stmt = conn:prepare(sql_stmt)
        local result = stmt:reset():bind(self.data.title, self.data.authors, self.doc_md5):step()
        local nr_id = tonumber(result[1])
        if nr_id == 0 then
            local partial_md5 = util.partialMD5(book_stats.file)
            stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);")
            stmt:reset():bind(book_stats.title, book_stats.authors, book_stats.notes,
                last_open_book, book_stats.highlights, book_stats.pages,
                book_stats.series, book_stats.language, partial_md5, total_read_time, total_read_pages) :step()
            sql_stmt = [[
                SELECT last_insert_rowid() AS num;
            ]]
            id_book = conn:rowexec(sql_stmt)
        else
            sql_stmt = [[
                SELECT id
                FROM   book
                WHERE  title = ?
                  AND  authors = ?
                  AND  md5 = ?;
            ]]
            stmt = conn:prepare(sql_stmt)
            result = stmt:reset():bind(self.data.title, self.data.authors, self.doc_md5):step()
            id_book = result[1]

        end
        local sorted_performance = {}
        for k, _ in pairs(book_stats.performance_in_pages) do
            table.insert(sorted_performance, k)
        end
        table.sort(sorted_performance)

        conn:exec('BEGIN;')
        stmt = conn:prepare("INSERT OR IGNORE INTO page_stat VALUES(?, ?, ?, ?);")
        local avg_time = math.ceil(book_stats.total_time_in_sec / read_pages)
        if avg_time > self.settings.max_sec then
            avg_time = self.settings.max_sec
        end
        local first_read_page = book_stats.performance_in_pages[sorted_performance[1]]
        if first_read_page > 1 then
            first_read_page = first_read_page - 1
        end
        local start_open_page = sorted_performance[1]
        --first page
        stmt:reset():bind(id_book, first_read_page, start_open_page - avg_time, avg_time):step()
        for i=2, #sorted_performance do
            start_open_page = sorted_performance[i-1]
            local diff_time = sorted_performance[i] - sorted_performance[i-1]
            if diff_time <= self.settings.max_sec then
                stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[i-1]],
                    start_open_page, diff_time):step()
            elseif diff_time > self.settings.max_sec then --and diff_time <= 2 * avg_time then
                stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[i-1]],
                    start_open_page, avg_time):step()
            end
        end
        --last page
        stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[#sorted_performance]],
            sorted_performance[#sorted_performance], avg_time):step()
        --last open book
        last_open_book = sorted_performance[#sorted_performance] + avg_time
        conn:exec('COMMIT;')
        total_read_pages, total_read_time = conn:rowexec(string.format(STATISTICS_SQL_BOOK_TOTALS_QUERY, tonumber(id_book)))
        sql_stmt = [[
            UPDATE book
            SET    last_open = ?,
                   total_read_time = ?,
                   total_read_pages = ?
            WHERE  id = ?;
        ]]
        stmt = conn:prepare(sql_stmt)
        stmt:reset():bind(last_open_book, total_read_time, total_read_pages, id_book):step()
        stmt:close()
        return true
    end
end

function ReaderStatistics:migrateToDB(conn)
    self:createDB(conn)
    local nr_of_conv_books = 0
    local exclude_titles = {}
    for _, v in ipairs(ReadHistory.hist) do
        local book_stats = DocSettings:open(v.file):readSetting("stats")
        if book_stats and book_stats.title == "" then
            book_stats.title = v.file:match("^.+/(.+)$")
        end
        if book_stats then
            book_stats.file = v.file
            if self:addBookStatToDB(book_stats, conn) then
                nr_of_conv_books = nr_of_conv_books + 1
                exclude_titles[book_stats.title] = true
            else
                logger.dbg("Book not converted: " .. book_stats.title)
            end
        else
            logger.dbg("Empty stats for file: ", v.file)
        end
    end
    -- import from stats files (for backward compatibility)
    if lfs.attributes(statistics_dir, "mode") == "directory" then
        for curr_file in lfs.dir(statistics_dir) do
            local path = statistics_dir .. curr_file
            if lfs.attributes(path, "mode") == "file" then
                local old_data = self:importFromFile(statistics_dir, curr_file)
                if old_data and old_data.total_time > 0 and not exclude_titles[old_data.title] then
                    local book_stats = { performance_in_pages= {} }
                    for _, v in pairs(old_data.details) do
                        book_stats.performance_in_pages[v.time] = v.page
                    end
                    book_stats.title = old_data.title
                    book_stats.authors = old_data.authors
                    book_stats.notes = old_data.notes
                    book_stats.highlights = old_data.highlights
                    book_stats.pages = old_data.pages
                    book_stats.series = old_data.series
                    book_stats.language = old_data.language
                    book_stats.total_time_in_sec = old_data.total_time
                    book_stats.file = nil
                    if self:addBookStatToDB(book_stats, conn) then
                        nr_of_conv_books = nr_of_conv_books + 1
                    else
                        logger.dbg("Book not converted (old stats): " .. book_stats.title)
                    end
                end
            end
        end
    end
    return nr_of_conv_books
end

function ReaderStatistics:getIdBookDB()
    local conn = SQ3.open(db_location)
    local id_book
    local sql_stmt = [[
        SELECT count(id)
        FROM   book
        WHERE  title = ?
          AND  authors = ?
          AND  md5 = ?;
    ]]
    local stmt = conn:prepare(sql_stmt)
    local title, authors = self.data.title, self.data.authors
    local result = stmt:reset():bind(title, authors, self.doc_md5):step()
    local nr_id = tonumber(result[1])
    if nr_id == 0 and self.ui.paging then
        -- In the past, title and/or authors strings, got from MuPDF, may have been or not null terminated.
        -- We need to check with all combinations if a book with these null terminated exists, and use it.
        title = title .. "\0"
        result = stmt:reset():bind(title, authors, self.doc_md5):step()
        nr_id = tonumber(result[1])
        if nr_id == 0 then
            authors = authors .. "\0"
            result = stmt:reset():bind(title, authors, self.doc_md5):step()
            nr_id = tonumber(result[1])
            if nr_id == 0 then
                title = self.data.title
                result = stmt:reset():bind(title, authors, self.doc_md5):step()
                nr_id = tonumber(result[1])
            end
        end
    end
    if nr_id == 0 then
        if not self.is_doc_not_frozen then return end
        -- Not in the DB yet, initialize it
        stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);")
        stmt:reset():bind(self.data.title, self.data.authors, self.data.notes,
            os.time(), self.data.highlights, self.data.pages,
            self.data.series, self.data.language, self.doc_md5, 0, 0):step()
        sql_stmt = [[
            SELECT last_insert_rowid() AS num;
        ]]
        id_book = conn:rowexec(sql_stmt)
    else
        sql_stmt = [[
            SELECT id
            FROM   book
            WHERE  title = ?
              AND  authors = ?
              AND  md5 = ?;
        ]]
        stmt = conn:prepare(sql_stmt)
        result = stmt:reset():bind(title, authors, self.doc_md5):step()
        id_book = result[1]
    end
    stmt:close()
    conn:close()

    return tonumber(id_book)
end

function ReaderStatistics:onBookMetadataChanged(prop_updated)
    if not prop_updated then return end
    local log_prefix = "Statistics metadata update:"
    logger.dbg(log_prefix, "got", prop_updated)
    -- Some metadata of a book (that we may or may not know about) has been modified
    local filepath = prop_updated.filepath
    local metadata_key_updated = prop_updated.metadata_key_updated
    local doc_props = prop_updated.doc_props -- contains up to date metadata

    local updated_field, updated_value
    if metadata_key_updated == "title" then
        updated_field = "title"
        updated_value = doc_props.display_title
    elseif metadata_key_updated == "authors" then
        updated_field = "authors"
        updated_value = doc_props.authors or "N/A"
    elseif metadata_key_updated == "language" then
        updated_field = "language"
        updated_value = doc_props.language or "N/A"
    elseif metadata_key_updated == "series" or metadata_key_updated == "series_index" then
        updated_field = "series"
        updated_value = "N/A"
        if doc_props.series then
            updated_value = doc_props.series
            if doc_props.series_index then
                updated_value = updated_value .. " #" .. doc_props.series_index
            end
        end
    else
        -- Updated metadata is one we do not store: nothing to do
        logger.dbg(log_prefix, "not a metadata we care about:", metadata_key_updated)
        return
    end

    local conn = SQ3.open(db_location)
    local id_book

    if self.document and self.document.file == filepath then
        -- Current document is the one updated: we have its id readily available
        id_book = self.id_curr_book
        logger.dbg(log_prefix, "got book id from opened document:", id_book)
        -- Update self.data with new value
        self.data[updated_field] = updated_value
    else
        -- Not the current document: we have to find its id in the db, from the (old) title/authors/md5
        local db_md5, db_title, db_authors, db_authors_legacy
        if DocSettings:hasSidecarFile(filepath) then
            db_md5 = DocSettings:open(filepath):readSetting("partial_md5_checksum")
            -- Note: stats.title and stats.authors may be osbolete, if the metadata
            -- has previously been updated and the document never re-opened since.
            logger.dbg(log_prefix, "got md5 from docsettings:", db_md5)
        end
        if not db_md5 then
            db_md5 = util.partialMD5(filepath)
            logger.dbg(log_prefix, "computed md5:", db_md5)
        end

        if metadata_key_updated == "title" then
            db_title = prop_updated.metadata_value_old
            if not db_title then -- empty title
                -- Build what display_title would have been
                local filemanagerutil = require("apps/filemanager/filemanagerutil")
                db_title = filemanagerutil.splitFileNameType(filepath)
            end
        else
            db_title = doc_props.display_title
        end

        if metadata_key_updated == "authors" then
            db_authors = prop_updated.metadata_value_old
        else
            db_authors = doc_props.authors
        end
        if not db_authors then -- empty authors (we get nil)
            db_authors = "N/A"
            -- Before Jun 2021 (#7868), we used to store "" for empty authors.
            -- If book not found with authors="N/A", we'll have to look again with "".
            db_authors_legacy = ""
        end

        local sql_stmt = [[
            SELECT id
            FROM   book
            WHERE  title = ?
              AND  authors = ?
              AND  md5 = ?;
        ]]
        local stmt = conn:prepare(sql_stmt)
        local result = stmt:reset():bind(db_title, db_authors, db_md5):step()
        if not result and db_authors_legacy then
            logger.dbg(log_prefix, "book not present, trying with fallback empty authors")
            result = stmt:reset():bind(db_title, db_authors_legacy, db_md5):step()
        end
        stmt:close()
        if not result then
            -- Book not present in statistics
            logger.info(log_prefix, "book not present", db_title, db_authors, db_md5)
            conn:close()
            return
        end
        id_book = tonumber(result[1])
        logger.dbg(log_prefix, "found book id in db:", id_book)
    end
    logger.info(log_prefix, "updating book", id_book, updated_field, "with:", updated_value)

    local sql_stmt = [[
        UPDATE book
        SET    ]]..updated_field..[[ = ?
        WHERE  id = ?;
    ]]
    local stmt = conn:prepare(sql_stmt)
    local ok, err = pcall(function()
        stmt:reset():bind(updated_value, id_book):step()
    end)
    if not ok and err then
        -- Let it be known if "UNIQUE constraint failed: book.title, book.authors, book.md5"
        err = err:gsub("\n.*", "") -- remove stacktrace
        logger.err(log_prefix, "updating book failed:", err)
    end

    sql_stmt = [[
        SELECT changes();
    ]]
    local nb_updated = conn:rowexec(sql_stmt)
    nb_updated = nb_updated and tonumber(nb_updated) or 0
    logger.dbg(log_prefix, nb_updated, "book updated.")
    stmt:close()
    conn:close()
end

function ReaderStatistics:insertDB(updated_pagecount)
    if not (self.id_curr_book and self.is_doc_not_frozen) then
        return
    end
    local id_book = self.id_curr_book
    local now_ts = os.time()

    -- The current page stat, having yet no duration, will be ignored
    -- in the insertion, and its start ts would be lost. We'll give it
    -- to resetVolatileStats() so it can restore it
    local cur_page_start_ts = now_ts
    local cur_page_data = self.page_stat[self.curr_page]
    local cur_page_data_tuple = cur_page_data and cur_page_data[#cur_page_data]
    if cur_page_data_tuple and cur_page_data_tuple[2] == 0 then -- should always be true
        cur_page_start_ts = cur_page_data_tuple[1]
    end

    local conn = SQ3.open(db_location)
    conn:exec('BEGIN;')
    local stmt = conn:prepare("INSERT OR IGNORE INTO page_stat_data VALUES(?, ?, ?, ?, ?);")
    for page, data_list in pairs(self.page_stat) do
        for _, data_tuple in ipairs(data_list) do
            -- See self.page_stat declaration above about the tuple's layout
            local ts = data_tuple[1]
            local duration = data_tuple[2]
            -- Skip placeholder durations
            if duration > 0 then
                -- NOTE: The fact that we update self.data.pages *after* this call on layout changes
                --       should ensure that it matches the layout in which said data was collected.
                --       Said data is used to re-scale page numbers, regardless of the document layout,
                --       at query time, via a fancy SQL view.
                --       This allows the progress tracking to be accurate even in the face of wild
                --       document layout changes (e.g., after font size changes).
                stmt:reset():bind(id_book, page, ts, duration, self.data.pages):step()
            end
        end
    end
    conn:exec('COMMIT;')

    -- Update the new pagecount now, so that subsequent queries against the view are accurate
    local sql_stmt = [[
        UPDATE book
        SET    pages = ?
        WHERE  id = ?;
    ]]
    stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(updated_pagecount and updated_pagecount or self.data.pages, id_book):step()

    -- NOTE: See the tail end of the discussions in #6761 for more context on the choice of this heuristic.
    --       Basically, we're counting distinct pages,
    --       while making sure the sum of durations per distinct page is clamped to self.settings.max_sec
    --       This is expressly tailored to a fairer computation of self.avg_time ;).
    local book_read_pages, book_read_time = conn:rowexec(string.format(STATISTICS_SQL_BOOK_CAPPED_TOTALS_QUERY, self.settings.max_sec, id_book))
    -- NOTE: What we cache in the book table is the plain uncapped sum (mainly for deleteBooksByTotalDuration's benefit)...
    local total_read_pages, total_read_time = conn:rowexec(string.format(STATISTICS_SQL_BOOK_TOTALS_QUERY, id_book))

    -- And now update the rest of the book table...
    sql_stmt = [[
        UPDATE book
        SET    last_open = ?,
               notes = ?,
               highlights = ?,
               total_read_time = ?,
               total_read_pages = ?
        WHERE  id = ?;
    ]]
    stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(now_ts, self.data.notes, self.data.highlights, total_read_time, total_read_pages, id_book):step()
    stmt:close()
    conn:close()

    -- NOTE: On the other hand, this is used for the average time estimate, so we use the capped variants here!
    if book_read_pages then
        self.book_read_pages = tonumber(book_read_pages)
    else
        self.book_read_pages = 0
    end
    if book_read_time then
        self.book_read_time = tonumber(book_read_time)
    else
        self.book_read_time = 0
    end
    self.avg_time = self.book_read_time / self.book_read_pages

    self:resetVolatileStats(cur_page_start_ts)
end

function ReaderStatistics:getPageTimeTotalStats(id_book)
    if id_book == nil then
        return
    end
    local conn = SQ3.open(db_location)
    -- NOTE: Similarly, this one is used for time-based estimates and averages, so, use the capped variant
    local total_pages, total_time = conn:rowexec(string.format(STATISTICS_SQL_BOOK_CAPPED_TOTALS_QUERY, self.settings.max_sec, id_book))
    conn:close()

    if total_pages then
        total_pages = tonumber(total_pages)
    else
        total_pages = 0
    end
    if total_time then
        total_time = tonumber(total_time)
    else
        total_time = 0
    end
    return total_pages, total_time
end

function ReaderStatistics:onToggleStatistics(arg)
    local no_notification, toggle
    if type(arg) == "table" then -- Dispatcher-enable/disable
        no_notification, toggle = unpack(arg)
        if toggle == self.settings.is_enabled then return end
    else -- Dispatcher-toggle or Menu-toggle
        no_notification = arg
        toggle = not self.settings.is_enabled
    end
    if self.settings.is_enabled then -- save data to file
        self:insertDB()
    end
    self.settings.is_enabled = toggle
    if self.is_doc then
        if self.settings.is_enabled then
            self:initData()
            self.start_current_period = os.time()
            self.curr_page = self.ui:getCurrentPage()
            self:resetVolatileStats(self.start_current_period)
        end
        self.view.footer:maybeUpdateFooter()
    end
    if not no_notification then
        local Notification = require("ui/widget/notification")
        Notification:notify(self.settings.is_enabled and _("Statistics enabled") or _("Statistics disabled"))
    end
end

function ReaderStatistics:addToMainMenu(menu_items)
    menu_items.statistics = {
        text = _("Reading statistics"),
        sub_item_table = {
            {
                text = _("Enabled"),
                checked_func = function()
                    return self.settings.is_enabled
                end,
                callback = function()
                    self:onToggleStatistics(true) -- no notification
                end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Read page duration limits: %1 s – %2 s"),
                                self.settings.min_sec, self.settings.max_sec)
                        end,
                        callback = function(touchmenu_instance)
                            local DoubleSpinWidget = require("ui/widget/doublespinwidget")
                            local durations_widget
                            durations_widget = DoubleSpinWidget:new{
                                left_text = C_("Extrema", "Min"),
                                left_value = self.settings.min_sec,
                                left_default = DEFAULT_MIN_READ_SEC,
                                left_min = 0,
                                left_max = 120,
                                left_step = 1,
                                left_hold_step = 10,
                                right_text = C_("Extrema", "Max"),
                                right_value = self.settings.max_sec,
                                right_default = DEFAULT_MAX_READ_SEC,
                                right_min = 10,
                                right_max = 7200,
                                right_step = 10,
                                right_hold_step = 60,
                                is_range = true,
                                -- @translators This is the time unit for seconds.
                                unit = C_("Time", "s"),
                                title_text = _("Read page duration limits"),
                                info_text = _([[
Set min and max time spent (in seconds) on a page for it to be counted as read in statistics.
The min value ensures pages you quickly browse and skip are not included.
The max value ensures a page you stay on for a long time (because you fell asleep or went away) will be included, but with a duration capped to this specified max value.]]),
                                callback = function(min, max)
                                    self.settings.min_sec = min
                                    self.settings.max_sec = max
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(durations_widget)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Freeze statistics of finished books"),
                        checked_func = function() return self.settings.freeze_finished_books end,
                        callback = function()
                            self.settings.freeze_finished_books = not self.settings.freeze_finished_books
                            self.is_doc_not_frozen = self.is_doc
                                and (self.is_doc_not_finished or not self.settings.freeze_finished_books)
                        end,
                        separator = true,
                    },
                    {
                        text_func = function()
                            return T(_("Calendar weeks start on %1"),
                                datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[self.settings.calendar_start_day_of_week]])
                        end,
                        sub_item_table = {
                            { -- Friday (Bangladesh and Maldives)
                                text = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[6]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 6 end,
                                callback = function() self.settings.calendar_start_day_of_week = 6 end
                            },
                            { -- Saturday (some Middle East countries)
                                text = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[7]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 7 end,
                                callback = function() self.settings.calendar_start_day_of_week = 7 end
                            },
                            { -- Sunday
                                text = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[1]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 1 end,
                                callback = function() self.settings.calendar_start_day_of_week = 1 end
                            },
                            { -- Monday
                                text = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[2]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 2 end,
                                callback = function() self.settings.calendar_start_day_of_week = 2 end
                            },
                        },
                    },
                    {
                        text_func = function()
                            return T(_("Books per calendar day: %1"), self.settings.calendar_nb_book_spans)
                        end,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                value = self.settings.calendar_nb_book_spans,
                                value_min = 1,
                                value_max = 5,
                                default_value  = DEFAULT_CALENDAR_NB_BOOK_SPANS,
                                ok_text = _("Set"),
                                title_text =  _("Books per calendar day"),
                                info_text = _("Set the max number of book spans to show for a day"),
                                callback = function(spin)
                                    self.settings.calendar_nb_book_spans = spin.value
                                    touchmenu_instance:updateItems()
                                end,
                            })
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Show hourly histogram in calendar days"),
                        checked_func = function() return self.settings.calendar_show_histogram end,
                        callback = function()
                            self.settings.calendar_show_histogram = not self.settings.calendar_show_histogram
                        end,
                    },
                    {
                        text = _("Allow browsing coming months"),
                        checked_func = function() return self.settings.calendar_browse_future_months end,
                        callback = function()
                            self.settings.calendar_browse_future_months = not self.settings.calendar_browse_future_months
                        end,
                        separator = true,
                    },
                    {
                        text_func = function()
                            -- @translators %1 is the time in the format 00:00
                            return T(_("Daily timeline starts at %1"),
                                string.format("%02d:%02d", self.settings.calendar_day_start_hour or 0,
                                                           self.settings.calendar_day_start_minute or 0)
                            )
                        end,
                        callback = function(touchmenu_instance)
                            local DateTimeWidget = require("ui/widget/datetimewidget")
                            local start_of_day_widget = DateTimeWidget:new{
                                hour = self.settings.calendar_day_start_hour or 0,
                                min = self.settings.calendar_day_start_minute or 0,
                                min_max = 50,
                                min_step = 10, -- we have vertical lines every 10mn, keep them meaningful
                                min_hold_step = 30,
                                ok_text = _("Set time"),
                                title_text = _("Daily timeline starts at"),
                                info_text =_([[
Set the time when the daily timeline should start.

If you read past midnight, and would like this reading session to be displayed on the same screen with your previous evening reading sessions, use a value such as 04:00.

Time is in hours and minutes.]]),
                                callback = function(time)
                                    self.settings.calendar_day_start_hour = time.hour
                                    self.settings.calendar_day_start_minute = time.min
                                    touchmenu_instance:updateItems()
                                end
                            }
                            UIManager:show(start_of_day_widget)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Also use in calendar view"),
                        checked_func = function() return self.settings.calendar_use_day_time_shift end,
                        callback = function()
                            self.settings.calendar_use_day_time_shift = not self.settings.calendar_use_day_time_shift
                        end,
                        separator = true,
                    },
                    {
                        text = _("Cloud sync"),
                        callback = function(touchmenu_instance)
                            local server = self.settings.sync_server
                            local edit_cb = function()
                                local sync_settings = SyncService:new{}
                                sync_settings.onClose = function(this)
                                    UIManager:close(this)
                                end
                                sync_settings.onConfirm = function(sv)
                                    if server and (server.type ~= sv.type
                                        or server.url ~= sv.url
                                        or server.address ~= sv.address) then
                                            SyncService.removeLastSyncDB(db_location)
                                    end
                                    self.settings.sync_server = sv
                                    touchmenu_instance:updateItems()
                                end
                                UIManager:show(sync_settings)
                            end
                            if not server then
                                edit_cb()
                                return
                            end
                            local dialogue
                            local delete_button = {
                                text = _("Delete"),
                                callback = function()
                                    UIManager:close(dialogue)
                                    UIManager:show(ConfirmBox:new{
                                        text = _("Delete server info?"),
                                        cancel_text = _("Cancel"),
                                        cancel_callback = function()
                                            return
                                        end,
                                        ok_text = _("Delete"),
                                        ok_callback = function()
                                            self.settings.sync_server = nil
                                            SyncService.removeLastSyncDB(db_location)
                                            touchmenu_instance:updateItems()
                                        end,
                                    })
                                end,
                            }
                            local edit_button = {
                                text = _("Edit"),
                                callback = function()
                                    UIManager:close(dialogue)
                                    edit_cb()
                                end
                            }
                            local close_button = {
                                text = _("Close"),
                                callback = function()
                                    UIManager:close(dialogue)
                                end
                            }
                            local type = server.type == "dropbox" and " (DropBox)" or " (WebDAV)"
                            dialogue = ButtonDialog:new{
                                title = T(_("Cloud storage:\n%1\n\nFolder path:\n%2\n\nSet up the same cloud folder on each device to sync across your devices."),
                                             server.name.." "..type, SyncService.getReadablePath(server)),
                                buttons = {
                                    {delete_button, edit_button, close_button}
                                },
                            }
                            UIManager:show(dialogue)
                        end,
                        enabled_func = function() return self.settings.is_enabled end,
                        keep_menu_open = true,
                        separator = true,
                    },
                    {
                        text = _("Dual Page Mode"),
                        show_func = function()
                            return self.ui.paging and self.ui.paging:supportsDualPage()
                        end,
                        sub_item_table = {
                            {
                                text = _("Divide page time in two"),
                                checked_func = function()
                                    return self.settings.dual_page_mode_divide_duration_by_two and
                                        not self.settings.dual_page_mode_duplicate_duration
                                end,
                                callback = function()
                                    self.settings.dual_page_mode_divide_duration_by_two = not self.settings
                                    .dual_page_mode_divide_duration_by_two
                                    self.settings.dual_page_mode_duplicate_duration = false
                                end,
                                help_text = _(
                                    [[When reading in Dual Page Mode, by default, the total time spend on the  pages will only count for the lowest page number(the base page).
If you enable this setting, then the total time spend looking at both pages will be divided by two and stored for each page.

Enabled:
If you're reading page 2 and 3 for 10m, then we will store that you've spend 5m reading page 2 and 5m reading page 3.
Disabled:
If you're reading page 2 and 3 for 10m, then we will store that you've spend 10m reading page 2, and never read page 3.
]]),
                            },
                            {
                                text = _("Store same time for both pages"),
                                checked_func = function()
                                    return self.settings.dual_page_mode_duplicate_duration and
                                        not self.settings.dual_page_mode_divide_duration_by_two
                                end,
                                callback = function()
                                    self.settings.dual_page_mode_divide_duration_by_two = false
                                    self.settings.dual_page_mode_duplicate_duration = not self.settings
                                    .dual_page_mode_duplicate_duration
                                end,
                                help_text = _(
                                    [[When reading in Dual Page Mode, by default, the total time spend on the  pages will only count for the lowest page number(the base page).
If you enalbe this setting, then the total time spend looking at both pages will be stored for both pages.

Enabled:
If you're reading page 2 and 3 for 10m, then we will store that you've spend 10m reading page 2 and 10m reading page 3.
Disabled:
If you're reading page 2 and 3 for 10m, then we will store that you've spend 10m reading page 2, and never read page 3.
]]),
                            }
                        },
                        callback = function() end,
                    },
                },
            },
            {
                text = _("Reset statistics"),
                sub_item_table = self:genResetBookSubItemTable(),
                separator = true,
            },
            {
                text = _("Synchronize now"),
                callback = function()
                    self:onSyncBookStats()
                end,
                enabled_func = function()
                    return self:canSync()
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Current book"),
                keep_menu_open = true,
                callback = function()
                    self.kv = KeyValuePage:new{
                        title = _("Current statistics"),
                        kv_pairs = self:getCurrentStat(),
                        value_align = "right",
                        single_page = true,
                    }
                    UIManager:show(self.kv)
                end,
                enabled_func = function() return self:isEnabled() end,
            },
            {
                text = _("Reading progress"),
                keep_menu_open = true,
                callback = function()
                    self:insertDB()
                    local current_duration, current_pages = self:getCurrentBookStats()
                    local today_duration, today_pages = self:getTodayBookStats()
                    local dates_stats = self:getReadingProgressStats(7)
                    if dates_stats then
                        UIManager:show(ReaderProgress:new{
                            dates = dates_stats,
                            current_duration = current_duration,
                            current_pages = current_pages,
                            today_duration = today_duration,
                            today_pages = today_pages,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Reading progress is not available.\nThere is no data for the last week."),
                        })
                    end
                end
            },
            {
                text = _("Time range"),
                keep_menu_open = true,
                callback = function()
                    self:onShowTimeRange()
                end
            },
            {
                text = _("Calendar view"),
                keep_menu_open = true,
                callback = function()
                    self:onShowCalendarView()
                end,
            },
            {
                text = _("Today's timeline"),
                keep_menu_open = true,
                callback = function()
                    self:onShowCalendarDayView()
                end,
            },
        },
    }
end

function ReaderStatistics:onShowTimeRange()
    self.kv = KeyValuePage:new{
        title = _("Time range statistics"),
        return_button = true,
        kv_pairs = {
            { _("All books"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    local total_msg, kv_pairs = self:getTotalStats()
                    self.kv = KeyValuePage:new{
                        title = total_msg,
                        value_align = "right",
                        kv_pairs = kv_pairs,
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end, -- clean stack
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("Books by week"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Books by week"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(0, "weekly", true),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("Books by month"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Books by month"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(0, "monthly", true),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
                separator = true,
            },
            { _("Last week"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Last week"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(7, "daily_weekday"),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("Last month by day"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Last month by day"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(30, "daily_weekday"),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("Last year by day"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Last year by day"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(365, "daily"),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("Last year by week"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("Last year by week"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(365, "weekly"),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
            { _("All stats by month"),"",
                callback = function()
                    local kv = self.kv
                    UIManager:close(self.kv)
                    self.kv = KeyValuePage:new{
                        title = _("All stats by month"),
                        value_overflow_align = "right",
                        kv_pairs = self:getDatesFromAll(0, "monthly"),
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                    UIManager:show(self.kv)
                end,
            },
        }
    }
    UIManager:show(self.kv)
end

function ReaderStatistics:getTodayBookStats()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT count(*),
               sum(sum_duration)
        FROM    (
                     SELECT sum(duration)    AS sum_duration
                     FROM   page_stat
                     WHERE  start_time >= %d
                     GROUP  BY id_book, page
                );
    ]]
    local today_pages, today_duration = conn:rowexec(string.format(sql_stmt, start_today_time))
    conn:close()

    if today_pages == nil then
        today_pages = 0
    end
    if today_duration == nil then
        today_duration = 0
    end
    today_duration = tonumber(today_duration)
    today_pages = tonumber(today_pages)
    return today_duration, today_pages
end

function ReaderStatistics:getCurrentBookStats()
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT count(*),
               sum(sum_duration)
        FROM   (
                    SELECT sum(duration)    AS sum_duration
                    FROM   page_stat
                    WHERE  start_time >= %d
                    GROUP  BY id_book, page
               );
    ]]
    local current_pages, current_duration = conn:rowexec(string.format(sql_stmt, self.start_current_period))
    conn:close()

    if current_pages == nil then
        current_pages = 0
    end
    if current_duration == nil then
        current_duration = 0
    end
    current_duration = tonumber(current_duration)
    current_pages = tonumber(current_pages)
    return current_duration, current_pages
end

function ReaderStatistics:getCurrentStat()
    self:insertDB()
    local id_book = self.id_curr_book
    local today_duration, today_pages = self:getTodayBookStats()
    local current_duration, current_pages = self:getCurrentBookStats()

    local conn = SQ3.open(db_location)
    local highlights, notes = conn:rowexec(string.format("SELECT highlights, notes FROM book WHERE id = %d;", id_book))
    local sql_stmt = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = %d
                    GROUP  BY dates
               );
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_book))

    -- NOTE: Here, we generally want to account for the *full* amount of time spent reading this book.
    sql_stmt = [[
        SELECT sum(duration),
               count(DISTINCT page),
               min(start_time)
        FROM   page_stat
        WHERE  id_book = %d;
    ]]
    local total_time_book, total_read_pages, first_open = conn:rowexec(string.format(sql_stmt, id_book))
    conn:close()

    -- NOTE: But, as the "Average time per page" entry is already re-using self.avg_time,
    --       which is computed slightly differently (c.f., insertDB), we'll be using this tweaked book read time
    --       to compute the other time-based statistics...
    local __, book_read_time = self:getPageTimeTotalStats(id_book)
    local now_ts = os.time()

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    if first_open == nil then
        first_open = now_ts
    end
    self.data.pages = self.document:getPageCount()
    total_time_book = tonumber(total_time_book)
    total_read_pages = tonumber(total_read_pages)

    local current_page
    local total_pages
    local page_progress_string
    local percent_read
    if self.document:hasHiddenFlows() and self.view.state.page then
        local flow = self.document:getPageFlow(self.view.state.page)
        current_page = self.document:getPageNumberInFlow(self.view.state.page)
        total_pages = self.document:getTotalPagesInFlow(flow)
        percent_read = Math.round(100*current_page/total_pages)
        if flow == 0 then
            page_progress_string = ("%d // %d (%d%%)"):format(current_page, total_pages, percent_read)
        else
            page_progress_string = ("[%d / %d]%d (%d%%)"):format(current_page, total_pages, flow, percent_read)
        end
    else
        current_page = self.ui:getCurrentPage()
        total_pages = self.data.pages
        percent_read = Math.round(100*current_page/total_pages)
        page_progress_string = ("%d / %d (%d%%)"):format(current_page, total_pages, percent_read)
    end

    local first_open_days_ago = math.floor(tonumber(now_ts - first_open)/86400)
    local time_to_read = current_page and ((total_pages - current_page) * self.avg_time) or 0
    local estimate_days_to_read = math.ceil(time_to_read/(book_read_time/tonumber(total_days)))
    local estimate_end_of_read_date = datetime.secondsToDate(tonumber(now_ts + estimate_days_to_read * 86400), true)
    local estimates_valid = time_to_read > 0 -- above values could be 'nan' and 'nil'
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    local avg_page_time_string = datetime.secondsToClockDuration(user_duration_format, self.avg_time, false)
    local avg_day_time_string = datetime.secondsToClockDuration(user_duration_format, book_read_time/tonumber(total_days), false)
    local time_to_read_string = estimates_valid and datetime.secondsToClockDuration(user_duration_format, time_to_read, false) or _("N/A")

    -- Use more_arrow to indicate that an option shows another view
    -- Use " ⓘ" to indicate that an option will show an info message
    local more_arrow = BD.mirroredUILayout() and "◂" or "▸"

    local estimated_popup = function()
        UIManager:show(InfoMessage:new{
            text = T(N_("There is 1 page (%2%) left to read.", "There are %1 pages (%2%) left to read.", total_pages - current_page), total_pages - current_page, 100 - percent_read) ..
                "\n\n" .. T(_("At the current rate of %1 per page, that will take %2 of reading time."), avg_page_time_string, time_to_read_string) ..
                "\n\n" .. T(N_("At the current rate of %1 per day, that will take 1 day.", "At the current rate of %1 per day, that will take %2 days.", estimate_days_to_read), avg_day_time_string, estimate_days_to_read),
            icon = "book.opened"
        })
    end

    -- Replace estimates for finished/frozen books
    local estimated_time_left, estimated_finish_date
    if self.is_doc_not_frozen then
        estimated_time_left = { _("Estimated reading time left") .. " ⓘ", time_to_read_string, callback = estimated_popup }
        estimated_finish_date = { _("Estimated finish date") .. " ⓘ", estimates_valid and T(N_("(in 1 day) %2", "(in %1 days) %2", estimate_days_to_read), estimate_days_to_read, estimate_end_of_read_date) or _("N/A"), callback = estimated_popup }
    else
        estimated_time_left = { _("Estimated reading time left"), _("finished") }
        local mark_date = self.ui.doc_settings:readSetting("summary").modified
        estimated_finish_date = { _("Book marked as finished"), datetime.secondsToDate(datetime.stringToSeconds(mark_date), true) }
    end
    estimated_time_left.separator = true
    estimated_finish_date.separator = true

    return {
        -- Global statistics (may consider other books than current book)

        -- Since last resume
        { _("Time spent reading this session"), datetime.secondsToClockDuration(user_duration_format, current_duration, false) },
        { _("Pages read this session"), tonumber(current_pages), separator = true },

        -- Today
        { _("Time spent reading today") .. " " .. more_arrow, datetime.secondsToClockDuration(user_duration_format, today_duration, false),
            callback = function()
                local CalendarView = require("calendarview")
                local title_callback = function(this)
                    return T(_("Today (%1)"), datetime.secondsToDate(now_ts, true))
                end
                CalendarView:showCalendarDayView(self, title_callback)
            end,
        },
        { _("Pages read today"), tonumber(today_pages), separator = true },

        -- Current book statistics (includes re-reads)

        -- Time-focused book stats
        { _("Total time spent on this book"), datetime.secondsToClockDuration(user_duration_format, total_time_book, false) },
        -- capped to self.settings.max_sec per distinct page
        { _("Time spent reading"), datetime.secondsToClockDuration(user_duration_format, book_read_time, false) },
        -- estimation, from current page to end of book
        estimated_time_left,

        -- Day-focused book stats
        { _("Days reading this book") .. " " .. more_arrow, tonumber(total_days),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)
                self.kv = KeyValuePage:new{
                    title = T(_("Days reading %1"), self.data.title),
                    value_overflow_align = "right",
                    kv_pairs = self:getDatesForBook(id_book),
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end,
                    close_callback = function() self.kv = nil end,
                }
                UIManager:show(self.kv)
            end,
        },
        { _("Average time per day"), avg_day_time_string, separator = true },

        -- Date-focused book stats
        { _("Book start date"), T(N_("(1 day ago) %2", "(%1 days ago) %2", first_open_days_ago), first_open_days_ago, datetime.secondsToDate(tonumber(first_open), true)) },
        estimated_finish_date,

        -- Page-focused book stats
        { _("Current page/Total pages"), page_progress_string },
        { _("Pages read"), string.format("%d (%d%%)", total_read_pages, Math.round(100*total_read_pages/self.data.pages)) },
        { _("Average time per page"), avg_page_time_string, separator = true },

        -- Highlights and notes
        { _("Book highlights"), tonumber(highlights) },
        { _("Book notes"), tonumber(notes) },
    }
end

function ReaderStatistics:getBookStat(id_book)
    if id_book == nil then
        return
    end
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT title, authors, pages, last_open, highlights, notes
        FROM book
        WHERE id = %d;
    ]]
    local title, authors, pages, last_open, highlights, notes = conn:rowexec(string.format(sql_stmt, id_book))

    -- Due to some bug, some books opened around April 2020 might
    -- have notes and highlight NULL in the DB.
    -- See: https://github.com/koreader/koreader/issues/6190#issuecomment-633693940
    -- (We made these last in the SQL so NULL/nil doesn't prevent
    -- fetching the other fields.)
    -- Show "?" when these values are not known (they will be
    -- fixed next time this book is opened).
    highlights = highlights and tonumber(highlights) or "?"
    notes = notes and tonumber(notes) or "?"

    sql_stmt = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = %d
                    GROUP  BY dates
               );
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_book))

    -- NOTE: Same general principle as getCurrentStat
    sql_stmt = [[
        SELECT sum(duration),
               count(DISTINCT page),
               min(start_time),
               (select max(ps2.page) from page_stat as ps2 where ps2.start_time = max(page_stat.start_time))
        FROM   page_stat
        WHERE  id_book = %d;
    ]]
    local total_time_book, total_read_pages, first_open, last_page = conn:rowexec(string.format(sql_stmt, id_book))
    conn:close()

    local book_read_pages, book_read_time = self:getPageTimeTotalStats(id_book)
    local now_ts = os.time()

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    if first_open == nil then
        first_open = now_ts
    end
    total_time_book = tonumber(total_time_book)
    total_read_pages = tonumber(total_read_pages)
    last_page = tonumber(last_page)
    if last_page == nil then
        last_page = 0
    end
    pages = tonumber(pages)
    if pages == nil or pages == 0 then
        pages = 1
    end
    local first_open_days_ago = math.floor(tonumber(now_ts - first_open)/86400)
    local last_open_days_ago = math.floor(tonumber(now_ts - last_open)/86400)
    local avg_time_per_page = book_read_time / book_read_pages
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    local more_arrow = BD.mirroredUILayout() and "◂" or "▸"
    return {
        -- Book metadata
        { _("Title"), title},
        { _("Author(s)"), authors, separator = true },

        -- Time-focused book stats
        { _("Total time spent on this book"), datetime.secondsToClockDuration(user_duration_format, total_time_book, false) },
        { _("Time spent reading"), datetime.secondsToClockDuration(user_duration_format, book_read_time, false), separator = true },

        -- Day-focused book stats
        { _("Days reading this book") .. " " .. more_arrow, tonumber(total_days),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)
                self.kv = KeyValuePage:new{
                    title = T(_("Days reading %1"), title),
                    value_overflow_align = "right",
                    kv_pairs = self:getDatesForBook(id_book),
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end,
                    close_callback = function() self.kv = nil end,
                }
                UIManager:show(self.kv)
            end,
        },
        { _("Average time per day"), datetime.secondsToClockDuration(user_duration_format, book_read_time/tonumber(total_days), false), separator = true },

        -- Date-focused book stats
        { _("Book start date"), T(N_("(1 day ago) %2", "(%1 days ago) %2", first_open_days_ago), first_open_days_ago, datetime.secondsToDate(tonumber(first_open), true)) },
        { _("Last read date"), T(N_("(1 day ago) %2", "(%1 days ago) %2", last_open_days_ago), last_open_days_ago, datetime.secondsToDate(tonumber(last_open), true)), separator = true },

        -- Page-focused book stats
        { _("Last read page/Total pages"), string.format("%d / %d (%d%%)", last_page, pages, Math.round(100*last_page/pages)) },
        { _("Pages read"), string.format("%d (%d%%)", total_read_pages, Math.round(100*total_read_pages/pages)) },
        { _("Average time per page"), datetime.secondsToClockDuration(user_duration_format, avg_time_per_page, false), separator = true },

        -- Highlights
        { _("Book highlights"), highlights },
        { _("Book notes"), notes },
    }
end

local function sqlDaily()
    return
    [[
            SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= %d
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;
    ]]
end

local function sqlWeekly()
    return
    [[
            SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%W', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= %d
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;
    ]]
end

local function sqlMonthly()
    return
    [[
            SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= %d
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;
    ]]
end

function ReaderStatistics:callbackMonthly(begin, finish, date_text, book_mode)
    local kv = self.kv
    UIManager:close(kv)
    if book_mode then
        self.kv = KeyValuePage:new{
            title = T(_("Books read in %1"), date_text),
            value_align = "right",
            kv_pairs = self:getBooksFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end,
            close_callback = function() self.kv = nil end,
        }
    else
        self.kv = KeyValuePage:new{
            title = date_text,
            value_overflow_align = "right",
            kv_pairs = self:getDaysFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end,
            close_callback = function() self.kv = nil end,
        }
    end
    UIManager:show(self.kv)
end

function ReaderStatistics:callbackWeekly(begin, finish, date_text, book_mode)
    local kv = self.kv
    UIManager:close(kv)
    if book_mode then
        self.kv = KeyValuePage:new{
            title = T(_("Books read in %1"), date_text),
            value_align = "right",
            kv_pairs = self:getBooksFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end,
            close_callback = function() self.kv = nil end,
        }
    else
        self.kv = KeyValuePage:new{
            title = date_text,
            value_overflow_align = "right",
            kv_pairs = self:getDaysFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end,
            close_callback = function() self.kv = nil end,
        }
    end
    UIManager:show(self.kv)
end

function ReaderStatistics:callbackDaily(begin, finish, date_text)
    local kv = self.kv
    UIManager:close(kv)
    self.kv = KeyValuePage:new{
        title = date_text,
        value_align = "right",
        kv_pairs = self:getBooksFromPeriod(begin, finish),
        callback_return = function()
            UIManager:show(kv)
            self.kv = kv
        end,
        close_callback = function() self.kv = nil end,
    }
    UIManager:show(self.kv)
end

-- sdays -> number of days to show
-- ptype -> daily - show daily without weekday name
--          daily_weekday - show daily with weekday name
--          weekly - show weekly
--          monthly - show monthly
--          book_mode = if true than show book in this period
function ReaderStatistics:getDatesFromAll(sdays, ptype, book_mode)
    local results = {}
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour *3600 + now_t.min*60 + now_t.sec
    local now_stamp = os.time()
    local one_day = 86400 -- one day in seconds
    local period_begin = 0
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    if sdays > 0 then
        period_begin = now_stamp - ((sdays-1) * one_day) - from_begin_day
    end
    local sql_stmt_res_book
    if ptype == "daily" or ptype == "daily_weekday" then
        sql_stmt_res_book = sqlDaily()
    elseif ptype == "weekly" then
        sql_stmt_res_book = sqlWeekly()
    elseif ptype == "monthly" then
        sql_stmt_res_book = sqlMonthly()
    end
    self:insertDB()
    local conn = SQ3.open(db_location)
    local result_book = conn:exec(string.format(sql_stmt_res_book, period_begin))
    conn:close()

    if result_book == nil then
        return {}
    end
    for i=1, #result_book.dates do
        local timestamp = tonumber(result_book[4][i])
        local date_text
        if ptype == "daily_weekday" then
            date_text = string.format("%s (%s)",
                os.date("%Y-%m-%d", timestamp),
                datetime.shortDayOfWeekTranslation[os.date("%a", timestamp)])
        elseif ptype == "daily" then
            date_text = result_book[1][i]
        elseif ptype == "weekly" then
            date_text = T(_("%1 Week %2"), os.date("%Y", timestamp), os.date(" %W", timestamp))
        elseif ptype == "monthly" then
            date_text = datetime.longMonthTranslation[os.date("%B", timestamp)] .. os.date(" %Y", timestamp)
        else
            date_text = result_book[1][i]
        end
        if ptype == "monthly" then
            local year_begin = tonumber(os.date("%Y", timestamp))
            local year_end
            local month_begin = tonumber(os.date("%m", timestamp))
            local month_end
            if month_begin == 12 then
                year_end = year_begin + 1
                month_end = 1
            else
                year_end = year_begin
                month_end = month_begin + 1
            end
            local start_month = os.time{year=year_begin, month=month_begin, day=1, hour=0, min=0 }
            local stop_month = os.time{year=year_end, month=month_end, day=1, hour=0, min=0 }
            table.insert(results, {
                date_text,
                T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
                callback = function()
                    self:callbackMonthly(start_month, stop_month, date_text, book_mode)
                end,
            })
        elseif ptype == "weekly" then
            local time_book = os.date("%H%M%S%w", timestamp)
            local begin_week = tonumber(result_book[4][i]) - 3600 * tonumber(string.sub(time_book,1,2))
                - 60 * tonumber(string.sub(time_book,3,4)) - tonumber(string.sub(time_book,5,6))
            local weekday = tonumber(string.sub(time_book,7,8))
            if weekday == 0 then weekday = 6 else weekday = weekday - 1 end
            begin_week = begin_week - weekday * 86400
            table.insert(results, {
                date_text,
                T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
                callback = function()
                    self:callbackWeekly(begin_week, begin_week + 7 * 86400, date_text, book_mode)
                end,
            })
        else
            local time_book = os.date("%H%M%S", timestamp)
            local begin_day = tonumber(result_book[4][i]) - 3600 * tonumber(string.sub(time_book,1,2))
                - 60 * tonumber(string.sub(time_book,3,4)) - tonumber(string.sub(time_book,5,6))
            table.insert(results, {
                date_text,
                T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
                callback = function()
                    self:callbackDaily(begin_day, begin_day + 86400, date_text)
                end,
            })
        end
    end
    return results
end

function ReaderStatistics:getDaysFromPeriod(period_begin, period_end)
    local results = {}
    local sql_stmt_res_book = [[
        SELECT dates,
               count(*)             AS pages,
               sum(sum_duration)    AS durations,
               start_time
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                           sum(duration)                                                 AS sum_duration,
                           start_time
                    FROM   page_stat
                    WHERE  start_time BETWEEN %d AND %d
                    GROUP  BY id_book, page, dates
               )
        GROUP  BY dates
        ORDER  BY dates DESC;
    ]]
    local conn = SQ3.open(db_location)
    local result_book = conn:exec(string.format(sql_stmt_res_book, period_begin, period_end - 1))
    conn:close()

    if result_book == nil then
        return {}
    end
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    for i=1, #result_book.dates do
        local time_begin = os.time{year=string.sub(result_book[1][i],1,4), month=string.sub(result_book[1][i],6,7),
            day=string.sub(result_book[1][i],9,10), hour=0, min=0, sec=0 }
        table.insert(results, {
            result_book[1][i],
            T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
            callback = function()
                local kv = self.kv
                UIManager:close(kv)
                self.kv = KeyValuePage:new{
                    title = T(_("Books read %1"), result_book[1][i]),
                    value_align = "right",
                    kv_pairs = self:getBooksFromPeriod(time_begin, time_begin + 86400),
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end,
                    close_callback = function() self.kv = nil end,
                }
                UIManager:show(self.kv)
            end,
        })
    end
    return results
end

function ReaderStatistics:getBooksFromPeriod(period_begin, period_end, callback_shows_days)
    local results = {}
    local sql_stmt_res_book = [[
        SELECT  book_tbl.title AS title,
                count(distinct page_stat_tbl.page),
                sum(page_stat_tbl.duration),
                book_tbl.id
        FROM    page_stat AS page_stat_tbl, book AS book_tbl
        WHERE   page_stat_tbl.id_book=book_tbl.id AND page_stat_tbl.start_time BETWEEN %d AND %d
        GROUP   BY book_tbl.id
        ORDER   BY book_tbl.last_open DESC;
    ]]
    local conn = SQ3.open(db_location)
    local result_book = conn:exec(string.format(sql_stmt_res_book, period_begin + 1, period_end))
    conn:close()

    if result_book == nil then
        return {}
    end
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    for i=1, #result_book.title do
        table.insert(results, {
            result_book[1][i],
            T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
            duration = tonumber(result_book[3][i]),
            book_id = tonumber(result_book[4][i]),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)
                if callback_shows_days then -- not used currently by any code
                    self.kv = KeyValuePage:new{
                        title = T(_("Days reading %1"), result_book[1][i]),
                        kv_pairs = self:getDatesForBook(tonumber(result_book[4][i])),
                        value_overflow_align = "right",
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                else
                    self.kv = KeyValuePage:new{
                        title = result_book[1][i],
                        kv_pairs = self:getBookStat(tonumber(result_book[4][i])),
                        value_align = "right",
                        single_page = true,
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end,
                        close_callback = function() self.kv = nil end,
                    }
                end
                UIManager:show(self.kv)
            end,
            hold_callback = function(kv_page, kv_item)
                self:resetStatsForBookForPeriod(result_book[4][i], period_begin, period_end, false, function()
                    kv_page:removeKeyValueItem(kv_item) -- Reset, refresh what's displayed
                end)
            end,
        })
    end
    return results
end

function ReaderStatistics:getReadingProgressStats(sdays)
    local results = {}
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour *3600 + now_t.min*60 + now_t.sec
    local now_stamp = os.time()
    local one_day = 86400 -- one day in seconds
    local period_begin = now_stamp - ((sdays-1) * one_day) - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT dates,
               count(*)             AS pages,
               sum(sum_duration)    AS durations,
               start_time
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                           sum(duration)                                                 AS sum_duration,
                           start_time
                    FROM   page_stat
                    WHERE  start_time >= %d
                    GROUP  BY id_book, page, dates
               )
        GROUP  BY dates
        ORDER  BY dates DESC;
    ]]
    local result_book = conn:exec(string.format(sql_stmt, period_begin))
    conn:close()

    if not result_book then return end
    for i = 1, sdays do
        local pages = tonumber(result_book[2][i])
        local duration = tonumber(result_book[3][i])
        local date_read = result_book[1][i]
        if pages == nil then pages = 0 end
        if duration == nil then duration = 0 end
        table.insert(results, {
            pages,
            duration,
            date_read
        })
    end
    return results
end

function ReaderStatistics:getDatesForBook(id_book)
    local results = {}
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT date(start_time, 'unixepoch', 'localtime') AS dates,
               count(DISTINCT page)                       AS pages,
               sum(duration)                              AS durations,
               min(start_time)                            AS min_start_time,
               max(start_time)                            AS max_start_time
        FROM   page_stat
        WHERE  id_book = %d
        GROUP  BY Date(start_time, 'unixepoch', 'localtime')
        ORDER  BY dates DESC;
    ]]
    local result_book = conn:exec(string.format(sql_stmt, id_book))
    conn:close()

    if result_book == nil then
        return {}
    end
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    for i=1, #result_book.dates do
        table.insert(results, {
            result_book[1][i],
            T(N_("%1 (1 page)", "%1 (%2 pages)", tonumber(result_book[2][i])), datetime.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false), tonumber(result_book[2][i])),
            hold_callback = function(kv_page, kv_item)
                self:resetStatsForBookForPeriod(id_book, result_book[4][i], result_book[5][i], result_book[1][i], function()
                    kv_page:removeKeyValueItem(kv_item) -- Reset, refresh what's displayed
                end)
            end,
        })
    end
    return results
end

function ReaderStatistics:resetStatsForBookForPeriod(id_book, min_start_time, max_start_time, day_str, on_reset_confirmed_callback)
    local confirm_text
    local confirm_button_text
    if day_str then
        -- From getDatesForBook(): we are showing a list of days, with book title at top title:
        -- show the day string to confirm the long-press was on the right day
        confirm_text = T(_("Do you want to reset statistics for day %1 for this book?"), day_str)
        confirm_button_text = C_("Reset statistics for day for book", "Reset")
    else
        -- From getBooksFromPeriod(): we are showing a list of books, with the period as top title:
        -- show the book title to confirm the long-press was on the right book
        local conn = SQ3.open(db_location)
        local sql_stmt = [[
            SELECT title
            FROM   book
            WHERE  id = %d;
        ]]
        local book_title = conn:rowexec(string.format(sql_stmt, id_book))
        conn:close()
        confirm_text = T(_("Do you want to reset statistics for this period for book:\n%1"), book_title)
        confirm_button_text = C_("Reset statistics for period for book", "Reset")
    end
    UIManager:show(ConfirmBox:new{
        text = confirm_text,
        cancel_text = _("Cancel"),
        cancel_callback = function()
            return
        end,
        ok_text = confirm_button_text,
        ok_callback = function()
            local conn = SQ3.open(db_location)
            local sql_stmt = [[
                DELETE FROM page_stat_data
                WHERE  id_book = ?
                AND start_time between ? and ?
            ]]
            local stmt = conn:prepare(sql_stmt)
            stmt:reset():bind(id_book, min_start_time, max_start_time):step()
            stmt:close()
            conn:close()
            if on_reset_confirmed_callback then
                on_reset_confirmed_callback()
            end
        end,
    })
end

function ReaderStatistics:getTotalStats()
    self:insertDB()
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration)
        FROM   page_stat;
    ]]
    local total_books_time = conn:rowexec(sql_stmt)
    if total_books_time == nil then
        total_books_time = 0
    end
    local total_stats = {}
    sql_stmt = [[
        SELECT id
        FROM   book
        ORDER  BY last_open DESC;
    ]]
    local id_book_tbl = conn:exec(sql_stmt)
    local nr_books
    if id_book_tbl ~= nil then
        nr_books = #id_book_tbl.id
    else
        nr_books = 0
    end
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    for i=1, nr_books do
        local id_book = tonumber(id_book_tbl[1][i])
        sql_stmt = [[
            SELECT title
            FROM   book
            WHERE  id = %d;
        ]]
        local book_title = conn:rowexec(string.format(sql_stmt, id_book))
        sql_stmt = [[
            SELECT sum(duration)
            FROM   page_stat
            WHERE  id_book = %d;
        ]]
        local total_time_book = conn:rowexec(string.format(sql_stmt,id_book))
        if total_time_book == nil then
            total_time_book = 0
        end
        table.insert(total_stats, {
            book_title,
            datetime.secondsToClockDuration(user_duration_format, total_time_book, false),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)

                self.kv = KeyValuePage:new{
                    title = book_title,
                    kv_pairs = self:getBookStat(id_book),
                    value_align = "right",
                    single_page = true,
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end,
                    close_callback = function() self.kv = nil end,
                }
                UIManager:show(self.kv)
            end,
        })
    end
    conn:close()

    return T(_("Total time spent reading: %1"), datetime.secondsToClockDuration(user_duration_format, total_books_time, false)), total_stats
end

function ReaderStatistics:genResetBookSubItemTable()
    local sub_item_table = {}
    table.insert(sub_item_table, {
        text = _("Reset statistics for the current book"),
        keep_menu_open = true,
        callback = function()
            self:resetCurrentBook()
        end,
        enabled_func = function() return self:isEnabled() and self.id_curr_book end,
        separator = true,
    })
    table.insert(sub_item_table, {
        text = _("Reset statistics per book"),
        keep_menu_open = true,
        callback = function()
            self:resetPerBook()
        end,
        separator = true,
    })
    local reset_minutes = { 1, 5, 15, 30, 60 }
    for _, minutes in ipairs(reset_minutes) do
        local text = T(N_("Reset stats for books read for < 1 m",
                          "Reset stats for books read for < %1 m",
                          minutes), minutes)
        table.insert(sub_item_table, {
            text = text,
            keep_menu_open = true,
            callback = function()
                self:deleteBooksByTotalDuration(minutes)
            end,
        })
    end
    return sub_item_table
end

function ReaderStatistics:resetPerBook()
    local total_stats = {}

    self:insertDB()
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT id
        FROM   book
        ORDER  BY last_open DESC;
    ]]
    local id_book_tbl = conn:exec(sql_stmt)
    local nr_books
    if id_book_tbl ~= nil then
        nr_books = #id_book_tbl.id
    else
        nr_books = 0
    end

    local user_duration_format = G_reader_settings:readSetting("duration_format")
    local total_time_book
    local kv_reset_book
    for i=1, nr_books do
        local id_book = tonumber(id_book_tbl[1][i])
        sql_stmt = [[
            SELECT title
            FROM   book
            WHERE  id = %d;
        ]]
        local book_title = conn:rowexec(string.format(sql_stmt, id_book))
        sql_stmt = [[
            SELECT sum(duration)
            FROM   page_stat
            WHERE  id_book = %d;
        ]]
        total_time_book = conn:rowexec(string.format(sql_stmt,id_book))
        if total_time_book == nil then
            total_time_book = 0
        end

        if id_book ~= self.id_curr_book then
            table.insert(total_stats, {
                book_title,
                datetime.secondsToClockDuration(user_duration_format, total_time_book, false),
                id_book,
                callback = function(kv_page, kv_item)
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Do you want to reset statistics for book:\n%1"), book_title),
                        cancel_text = _("Cancel"),
                        cancel_callback = function()
                            return
                        end,
                        ok_text = _("Reset"),
                        ok_callback = function()
                            self:deleteBook(id_book)
                            kv_page:removeKeyValueItem(kv_item) -- Reset, refresh what's displayed
                        end,
                    })
                end,
            })
        end
    end
    conn:close()

    kv_reset_book = KeyValuePage:new{
        title = _("Reset book statistics"),
        value_align = "right",
        kv_pairs = total_stats,
    }
    UIManager:show(kv_reset_book)
end

function ReaderStatistics:resetCurrentBook()
    -- Flush to db first, so we get a resetVolatileStats
    self:insertDB()

    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT title
        FROM   book
        WHERE  id = %d;
    ]]
    local book_title = conn:rowexec(string.format(sql_stmt, self.id_curr_book))
    conn:close()

    UIManager:show(ConfirmBox:new{
        text = T(_("Do you want to reset statistics for book:\n%1"), book_title),
        cancel_text = _("Cancel"),
        cancel_callback = function()
            return
        end,
        ok_text = _("Reset"),
        ok_callback = function()
            self:deleteBook(self.id_curr_book)

            -- We also need to reset the time/page/avg tracking
            self.book_read_pages = 0
            self.book_read_time = 0
            self.avg_time = math.floor(0.50 * self.settings.max_sec)
            logger.dbg("ReaderStatistics: Initializing average time per page at 50% of the max value, i.e.,", self.avg_time)

            -- And the current volatile stats
            self:resetVolatileStats(os.time())

            -- And re-create the Book's data in the book table and get its new ID...
            self.id_curr_book = self:getIdBookDB()
        end,
    })
end

function ReaderStatistics:deleteBook(id_book)
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
            DELETE FROM book
            WHERE  id = ?;
        ]]
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(id_book):step()

    sql_stmt = [[
            DELETE FROM page_stat_data
            WHERE  id_book = ?;
        ]]
    stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(id_book):step()
    stmt:close()
    conn:close()
end

function ReaderStatistics:deleteBooksByTotalDuration(max_total_duration_mn)
    local max_total_duration_sec = max_total_duration_mn * 60
    UIManager:show(ConfirmBox:new{
        text = T(N_("Permanently remove statistics for books read for less than 1 minute?",
                    "Permanently remove statistics for books read for less than %1 minutes?",
                    max_total_duration_mn), max_total_duration_mn),
        ok_text = _("Remove"),
        ok_callback = function()
            -- Allow following SQL statements to work even when doc less by
            -- using -1 as the book id, as real book ids are positive.
            local id_curr_book = self.id_curr_book or -1
            local conn = SQ3.open(db_location)
            local sql_stmt = [[
                    DELETE FROM page_stat_data
                    WHERE  id_book IN (
                      SELECT id FROM book WHERE id != ? AND (total_read_time IS NULL OR total_read_time < ?)
                    );
                ]]
            local stmt = conn:prepare(sql_stmt)
            stmt:reset():bind(id_curr_book, max_total_duration_sec):step()
            sql_stmt = [[
                    DELETE FROM book
                    WHERE  id != ? AND (total_read_time IS NULL OR total_read_time < ?);
                ]]
            stmt = conn:prepare(sql_stmt)
            stmt:reset():bind(id_curr_book, max_total_duration_sec):step()
            stmt:close()
            -- Get nb of deleted books
            sql_stmt = [[
                SELECT changes();
            ]]
            local nb_deleted = conn:rowexec(sql_stmt)
            nb_deleted = nb_deleted and tonumber(nb_deleted) or 0
            if max_total_duration_mn >= 30 and nb_deleted >= 10 then
                -- Do a VACUUM to reduce db size (but not worth doing if not much was removed)
                conn:exec("PRAGMA temp_store = 2;") -- use memory for temp files
                local ok, errmsg = pcall(conn.exec, conn, "VACUUM;") -- this may take some time
                if not ok then
                    logger.warn("Failed compacting statistics database:", errmsg)
                end
            end
            conn:close()
            UIManager:show(InfoMessage:new{
                text = nb_deleted > 0 and T(N_("Statistics for 1 book removed.",
                                               "Statistics for %1 books removed.",
                                               nb_deleted), nb_deleted)
                                       or T(_("No statistics removed."))
            })
        end,
    })
end


function ReaderStatistics:onPosUpdate(pos, pageno)
    if self.curr_page ~= pageno then
        self:onPageUpdate(pageno)
    end
end

function ReaderStatistics:onDualPageModeEnabled(enabled, base)
    if not enabled then
        return
    end

    logger.dbg("ReaderStatistics:onDualPageModeEnabled: setting page state for page pair", base)

    local pair = self.ui.paging:getDualPagePairFromBasePage(base)
    if #pair == 1 and pair[#pair] == self.curr_page then
        return
    end

    local ts = os.time()

    if self.page_stat and self.page_stat[base] then
        local page_data = self.page_stat[base]
        local latest = page_data[#page_data]
        local original_ts = latest and latest[1]
        if not original_ts then
            ts = original_ts
        end
    end

    for _, page in ipairs(pair) do
        logger.dbg("ReaderStatistics:onDualPageModeEnabled setting page_data for", page, "to", ts)
        local page_data = self.page_stat[page]

        if page_data then
            table.insert(page_data, { ts, 0 })
        else
            self.page_stat[page] = { { ts, 0 } }
        end
    end
end

function ReaderStatistics:onPageUpdate(pageno)
    if not self:isEnabledAndNotFrozen() then
        return
    end

    logger.dbg("ReaderStatistics:onPageUpdate", pageno)

    if self._reading_paused_ts then
        -- Reading paused: don't update stats, but remember the current
        -- page for when reading resumed.
        self._reading_paused_curr_page = pageno
        return
    end

    -- We only care about *actual* page turns ;)
    if self.curr_page == pageno then
        return
    end

    local closing = false
    if pageno == false then     -- from onCloseDocument()
        closing = true
        pageno = self.curr_page -- avoid issues in following code
    end

    self.pageturn_count = self.pageturn_count + 1
    local now_ts = os.time()
    local pages = { pageno }

    if self.ui.paging and
        self.ui.paging:isDualPageEnabled() and
        (self.settings.dual_page_mode_divide_duration_by_two or self.settings.dual_page_mode_duplicate_duration) then
        self.pageturn_count = self.pageturn_count + 1

        local pair = self.ui.paging:getDualPagePairFromBasePage(self.curr_page)
        pages = self.ui.paging:getDualPagePairFromBasePage(pageno)

        for _, page in ipairs(pair) do
            self:updateDurtationForSinglePageTurn(now_ts, page, self.settings.dual_page_mode_divide_duration_by_two)
        end
    else
        self:updateDurtationForSinglePageTurn(now_ts, self.curr_page, false)
    end

    self.curr_page = pageno

    if closing then
        return -- current page data updated, nothing more needed
    end

    for _, page in ipairs(pages) do
        local new_page_data = self.page_stat[page]
        if new_page_data then
            table.insert(new_page_data, { now_ts, 0 })
        else
            self.page_stat[page] = { { now_ts, 0 } }
        end
    end

    -- We want a flush to db every 50 page turns
    if self.pageturn_count >= MAX_PAGETURNS_BEFORE_FLUSH then
        -- I/O, delay until after the pageturn, but reset the count now, to avoid potentially scheduling multiple inserts...
        self.pageturn_count = 0
        UIManager:tickAfterNext(function()
            self:insertDB()
            -- insertDB will call resetVolatileStats for us ;)
        end)
    end

    -- Update average time per page (if need be, insertDB will have updated the totals and cleared the volatiles)
    -- NOTE: Until insertDB runs, while book_read_pages only counts *distinct* pages,
    --       and while mem_read_pages does the same, there may actually be an overlap between the two!
    --       (i.e., the same page may be counted as read both in total and in mem, inflating the pagecount).
    --       Only insertDB will actually check that the count (and as such average time) is actually accurate.
    if self.book_read_pages > 0 or self.mem_read_pages > 0 then
        self.avg_time = (self.book_read_time + self.mem_read_time) / (self.book_read_pages + self.mem_read_pages)
    end
end

-- @param pageno number should be the page we just turned away from
function ReaderStatistics:updateDurtationForSinglePageTurn(now_ts, pageno, divide_diff_by_two)
    logger.dbg("ReaderStatistics:updateDurtationForSinglePageTurn:", now_ts, pageno,  divide_diff_by_two)

    -- Get the previous page's last timestamp (if there is one)
    local page_data = self.page_stat[pageno]
    -- This is a list of tuples, in insertion order, we want the last one
    local data_tuple = page_data and page_data[#page_data]
    -- Tuple layout is { timestamp, duration }
    local then_ts = data_tuple and data_tuple[1]
    -- If we don't have a previous timestamp to compare to, abort early
    if not then_ts then
        logger.dbg("ReaderStatistics: No timestamp for previous page", pageno)

        return
    end

    -- By now, we're sure that we actually have a tuple (and the rest of the code ensures they're sane, i.e., zero-initialized)
    local curr_duration = data_tuple[2]
    -- NOTE: If all goes well, given the earlier curr_page != pageno check, curr_duration should always be 0 here.
    -- Compute the difference between now and the previous page's last timestamp
    local diff_time = now_ts - then_ts

    if divide_diff_by_two then
        diff_time = diff_time / 2
    end

    if diff_time >= self.settings.min_sec and diff_time <= self.settings.max_sec then
        self.mem_read_time = self.mem_read_time + diff_time
        -- If it's the first time we're computing a duration for this page, count it as read
        if #page_data == 1 and curr_duration == 0 then
            self.mem_read_pages = self.mem_read_pages + 1
        end
        -- Update the tuple with the computed duration
        data_tuple[2] = curr_duration + diff_time
    elseif diff_time > self.settings.max_sec then
        self.mem_read_time = self.mem_read_time + self.settings.max_sec
        if #page_data == 1 and curr_duration == 0 then
            self.mem_read_pages = self.mem_read_pages + 1
        end
        -- Update the tuple with the computed duration
        data_tuple[2] = curr_duration + self.settings.max_sec
    end
end

-- For backward compatibility
function ReaderStatistics:importFromFile(base_path, item)
    item = util.trim(item)
    if item ~= ".stat" then
        local statistic_file = FFIUtil.joinPath(base_path, item)
        if lfs.attributes(statistic_file, "mode") == "directory" then
            return
        end
        local ok, stored = pcall(dofile, statistic_file)
        if ok then
            return stored
        end
    end
end

function ReaderStatistics:onCloseDocument()
    self:onPageUpdate(false) -- update current page duration
    self:insertDB()
end

function ReaderStatistics:onAnnotationsModified(annotations)
    if self.settings.is_enabled then
        if annotations.nb_highlights_added then
            self.data.highlights = self.data.highlights + annotations.nb_highlights_added
        end
        if annotations.nb_notes_added then
            self.data.notes = self.data.notes + annotations.nb_notes_added
        end
    end
end

-- Triggered by auto_save_settings_interval_minutes
function ReaderStatistics:onSaveSettings()
    self:insertDB()
end

-- in case when screensaver starts
function ReaderStatistics:onSuspend()
    self:insertDB()
    self:onReadingPaused()
end

-- screensaver off
function ReaderStatistics:onResume()
    self.start_current_period = os.time()
    self:onReadingResumed()
end

function ReaderStatistics:onReadingPaused()
    if self:isEnabledAndNotFrozen() then
        if not self._reading_paused_ts then
            self._reading_paused_ts = os.time()
        end
    end
end

function ReaderStatistics:onReadingResumed()
    if self:isEnabledAndNotFrozen() then
        if self._reading_paused_ts then
            -- Just add the pause duration to the current page start_time
            local pause_duration = os.time() - self._reading_paused_ts
            local page_data = self.page_stat[self.curr_page]
            local data_tuple = page_data and page_data[#page_data]
            if data_tuple then
                data_tuple[1] = data_tuple[1] + pause_duration
            end
            if self._reading_paused_curr_page and self._reading_paused_curr_page ~= self.curr_page then
                self._reading_paused_ts = nil
                self:onPageUpdate(self._reading_paused_curr_page)
                self._reading_paused_curr_page = nil
            end
        end
    end
    self._reading_paused_ts = nil
end

function ReaderStatistics:onReaderReady(config)
    if self.settings.is_enabled then
        self.data = config:readSetting("stats", { performance_in_pages = {} })
        self.doc_md5 = config:readSetting("partial_md5_checksum")
        -- we have correct page count now, do the actual initialization work
        self:initData()
        self.view.footer:maybeUpdateFooter()
    end
end

function ReaderStatistics:onShowCalendarView()
    self:insertDB()
    self.kv = nil -- clean left over stack link
    local CalendarView = require("calendarview")
    UIManager:show(CalendarView:new{
        reader_statistics = self,
        start_day_of_week = self.settings.calendar_start_day_of_week,
        nb_book_spans = self.settings.calendar_nb_book_spans,
        show_hourly_histogram = self.settings.calendar_show_histogram,
        browse_future_months = self.settings.calendar_browse_future_months,
    })
end

function ReaderStatistics:onShowCalendarDayView()
    self:insertDB()
    self.kv = nil -- clean left over stack link
    local CalendarView = require("calendarview")
    CalendarView:showCalendarDayView(self)
end

-- Used by calendarview.lua CalendarView
function ReaderStatistics:getFirstTimestamp()
    local sql_stmt = [[
        SELECT min(start_time)
        FROM   page_stat;
    ]]
    local conn = SQ3.open(db_location)
    local first_ts = conn:rowexec(sql_stmt)
    conn:close()
    return first_ts and tonumber(first_ts) or nil
end

function ReaderStatistics:getReadingRatioPerHourByDay(month)
    -- We used to have in the SQL statement (with ? = 'YYYY-MM'):
    --   WHERE  strftime('%Y-%m', start_time, 'unixepoch', 'localtime') = ?
    -- but strftime()ing all start_time is slow.
    -- Converting the month into timestamp boundaries, and just comparing
    -- integers, can be 5 times faster.
    -- We let SQLite compute these timestamp boundaries from the provided
    -- month; we need the start of the month to be a real date:
    month = month.."-01"
    local offset = not self.settings.calendar_use_day_time_shift and 0 or (self.settings.calendar_day_start_hour or 0) * 3600 + (self.settings.calendar_day_start_minute or 0) * 60
    local sql_stmt = [[
        SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            strftime('%H', start_time, 'unixepoch', 'localtime') hour,
            sum(duration)/3600.0 ratio
        FROM  (
            SELECT
                start_time-? as start_time,
                duration
            FROM page_stat
            WHERE  start_time BETWEEN strftime('%s', ?, 'utc')
                                  AND strftime('%s', ?, 'utc', '+33 days', 'start of month', '-1 second')
        )
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            strftime('%H', start_time, 'unixepoch', 'localtime')
        ORDER BY day, hour;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(offset, month, month):resultset("i")
    stmt:close()
    conn:close()
    local per_day = {}
    for i=1, nb do
        local day, hour, ratio = res[1][i], res[2][i], res[3][i]
        if not per_day[day] then
            per_day[day] = {}
        end
        -- +1 as histogram starts counting at 1
        per_day[day][tonumber(hour)+1] = ratio
    end
    return per_day
end

function ReaderStatistics:getReadBookByDay(month)
    month = month.."-01"
    local offset = not self.settings.calendar_use_day_time_shift and 0 or (self.settings.calendar_day_start_hour or 0) * 3600 + (self.settings.calendar_day_start_minute or 0) * 60
    local sql_stmt = [[
        SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            sum(duration) durations,
            id_book book_id,
            title book_title
        FROM  (
            SELECT start_time-? as start_time, duration, page_stat.id_book, book.title
            FROM page_stat
            JOIN   book ON book.id = page_stat.id_book
            WHERE  start_time BETWEEN strftime('%s', ?, 'utc')
                                  AND strftime('%s', ?, 'utc', '+33 days', 'start of month', '-1 second')
        )
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            id_book,
            title
        ORDER BY day, durations desc, book_id, book_title;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(offset, month, month):resultset("i")
    stmt:close()
    conn:close()
    local per_day = {}
    for i=1, nb do
        -- (We don't care about the duration, we just needed it
        -- to have the books in decreasing duration order)
        local day, duration, book_id, book_title = res[1][i], res[2][i], res[3][i], res[4][i] -- luacheck: no unused
        if not per_day[day] then
            per_day[day] = {}
        end
        table.insert(per_day[day], { id = tonumber(book_id), title = tostring(book_title) })
    end
    return per_day
end

function ReaderStatistics:getReadingDurationBySecond(ts)
    -- Two read spans, separated by a duration smaller than this, will be merged and appear as one span
    local ignorable_gap = math.max(30, self.settings.min_sec)
    local sql_stmt = [[
        SELECT
            start_time - ? as start,
            start_time - ? + duration as finish,
            id_book book_id,
            book.title book_title
        FROM   page_stat_data
        JOIN   book ON book.id = page_stat_data.id_book
        WHERE  start_time BETWEEN ? AND ?
        ORDER BY start;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(ts, ts, ts - self.settings.max_sec - ignorable_gap, ts + 86400 - 1 + ignorable_gap):resultset("i")
    stmt:close()
    conn:close()
    local per_book = {}
    local last_book_id
    local last_book_finish
    local done = false
    for i=1, nb do
        local start, finish, book_id, book_title = tonumber(res[1][i]), tonumber(res[2][i]), tonumber(res[3][i]), tostring(res[4][i])
        -- This is a bit complex as we want to ensure a page read span continuation
        -- from/to previous/next day if the gap is low enough
        if start >= 0 or finish >= 0 then
            -- Page read the current day (or started the next day before ignorable_gap seconds)
            if start < 0 then -- started previous day
                start = 0
            end
            if finish >= 86400 then -- next day
                finish = 86400 - 1 -- cap to this day's last second
                done = true -- no need to handle next results
            end
            if start < 86400 then
                -- Page read the current day: account for it
                if not per_book[book_id] then
                    per_book[book_id] = {
                        title = book_title,
                        periods = {},
                    }
                end
                local periods = per_book[book_id].periods
                if book_id == last_book_id and start - last_book_finish <= ignorable_gap then
                    -- Same book as previous span, no or small gap: previous span/period can be continued
                    if #periods > 0 then
                        periods[#periods].finish = finish -- extend previous span
                    else
                        -- No period yet accounted: this is a continuation from previous day's last page read:
                        -- make it start at 0, so the continuation is visible
                        table.insert(periods, { start = 0, finish = finish })
                    end
                else
                    -- Different book, or gap from previous read page of same book is not ignorable: add a new period
                    table.insert(periods, { start = start, finish = finish })
                end
            else
                -- Page started the next day
                if book_id == last_book_id and start - last_book_finish <= ignorable_gap then
                    -- Same book as current day's last span, no or small gap: current day's last
                    -- span can be continued: extend it (if it exists) to the end of current day
                    if per_book[book_id] then
                        local periods = per_book[book_id].periods
                        if #periods > 0 then
                            periods[#periods].finish = 86400 - 1
                        end
                    end
                end
                done = true -- last interesting slot
            end
            last_book_id = book_id
            last_book_finish = finish
        else
            -- Page read the previous day
            if finish >= - ignorable_gap then
                -- Page reading ended near 23h59mNNs: we may have to make the first
                -- page read the current day start at 00h00m00s
                last_book_id = book_id
                last_book_finish = finish
            end
        end
        if done then
            break
        end
    end
    return per_book
end

function ReaderStatistics:onShowReaderProgress()
    self:insertDB()
    local current_duration, current_pages = self:getCurrentBookStats()
    local today_duration, today_pages = self:getTodayBookStats()
    local dates_stats = self:getReadingProgressStats(7)
    local readingprogress
    if dates_stats then
        readingprogress = ReaderProgress:new{
            dates = dates_stats,
            current_duration = current_duration,
            current_pages = current_pages,
            today_duration = today_duration,
            today_pages = today_pages,
            --readonly = true,
        }
    end
    UIManager:show(readingprogress)
end

function ReaderStatistics:onShowBookStats()
    if not self:isEnabled() then return end
    self.kv = KeyValuePage:new{
        title = _("Current statistics"),
        kv_pairs = self:getCurrentStat(),
        value_align = "right",
        single_page = true,
    }
    UIManager:show(self.kv)
end

function ReaderStatistics:getCurrentBookReadPages()
    if not self:isEnabled() then return end
    self:insertDB()
    local sql_stmt = [[
        SELECT
          page,
          min(sum(duration), ?) AS durations,
          strftime("%s", "now") - max(start_time) AS delay
        FROM page_stat
        WHERE id_book = ?
        GROUP BY page
        ORDER BY page;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(self.settings.max_sec, self.id_curr_book):resultset("i")
    stmt:close()
    conn:close()
    local read_pages = {}
    local max_duration = 0
    for i=1, nb do
        local page, duration, delay = res[1][i], res[2][i], res[3][i]
        page = tonumber(page)
        duration = tonumber(duration)
        delay = tonumber(delay)
        read_pages[page] = {duration, delay}
        if duration > max_duration then
            max_duration = duration
        end
    end
    for page, info in pairs(read_pages) do
        -- Make the value a duration ratio (vs capped or max duration)
        read_pages[page][1] = info[1] / max_duration
    end
    return read_pages
end

function ReaderStatistics:canSync()
    return self.settings.sync_server ~= nil and self.settings.is_enabled
end

function ReaderStatistics:onSyncBookStats()
    if not self:canSync() then return end

    UIManager:show(InfoMessage:new {
        text = _("Syncing book statistics. This may take a while."),
        timeout = 1,
    })

    UIManager:nextTick(function()
        SyncService.sync(self.settings.sync_server, db_location, self.onSync)
    end)
end

function ReaderStatistics.onSync(local_path, cached_path, income_path)
    local conn_income = SQ3.open(income_path)
    local ok1, v1 = pcall(conn_income.rowexec, conn_income, "PRAGMA schema_version")
    if not ok1 or tonumber(v1) == 0 then
        -- no income db or wrong db, first time sync
        logger.warn("statistics open income DB failed", v1)
        return true
    end

    local sql = "attach '" .. income_path:gsub("'", "''") .."' as income_db;"
    -- then we try to open cached db
    local conn_cached = SQ3.open(cached_path)
    local ok2, v2 = pcall(conn_cached.rowexec, conn_cached, "PRAGMA schema_version")
    local attached_cache
    if not ok2 or tonumber(v2) == 0 then
        -- no cached or error, no item to delete
        logger.warn("statistics open cached DB failed", v2)
    else
        attached_cache = true
        sql = sql .. "attach '" .. cached_path:gsub("'", "''") ..[[' as cached_db;
            -- first we delete from income_db books that exist in cached_db but not in local_db,
            -- namely the ones that were deleted since last sync
            DELETE FROM income_db.page_stat_data WHERE id_book IN (
                SELECT id FROM income_db.book WHERE (title, authors, md5) IN (
                    SELECT title, authors, md5 FROM cached_db.book WHERE (title, authors, md5) NOT IN (
                        SELECT title, authors, md5 FROM book
                    )
                )
            );
            DELETE FROM income_db.book WHERE (title, authors, md5) IN (
                SELECT title, authors, md5 FROM cached_db.book WHERE (title, authors, md5) NOT IN (
                    SELECT title, authors, md5 FROM book
                )
            );

            -- then we delete books from local db that were present in last sync but
            -- not any more (ie. deleted in other devices)
            DELETE FROM page_stat_data WHERE id_book IN (
                SELECT id FROM book WHERE (title, authors, md5) IN (
                    SELECT title, authors, md5 FROM cached_db.book WHERE (title, authors, md5) NOT IN (
                        SELECT title, authors, md5 FROM income_db.book
                    )
                )
            );
            DELETE FROM book WHERE (title, authors, md5) IN (
                SELECT title, authors, md5 FROM cached_db.book WHERE (title, authors, md5) NOT IN (
                    SELECT title, authors, md5 FROM income_db.book
                )
            );
        ]]
    end

    conn_cached:close()
    conn_income:close()
    local conn = SQ3.open(local_path)
    local ok3, v3 = pcall(conn.exec, conn, "PRAGMA schema_version")
    if not ok3 or tonumber(v3) == 0 then
        -- no local db, this is an error
        logger.err("statistics open local DB", v3)
        return false
    end

    -- NOTE: We could replace this first `UPDATE` with an "upsert" by adding an `ON CONFLICT` clause to the
    -- following `INSERT`, but using `ON CONFLICT` unnecessarily increments the autoincrement for the table.
    -- See https://sqlite.org/forum/info/98d4fb9ced866287
    sql = sql .. [[
        -- If book was opened more recently on another device, then update local last_open field
        UPDATE book AS b
        SET last_open = i.last_open
        FROM income_db.book AS i
        WHERE (b.title, b.authors, b.md5) = (i.title, i.authors, i.md5)
          AND i.last_open > b.last_open;

        -- We merge the local db with income db to form the synced db.
        -- Do the books
        INSERT INTO book (
            title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages
        ) SELECT
            title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages
        FROM income_db.book
        WHERE (title, authors, md5) NOT IN (
            SELECT title, authors, md5 FROM book
        );

        -- We create a book_id mapping temp table (view not possible due to attached db)
        CREATE TEMP TABLE book_id_map AS
            SELECT m.id as mid, i.id as iid FROM book m --main
            INNER JOIN income_db.book i
            ON (m.title, m.authors, m.md5) = (i.title, i.authors, i.md5);
        ]]
    if attached_cache then
        -- more deletion needed
        sql = sql .. [[
        -- DELETE stat_data items
        DELETE FROM income_db.page_stat_data WHERE (id_book, page, start_time) IN (
            SELECT map.iid, page, start_time FROM cached_db.page_stat_data
            INNER JOIN book_id_map AS map ON id_book = map.mid
            WHERE (id_book, page, start_time) NOT IN (
                SELECT id_book, page, start_time FROM page_stat_data
            )
        );
        DELETE FROM page_stat_data WHERE (id_book, page, start_time) IN (
            SELECT id_book, page, start_time FROM cached_db.page_stat_data WHERE (id_book, page, start_time) NOT IN (
                SELECT map.mid, page, start_time FROM income_db.page_stat_data
                LEFT JOIN book_id_map AS map on id_book = map.iid
            )
        );]]
    end
    sql = sql .. [[
        -- Then we merge the income_db's contents into the local db
        INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages)
            SELECT map.mid, page, start_time, duration, total_pages
            FROM income_db.page_stat_data
            INNER JOIN book_id_map as map
            ON id_book = map.iid
            WHERE map.mid IS NOT null
        ON CONFLICT(id_book, page, start_time) DO UPDATE SET
        duration = MAX(duration, excluded.duration);

        -- finally we update the total numbers of book
        UPDATE book SET (total_read_pages, total_read_time) =
        (SELECT count(DISTINCT page),
                sum(duration)
         FROM   page_stat
         WHERE  id_book = book.id);
    ]]
    conn:exec(sql)
    pcall(conn.exec, conn, "COMMIT;")
    conn:exec("DETACH income_db;"..(attached_cache and "DETACH cached_db;" or ""))
    conn:close()
    return true
end

return ReaderStatistics
