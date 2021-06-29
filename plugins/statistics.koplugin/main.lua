local BD = require("ui/bidi")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
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
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
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
local DB_SCHEMA_VERSION = 20201022

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
    page_stat = {}, -- Dictionary, indexed by page (hash), contains a list (array) of { timestamp, duration } tuples.
    data = {
        title = "",
        authors = "N/A",
        language = "N/A",
        series = "N/A",
        performance_in_pages = {},
        total_time_in_sec = 0,
        highlights = 0,
        notes = 0,
        pages = 0,
        md5 = nil,
    },
}

local weekDays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" } -- in Lua wday order

local shortDayOfWeekTranslation = {
    ["Mon"] = _("Mon"),
    ["Tue"] = _("Tue"),
    ["Wed"] = _("Wed"),
    ["Thu"] = _("Thu"),
    ["Fri"] = _("Fri"),
    ["Sat"] = _("Sat"),
    ["Sun"] = _("Sun"),
}

local longDayOfWeekTranslation = {
    ["Mon"] = _("Monday"),
    ["Tue"] = _("Tuesday"),
    ["Wed"] = _("Wednesday"),
    ["Thu"] = _("Thursday"),
    ["Fri"] = _("Friday"),
    ["Sat"] = _("Saturday"),
    ["Sun"] = _("Sunday"),
}

local monthTranslation = {
    ["January"] = _("January"),
    ["February"] = _("February"),
    ["March"] = _("March"),
    ["April"] = _("April"),
    ["May"] = _("May"),
    ["June"] = _("June"),
    ["July"] = _("July"),
    ["August"] = _("August"),
    ["September"] = _("September"),
    ["October"] = _("October"),
    ["November"] = _("November"),
    ["December"] = _("December"),
}

function ReaderStatistics:isDocless()
    return self.ui == nil or self.ui.document == nil or self.ui.document.is_pic == true
end

-- NOTE: This is used in a migration script by ui/data/onetime_migration,
--       which is why it's public.
ReaderStatistics.default_settings = {
    min_sec = DEFAULT_MIN_READ_SEC,
    max_sec = DEFAULT_MAX_READ_SEC,
    is_enabled = true,
    convert_to_db = nil,
    calendar_start_day_of_week = DEFAULT_CALENDAR_START_DAY_OF_WEEK,
    calendar_nb_book_spans = DEFAULT_CALENDAR_NB_BOOK_SPANS,
    calendar_show_histogram = true,
    calendar_browse_future_months = false,
}

function ReaderStatistics:init()
    -- Disable in PIC documents (but not the FM, as we want to be registered to the FM's menu).
    if self.ui and self.ui.document and self.ui.document.is_pic then
        return
    end

    self.start_current_period = os.time()
    self:resetVolatileStats()

    self.settings = G_reader_settings:readSetting("statistics", self.default_settings)

    self.ui.menu:registerToMainMenu(self)
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
        self:insertDB(self.id_curr_book)
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
    if self:isDocless() or not self.settings.is_enabled then
        return
    end
    -- first execution
    if not self.data then
        self.data = { performance_in_pages= {} }
    end
    local book_properties = self:getBookProperties()
    self.data.title = book_properties.title
    if self.data.title == nil or self.data.title == "" then
        self.data.title = self.document.file:match("^.+/(.+)$")
    end
    self.data.authors = book_properties.authors
    if self.data.authors == nil or self.data.authors == "" then
        self.data.authors = "N/A"
    end
    self.data.language = book_properties.language
    if self.data.language == nil or self.data.language == "" then
        self.data.language = "N/A"
    end
    self.data.series = book_properties.series
    if self.data.series == nil or self.data.series == "" then
        self.data.series = "N/A"
    end

    self.data.pages = self.view.document:getPageCount()
    if not self.data.md5 then
        self.data.md5 = self:partialMd5(self.document.file)
    end
    -- Update these numbers to what's actually stored in the settings
    -- (not that "notes" is invalid and does not represent edited highlights)
    self.data.highlights, self.data.notes = self.ui.bookmark:getNumberOfHighlightsAndNotes()
    self.id_curr_book = self:getIdBookDB()
    self.book_read_pages, self.book_read_time = self:getPageTimeTotalStats(self.id_curr_book)
    if self.book_read_pages > 0 then
        self.avg_time = self.book_read_time / self.book_read_pages
    else
        -- NOTE: Possibly less weird-looking than initializing this to 0?
        self.avg_time = math.floor(0.50 * self.settings.max_sec)
        logger.dbg("ReaderStatistics: Initializing average time per page at 50% of the max value, i.e.,", self.avg_time)
    end
end

-- Reset the (volatile) stats on page count changes (e.g., after a font size update)
function ReaderStatistics:onUpdateToc()
    local new_pagecount = self.view.document:getPageCount()

    if new_pagecount ~= self.data.pages then
        logger.dbg("ReaderStatistics: Pagecount change, flushing volatile book statistics")
        -- Flush volatile stats to DB for current book, and update pagecount and average time per page stats
        self:insertDB(self.id_curr_book, new_pagecount)
    end

    -- Update our copy of the page count
    self.data.pages = new_pagecount
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

    self:insertDB(self.id_curr_book)
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
                    self:initData()
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

function ReaderStatistics:partialMd5(file)
    if file == nil then
        return nil
    end
    local bit = require("bit")
    local md5 = require("ffi/sha2").md5
    local lshift = bit.lshift
    local step, size = 1024, 1024
    local update = md5()
    local file_handle = io.open(file, 'rb')
    for i = -1, 10 do
        file_handle:seek("set", lshift(step, 2*i))
        local sample = file_handle:read(size)
        if sample then
            update(sample)
        else
            break
        end
    end
    return update()
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
        CREATE INDEX IF NOT EXISTS book_title_authors_md5 ON book(title, authors, md5);
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
                AND    authors = ?
                AND    md5 = ?;
        ]]
        local stmt = conn:prepare(sql_stmt)
        local result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
        local nr_id = tonumber(result[1])
        if nr_id == 0 then
            stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);")
            stmt:reset():bind(book_stats.title, book_stats.authors, book_stats.notes,
                last_open_book, book_stats.highlights, book_stats.pages,
                book_stats.series, book_stats.language, self:partialMd5(book_stats.file), total_read_time, total_read_pages) :step()
            sql_stmt = [[
                SELECT last_insert_rowid() AS num;
            ]]
            id_book = conn:rowexec(sql_stmt)
        else
            sql_stmt = [[
                SELECT id
                FROM   book
                WHERE  title = ?
                    AND authors = ?
                    AND md5 = ?;
            ]]
            stmt = conn:prepare(sql_stmt)
            result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
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
    for _, v in pairs(ReadHistory.hist) do
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
            AND authors = ?
            AND md5 = ?;
    ]]
    local stmt = conn:prepare(sql_stmt)
    local result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
    local nr_id = tonumber(result[1])
    if nr_id == 0 then
        -- Not in the DB yet, initialize it
        stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);")
        stmt:reset():bind(self.data.title, self.data.authors, self.data.notes,
            os.time(), self.data.highlights, self.data.pages,
            self.data.series, self.data.language, self.data.md5, 0, 0):step()
        sql_stmt = [[
            SELECT last_insert_rowid() AS num;
        ]]
        id_book = conn:rowexec(sql_stmt)
    else
        sql_stmt = [[
            SELECT id
            FROM   book
            WHERE  title = ?
                AND    authors = ?
                AND    md5 = ?;
        ]]
        stmt = conn:prepare(sql_stmt)
        result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
        id_book = result[1]
    end
    stmt:close()
    conn:close()

    return tonumber(id_book)
end

function ReaderStatistics:insertDB(id_book, updated_pagecount)
    if not id_book then
        return
    end
    local now_ts = os.time()
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

    self:resetVolatileStats(now_ts)
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

function ReaderStatistics:getBookProperties()
    local props = self.view.document:getProps()
    if props.title == "No document" or props.title == "" then
        --- @fixme Sometimes crengine returns "No document", try one more time.
        props = self.view.document:getProps()
    end
    return props
end

function ReaderStatistics:getStatisticEnabledMenuItem()
    return {
        text = _("Enabled"),
        checked_func = function() return self.settings.is_enabled end,
        callback = function()
            -- if was enabled, have to save data to file
            if self.settings.is_enabled and not self:isDocless() then
                self:insertDB(self.id_curr_book)
                self.ui.doc_settings:saveSetting("stats", self.data)
            end

            self.settings.is_enabled = not self.settings.is_enabled
            -- if was disabled have to get data from db
            if self.settings.is_enabled and not self:isDocless() then
                self:initData()
                self.start_current_period = os.time()
                self.curr_page = self.ui:getCurrentPage()
                self:resetVolatileStats(self.start_current_period)
            end
            if not self:isDocless() then
                self.view.footer:onUpdateFooter()
            end
        end,
    }
end

function ReaderStatistics:addToMainMenu(menu_items)
    menu_items.statistics = {
        text = _("Reading statistics"),
        sub_item_table = {
            self:getStatisticEnabledMenuItem(),
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Read page duration limits: %1 s / %2 s"),
                                self.settings.min_sec, self.settings.max_sec)
                        end,
                        callback = function(touchmenu_instance)
                            local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
                            local durations_widget
                            durations_widget = DoubleSpinWidget:new{
                                left_text = _("Min"),
                                left_value = self.settings.min_sec,
                                left_default = DEFAULT_MIN_READ_SEC,
                                left_min = 3,
                                left_max = 120,
                                left_step = 1,
                                left_hold_step = 10,
                                right_text = _("Max"),
                                right_value = self.settings.max_sec,
                                right_default = DEFAULT_MAX_READ_SEC,
                                right_min = 10,
                                right_max = 7200,
                                right_step = 10,
                                right_hold_step = 60,
                                default_values = true,
                                default_text = _("Use defaults"),
                                title_text = _("Read page duration limits"),
                                info_text = _([[
Set min and max time spent (in seconds) on a page for it to be counted as read in statistics.
The min value ensures pages you quickly browse and skip are not included.
The max value ensures a page you stay on for a long time (because you fell asleep or went away) will be included, but with a duration capped to this specified max value.]]),
                                callback = function(min, max)
                                    if not min then min = DEFAULT_MIN_READ_SEC end
                                    if not max then max = DEFAULT_MAX_READ_SEC end
                                    if min > max then
                                        min, max = max, min
                                    end
                                    self.settings.min_sec = min
                                    self.settings.max_sec = max
                                    UIManager:close(durations_widget)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(durations_widget)
                        end,
                        keep_menu_open = true,
                        separator = true,
                    },
                    {
                        text_func = function()
                            return T(_("Calendar weeks start on %1"),
                                longDayOfWeekTranslation[weekDays[self.settings.calendar_start_day_of_week]])
                        end,
                        sub_item_table = {
                            { -- Friday (Bangladesh and Maldives)
                                text = longDayOfWeekTranslation[weekDays[6]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 6 end,
                                callback = function() self.settings.calendar_start_day_of_week = 6 end
                            },
                            { -- Saturday (some Middle East countries)
                                text = longDayOfWeekTranslation[weekDays[7]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 7 end,
                                callback = function() self.settings.calendar_start_day_of_week = 7 end
                            },
                            { -- Sunday
                                text = longDayOfWeekTranslation[weekDays[1]],
                                checked_func = function() return self.settings.calendar_start_day_of_week == 1 end,
                                callback = function() self.settings.calendar_start_day_of_week = 1 end
                            },
                            { -- Monday
                                text = longDayOfWeekTranslation[weekDays[2]],
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
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = self.settings.calendar_nb_book_spans,
                                value_min = 1,
                                value_max = 5,
                                ok_text = _("Set"),
                                title_text =  _("Books per calendar day"),
                                info_text = _("Set the max number of book spans to show for a day"),
                                callback = function(spin)
                                    self.settings.calendar_nb_book_spans = spin.value
                                    touchmenu_instance:updateItems()
                                end,
                                extra_text = _("Use default"),
                                extra_callback = function()
                                    self.settings.calendar_nb_book_spans = DEFAULT_CALENDAR_NB_BOOK_SPANS
                                    touchmenu_instance:updateItems()
                                end
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
                    },
                },
            },
            {
                text = _("Reset statistics"),
                sub_item_table = self:genResetBookSubItemTable(),
                separator = true,
            },
            {
                text = _("Current book"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(KeyValuePage:new{
                        title = _("Current statistics"),
                        kv_pairs = self:getCurrentStat(self.id_curr_book),
                    })
                end,
                enabled_func = function() return not self:isDocless() and self.settings.is_enabled end,
            },
            {
                text = _("Reading progress"),
                keep_menu_open = true,
                callback = function()
                    self:insertDB(self.id_curr_book)
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
                    self:statMenu()
                end
            },
            {
                text = _("Calendar view"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(self:getCalendarView())
                end,
            },
        },
    }
end

function ReaderStatistics:statMenu()
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
                        end
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
                        end
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
                        end
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
                        end
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
                        end
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
                        end
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
                        end
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
                        end
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

function ReaderStatistics:getCurrentStat(id_book)
    if id_book == nil then
        return
    end
    self:insertDB(id_book)
    local today_duration, today_pages = self:getTodayBookStats()
    local current_duration, current_pages = self:getCurrentBookStats()

    local conn = SQ3.open(db_location)
    local highlights, notes = conn:rowexec(string.format("SELECT highlights, notes FROM book WHERE id = %d;", id_book)) -- luacheck: no unused
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
    self.data.pages = self.view.document:getPageCount()
    total_time_book = tonumber(total_time_book)
    total_read_pages = tonumber(total_read_pages)
    local time_to_read = (self.data.pages - self.view.state.page) * self.avg_time
    local estimate_days_to_read = math.ceil(time_to_read/(book_read_time/tonumber(total_days)))
    local estimate_end_of_read_date = os.date("%Y-%m-%d", tonumber(now_ts + estimate_days_to_read * 86400))
    local estimates_valid = time_to_read > 0 -- above values could be 'nan' and 'nil'
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    return {
        -- Global statistics (may consider other books than current book)
        -- since last resume
        { _("Time spent reading this session"), util.secondsToClockDuration(user_duration_format, current_duration, false) },
        { _("Pages read this session"), tonumber(current_pages) },
        -- today
        { _("Time spent reading today"), util.secondsToClockDuration(user_duration_format, today_duration, false) },
        { _("Pages read today"), tonumber(today_pages), separator = true },
        -- Current book statistics
        -- Includes re-reads
        { _("Total time spent on this book"), util.secondsToClockDuration(user_duration_format, total_time_book, false) },
        -- Capped to self.settings.max_sec per distinct page
        { _("Time spent reading this book"), util.secondsToClockDuration(user_duration_format, book_read_time, false) },
        -- per days
        { _("Reading started"), os.date("%Y-%m-%d (%H:%M)", tonumber(first_open))},
        { _("Days reading this book"), tonumber(total_days) },
        { _("Average time per day"), util.secondsToClockDuration(user_duration_format, book_read_time/tonumber(total_days), false) },
        -- per page (% read)
        { _("Average time per page"), util.secondsToClockDuration(user_duration_format, self.avg_time, false) },
        { _("Pages read"), string.format("%d (%d%%)", total_read_pages, Math.round(100*total_read_pages/self.data.pages)) },
        -- current page (% completed)
        { _("Current page/Total pages"), string.format("%d/%d (%d%%)", self.curr_page, self.data.pages, Math.round(100*self.curr_page/self.data.pages)) },
        -- estimation, from current page to end of book
        { _("Estimated time to read"), estimates_valid and util.secondsToClockDuration(user_duration_format, time_to_read, false) or _("N/A") },
        { _("Estimated reading finished"), estimates_valid and
            T(N_("%1 (1 day)", "%1 (%2 days)", estimate_days_to_read), estimate_end_of_read_date, estimate_days_to_read)
            or _("N/A") },
        -- highlights
        { _("Highlights"), tonumber(highlights), separator = true },
        -- { _("Total notes"), tonumber(notes) }, -- not accurate, don't show it
        { _("Show days"), _("Tap to display"),
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
                    end
                }
                UIManager:show(self.kv)
            end,
        }
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
    notes = notes and tonumber(notes) or "?" -- luacheck: no unused

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

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    if first_open == nil then
        first_open = os.time()
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
    local avg_time_per_page = book_read_time / book_read_pages
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    return {
        { _("Title"), title},
        { _("Authors"), authors},
        { _("Reading started"), os.date("%Y-%m-%d (%H:%M)", tonumber(first_open))},
        { _("Last read"), os.date("%Y-%m-%d (%H:%M)", tonumber(last_open))},
        { _("Days reading this book"), tonumber(total_days) },
        { _("Total time spent on this book"), util.secondsToClockDuration(user_duration_format, total_time_book, false) },
        { _("Time spent reading this book"), util.secondsToClockDuration(user_duration_format, book_read_time, false) },
        { _("Average time per day"), util.secondsToClockDuration(user_duration_format, book_read_time/tonumber(total_days), false) },
        { _("Average time per page"), util.secondsToClockDuration(user_duration_format, avg_time_per_page, false) },
        { _("Pages read"), string.format("%d (%d%%)", total_read_pages, Math.round(100*total_read_pages/pages)) },
        { _("Last read page/Total pages"), string.format("%d/%d (%d%%)", last_page, pages, Math.round(100*last_page/pages)) },
        { _("Highlights"), highlights, separator = true },
        -- { _("Total notes"), notes }, -- not accurate, don't show it
        { _("Show days"), _("Tap to display"),
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
                    end
                }
                UIManager:show(self.kv)
            end,
        }
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
            end
        }
    else
        self.kv = KeyValuePage:new{
            title = date_text,
            value_align = "right",
            kv_pairs = self:getDaysFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end
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
            end
        }
    else
        self.kv = KeyValuePage:new{
            title = date_text,
            value_align = "right",
            kv_pairs = self:getDaysFromPeriod(begin, finish),
            callback_return = function()
                UIManager:show(kv)
                self.kv = kv
            end
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
        end
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
    self:insertDB(self.id_curr_book)
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
                shortDayOfWeekTranslation[os.date("%a", timestamp)])
        elseif ptype == "daily" then
            date_text = result_book[1][i]
        elseif ptype == "weekly" then
            date_text = T(_("%1 Week %2"), os.date("%Y", timestamp), os.date(" %W", timestamp))
        elseif ptype == "monthly" then
            date_text = monthTranslation[os.date("%B", timestamp)] .. os.date(" %Y", timestamp)
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false)),
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false)),
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false)),
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
            T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false)),
            callback = function()
                local kv = self.kv
                UIManager:close(kv)
                self.kv = KeyValuePage:new{
                    title = T(_("Books read %1"), result_book[1][i]),
                    value_overflow_align = "right",
                    kv_pairs = self:getBooksFromPeriod(time_begin, time_begin + 86400),
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end
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
                sum(page_stat_tbl.duration),
                count(distinct page_stat_tbl.page),
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
            T(_("%1 (%2)"), util.secondsToClockDuration(user_duration_format, tonumber(result_book[2][i]), false), tonumber(result_book[3][i])),
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
                        end
                    }
                else
                    self.kv = KeyValuePage:new{
                        title = result_book[1][i],
                        kv_pairs = self:getBookStat(tonumber(result_book[4][i])),
                        value_overflow_align = "right",
                        callback_return = function()
                            UIManager:show(kv)
                            self.kv = kv
                        end
                    }
                end
                UIManager:show(self.kv)
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
               sum(duration)                              AS durations
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
            T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClockDuration(user_duration_format, tonumber(result_book[3][i]), false))
        })
    end
    return results
end

function ReaderStatistics:getTotalStats()
    self:insertDB(self.id_curr_book)
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
            util.secondsToClockDuration(user_duration_format, total_time_book, false),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)

                self.kv = KeyValuePage:new{
                    title = book_title,
                    kv_pairs = self:getBookStat(id_book),
                    value_overflow_align = "right",
                    callback_return = function()
                        UIManager:show(kv)
                        self.kv = kv
                    end
                }
                UIManager:show(self.kv)
            end,
        })
    end
    conn:close()

    return T(_("Total time spent reading: %1"), util.secondsToClockDuration(user_duration_format, total_books_time, false)), total_stats
end

function ReaderStatistics:genResetBookSubItemTable()
    local sub_item_table = {}
    table.insert(sub_item_table, {
        text = _("Reset statistics for the current book"),
        keep_menu_open = true,
        callback = function()
            self:resetCurrentBook()
        end,
        enabled_func = function() return not self:isDocless() and self.settings.is_enabled and self.id_curr_book end,
        separator = true,
    })
    table.insert(sub_item_table, {
        text = _("Reset statistics per book"),
        keep_menu_open = true,
        callback = function()
            self:resetBook()
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

function ReaderStatistics:resetBook()
    local total_stats = {}

    self:insertDB(self.id_curr_book)
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
                util.secondsToClockDuration(user_duration_format, total_time_book, false),
                id_book,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Do you want to reset statistics for book:\n%1"), book_title),
                        cancel_text = _("Cancel"),
                        cancel_callback = function()
                            return
                        end,
                        ok_text = _("Reset"),
                        ok_callback = function()
                            for j=1, #total_stats do
                                if total_stats[j][3] == id_book then
                                    self:deleteBook(id_book)
                                    table.remove(total_stats, j)
                                    break
                                end
                            end
                            -- refresh window after delete item
                            kv_reset_book:_populateItems()
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
    self:insertDB(self.id_curr_book)

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

function ReaderStatistics:onPageUpdate(pageno)
    if self:isDocless() or not self.settings.is_enabled then
        return
    end

    -- We only care about *actual* page turns ;)
    if self.curr_page == pageno then
        return
    end

    self.pageturn_count = self.pageturn_count + 1
    local now_ts = os.time()

    -- Get the previous page's last timestamp (if there is one)
    local page_data = self.page_stat[self.curr_page]
    -- This is a list of tuples, in insertion order, we want the last one
    local data_tuple = page_data and page_data[#page_data]
    -- Tuple layout is { timestamp, duration }
    local then_ts = data_tuple and data_tuple[1]
    -- If we don't have a previous timestamp to compare to, abort early
    if not then_ts then
        logger.dbg("ReaderStatistics: No timestamp for previous page", self.curr_page)
        self.page_stat[pageno] = { { now_ts, 0 } }
        self.curr_page = pageno
        return
    end

    -- By now, we're sure that we actually have a tuple (and the rest of the code ensures they're sane, i.e., zero-initialized)
    local curr_duration = data_tuple[2]
    -- NOTE: If all goes well, given the earlier curr_page != pageno check, curr_duration should always be 0 here.
    -- Compute the difference between now and the previous page's last timestamp
    local diff_time = now_ts - then_ts
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

    -- We want a flush to db every 50 page turns
    if self.pageturn_count >= MAX_PAGETURNS_BEFORE_FLUSH then
        -- I/O, delay until after the pageturn, but reset the count now, to avoid potentially scheduling multiple inserts...
        self.pageturn_count = 0
        UIManager:tickAfterNext(function()
            self:insertDB(self.id_curr_book)
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

    -- We're done, update the current page tracker
    self.curr_page = pageno
    -- And, in the new page's list, append a new tuple with the current timestamp and a placeholder duration
    -- (duration will be computed on next pageturn)
    local new_page_data = self.page_stat[pageno]
    if new_page_data then
        table.insert(new_page_data, { now_ts, 0 })
    else
        self.page_stat[pageno] = { { now_ts, 0 } }
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
    if not self:isDocless() and self.settings.is_enabled then
        self.ui.doc_settings:saveSetting("stats", self.data)
        self:insertDB(self.id_curr_book)
    end
end

function ReaderStatistics:onAddHighlight()
    if self.settings.is_enabled then
        self.data.highlights = self.data.highlights + 1
    end
end

function ReaderStatistics:onDelHighlight()
    if self.settings.is_enabled then
        if self.data.highlights > 0 then
            self.data.highlights = self.data.highlights - 1
        end
    end
end

function ReaderStatistics:onAddNote()
    if self.settings.is_enabled then
        self.data.notes = self.data.notes + 1
    end
end

-- Triggered by auto_save_settings_interval_minutes
function ReaderStatistics:onSaveSettings()
    if not self:isDocless() then
        self.ui.doc_settings:saveSetting("stats", self.data)
        self:insertDB(self.id_curr_book)
    end
end

-- in case when screensaver starts
function ReaderStatistics:onSuspend()
    if not self:isDocless() then
        self.ui.doc_settings:saveSetting("stats", self.data)
        self:insertDB(self.id_curr_book)
    end
end

-- screensaver off
function ReaderStatistics:onResume()
    self.start_current_period = os.time()
    self:resetVolatileStats(self.start_current_period)
end

function ReaderStatistics:onReadSettings(config)
    self.data = config.data.stats or {}
end

function ReaderStatistics:onReaderReady()
    -- we have correct page count now, do the actual initialization work
    self:initData()
    self.view.footer:onUpdateFooter()
end

function ReaderStatistics:getCalendarView()
    self:insertDB(self.id_curr_book)
    local CalendarView = require("calendarview")
    return CalendarView:new{
        reader_statistics = self,
        monthTranslation = monthTranslation,
        shortDayOfWeekTranslation = shortDayOfWeekTranslation,
        longDayOfWeekTranslation = longDayOfWeekTranslation,
        start_day_of_week = self.settings.calendar_start_day_of_week,
        nb_book_spans = self.settings.calendar_nb_book_spans,
        show_hourly_histogram = self.settings.calendar_show_histogram,
        browse_future_months = self.settings.calendar_browse_future_months,
    }
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
    -- Comverting the month into timestamp boundaries, and just comparing
    -- integers, can be 5 times faster.
    -- We let SQLite compute these timestamp boundaries from the provided
    -- month; we need the start of the month to be a real date:
    month = month.."-01"
    local sql_stmt = [[
        SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            strftime('%H', start_time, 'unixepoch', 'localtime') hour,
            sum(duration)/3600.0 ratio
        FROM   page_stat
        WHERE  start_time BETWEEN strftime('%s', ?, 'utc')
                              AND strftime('%s', ?, 'utc', '+33 days', 'start of month', '-1 second')
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            strftime('%H', start_time, 'unixepoch', 'localtime')
        ORDER BY day, hour;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(month, month):resultset("i")
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
    local sql_stmt = [[
        SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            sum(duration) durations,
            id_book book_id,
            book.title book_title
        FROM   page_stat
        JOIN   book ON book.id = page_stat.id_book
        WHERE  start_time BETWEEN strftime('%s', ?, 'utc')
                              AND strftime('%s', ?, 'utc', '+33 days', 'start of month', '-1 second')
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            id_book,
            title
        ORDER BY day, durations desc, book_id, book_title;
    ]]
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql_stmt)
    local res, nb = stmt:reset():bind(month, month):resultset("i")
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

function ReaderStatistics:onShowReaderProgress()
    self:insertDB(self.id_curr_book)
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
    if self:isDocless() or not self.settings.is_enabled then return end
    local stats = KeyValuePage:new{
        title = _("Current statistics"),
        kv_pairs = self:getCurrentStat(self.id_curr_book),
    }
    UIManager:show(stats)
end

function ReaderStatistics:onShowCalendarView()
     UIManager:show(self:getCalendarView())
end

return ReaderStatistics
