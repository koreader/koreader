local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local ReaderProgress = require("readerprogress")
local ReadHistory = require("readhistory")
local Screensaver = require("ui/screensaver")
local SQ3 = require("lua-ljsqlite3/init")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local joinPath = require("ffi/util").joinPath
local Screen = require("device").screen
local T = require("ffi/util").template

local statistics_dir = DataStorage:getDataDir() .. "/statistics/"
local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local PAGE_INSERT = 50
local DEFAULT_MIN_READ_SEC = 5
local DEFAULT_MAX_READ_SEC = 120

local ReaderStatistics = Widget:extend{
    page_min_read_sec = DEFAULT_MIN_READ_SEC,
    page_max_read_sec = DEFAULT_MAX_READ_SEC,
    start_current_period = 0,
    curr_page = 0,
    id_curr_book = nil,
    curr_total_time = 0,
    curr_total_pages = 0,
    is_enabled = nil,
    convert_to_db = nil,
    total_read_pages = 0,
    total_read_time = 0,
    avg_time = nil,
    pages_stats = {},
    data = {
        title = "",
        authors = "",
        language = "",
        series = "",
        performance_in_pages = {},
        total_time_in_sec = 0,
        highlights = 0,
        notes = 0,
        pages = 0,
        md5 = nil,
    },
}

local shortDayOfWeekTranslation = {
    ["Mon"] = _("Mon"),
    ["Tue"] = _("Tue"),
    ["Wed"] = _("Wed"),
    ["Thu"] = _("Thu"),
    ["Fri"] = _("Fri"),
    ["Sat"] = _("Sat"),
    ["Sun"] = _("Sun"),
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
    return self.ui == nil or self.ui.document == nil
end

function ReaderStatistics:init()
    if not self:isDocless() and self.ui.document.is_pic then
        return
    end
    self.start_current_period = TimeVal:now().sec
    self.pages_stats = {}
    local settings = G_reader_settings:readSetting("statistics") or {}
    self.page_min_read_sec = tonumber(settings.min_sec)
    self.page_max_read_sec = tonumber(settings.max_sec)
    self.is_enabled = not (settings.is_enabled == false)
    self.convert_to_db = settings.convert_to_db
    self.ui.menu:registerToMainMenu(self)
    self:checkInitDatabase()
    BookStatusWidget.getStats = function()
        return self:getStatsBookStatus(self.id_curr_book, self.is_enabled)
    end
    ReaderFooter.getAvgTimePerPage = function()
        if self.is_enabled then
            return self.avg_time
        end
    end
    Screensaver.getReaderProgress = function()
        local readingprogress
        self:insertDB(self.id_curr_book)
        local current_period, current_pages = self:getCurrentBookStats()
        local today_period, today_pages = self:getTodayBookStats()
        local dates_stats = self:getReadingProgressStats(7)
        if dates_stats then
            readingprogress = ReaderProgress:new{
                dates = dates_stats,
                current_period = current_period,
                current_pages = current_pages,
                today_period = today_period,
                today_pages = today_pages,
                readonly = true,
            }
        end
        return readingprogress
    end
end

function ReaderStatistics:initData()
    if self:isDocless() or not self.is_enabled then
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
    self.data.language = book_properties.language
    self.data.series = book_properties.series

    self.data.pages = self.view.document:getPageCount()
    self.data.md5 = self:partialMd5(self.document.file)
    self.curr_total_time = 0
    self.curr_total_pages = 0
    self.id_curr_book = self:getIdBookDB()
    self.total_read_pages, self.total_read_time = self:getPageTimeTotalStats(self.id_curr_book)
    if self.total_read_pages > 0 then
        self.avg_time = math.ceil(self.total_read_time / self.total_read_pages)
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
                    WHERE  id_book = '%s'
                    GROUP  BY dates
               )
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_curr_book))
    sql_stmt = [[
        SELECT sum(period),
               count(DISTINCT page)
        FROM   page_stat
        WHERE  id_book = '%s'
    ]]
    local total_time_book, total_read_pages = conn:rowexec(string.format(sql_stmt, id_curr_book))
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
    if self.convert_to_db then      -- if conversion to sqlite was doing earlier
        if not conn:exec("pragma table_info('book');") then
            UIManager:show(ConfirmBox:new{
                text = T(_([[
Cannot open database in %1.
The database may have been moved or deleted.
Do you want to create an empty database?
]]),
                        db_location),
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
    else  -- first time convertion to sqlite database
        self.convert_to_db = true
        if not conn:exec("pragma table_info('book');") then
            if #ReadHistory.hist > 0 then
                local info = InfoMessage:new{
                    text =_([[
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
                    text =T(_("Conversion completed.\nImported %1 books to database.\nTap to continue."),nr_book) })
            else
                self:createDB(conn)
            end
        end
        self:saveSettings()
    end
    conn:close()
end

function ReaderStatistics:partialMd5(file)
    if file == nil then
        return nil
    end
    local md5 = require("ffi/MD5")
    local lshift = bit.lshift
    local step, size = 1024, 1024
    local m = md5.new()
    local file_handle = io.open(file, 'rb')
    for i = -1, 10 do
        file_handle:seek("set", lshift(step, 2*i))
        local sample = file_handle:read(size)
        if sample then
            m:update(sample)
        else
            break
        end
    end
    return m:sum()
end

function ReaderStatistics:createDB(conn)
    local sql_stmt = [[
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
        CREATE TABLE IF NOT EXISTS page_stat
            (
                id_book    integer,
                page       integer NOT NULL,
                start_time integer NOT NULL,
                period     integer NOT NULL,
                UNIQUE (page, start_time),
                FOREIGN KEY(id_book) REFERENCES book(id)
             );
        CREATE TABLE IF NOT EXISTS info
             (
                 version integer
             );
        CREATE INDEX IF NOT EXISTS page_stat_id_book ON page_stat(id_book);
        CREATE INDEX IF NOT EXISTS book_title_authors_md5 ON book(title, authors, md5);
    ]]
    conn:exec(sql_stmt)
    --DB structure version - now is version 1
    local stmt = conn:prepare("INSERT INTO info values (?)")
    stmt:reset():bind("1"):step()
    stmt:close()
end

function ReaderStatistics:addBookStatToDB(book_stats, conn)
    local id_book
    local last_open_book = 0
    local start_open_page
    local diff_time
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
                AND    md5 = ?
        ]]
        local stmt = conn:prepare(sql_stmt)
        local result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
        local nr_id = tonumber(result[1])
        if nr_id == 0 then
            stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
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
                    AND md5 = ?
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

        conn:exec('BEGIN')
        stmt = conn:prepare("INSERT OR IGNORE INTO page_stat VALUES(?, ?, ?, ?)")
        local avg_time = math.ceil(book_stats.total_time_in_sec / read_pages)
        if avg_time > self.page_max_read_sec then
            avg_time = self.page_max_read_sec
        end
        local first_read_page = book_stats.performance_in_pages[sorted_performance[1]]
        if first_read_page > 1 then
            first_read_page = first_read_page - 1
        end
        start_open_page = sorted_performance[1]
        --first page
        stmt:reset():bind(id_book, first_read_page, start_open_page - avg_time, avg_time):step()
        for i=2, #sorted_performance do
            start_open_page = sorted_performance[i-1]
            diff_time = sorted_performance[i] - sorted_performance[i-1]
            if diff_time <= self.page_max_read_sec then
                stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[i-1]],
                    start_open_page, diff_time):step()
            elseif diff_time > self.page_max_read_sec then --and diff_time <= 2 * avg_time then
                stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[i-1]],
                    start_open_page, avg_time):step()
            end
        end
        --last page
        stmt:reset():bind(id_book, book_stats.performance_in_pages[sorted_performance[#sorted_performance]],
            sorted_performance[#sorted_performance], avg_time):step()
        --last open book
        last_open_book = sorted_performance[#sorted_performance] + avg_time
        conn:exec('COMMIT')
        sql_stmt = [[
            SELECT count(DISTINCT page),
                   sum(period)
            FROM   page_stat
            WHERE  id_book = %s;
        ]]
        total_read_pages, total_read_time = conn:rowexec(string.format(sql_stmt, tonumber(id_book)))
        sql_stmt = [[
            UPDATE book
            SET    last_open = ?,
                   total_read_time = ?,
                   total_read_pages = ?
            WHERE  id = ?
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
        local book_stats = DocSettings:open(v.file):readSetting('stats')
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
            AND md5 = ?
    ]]
    local stmt = conn:prepare(sql_stmt)
    local result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
    local nr_id = tonumber(result[1])
    if nr_id == 0 then
        stmt = conn:prepare("INSERT INTO book VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        stmt:reset():bind(self.data.title, self.data.authors, self.data.notes,
            TimeVal:now().sec, self.data.highlights, self.data.pages,
            self.data.series, self.data.language, self.data.md5, self.curr_total_time, self.curr_total_pages):step()
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
                AND    md5 = ?
        ]]
        stmt = conn:prepare(sql_stmt)
        result = stmt:reset():bind(self.data.title, self.data.authors, self.data.md5):step()
        id_book = result[1]
    end
    conn:close()
    return tonumber(id_book)
end

function ReaderStatistics:insertDB(id_book)
    self.pages_stats[TimeVal:now().sec] = self.curr_page
    if id_book == nil or util.tableSize(self.pages_stats) < 2 then
        return
    end
    local diff_time
    local conn = SQ3.open(db_location)
    local sorted_performance = {}
    for time, pages in pairs(self.pages_stats) do
        table.insert(sorted_performance, time)
    end
    table.sort(sorted_performance)
    conn:exec('BEGIN')
    local stmt = conn:prepare("INSERT OR IGNORE INTO page_stat VALUES(?, ?, ?, ?)")
    for i=1, #sorted_performance - 1 do
        diff_time = sorted_performance[i+1] - sorted_performance[i]
        if diff_time >= self.page_min_read_sec then
            stmt:reset():bind(id_book,
                self.pages_stats[sorted_performance[i]],
                sorted_performance[i],
                math.min(diff_time, self.page_max_read_sec)):step()
        end
    end
    conn:exec('COMMIT')
    local sql_stmt = [[
        SELECT count(DISTINCT page),
               sum(period)
        FROM   page_stat
        WHERE  id_book = '%s'
    ]]
    local total_read_pages, total_read_time = conn:rowexec(string.format(sql_stmt, id_book))
    sql_stmt = [[
        UPDATE book
        SET    last_open = ?,
               notes = ?,
               highlights = ?,
               total_read_time = ?,
               total_read_pages = ?,
               pages = ?
        WHERE  id = ?
    ]]
    stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(TimeVal:now().sec, self.data.notes, self.data.highlights, total_read_time, total_read_pages,
        self.data.pages, id_book):step()
    if total_read_pages then
        self.total_read_pages = tonumber(total_read_pages)
    else
        self.total_read_pages = 0
    end
    if total_read_time then
        self.total_read_time = tonumber(total_read_time)
    else
        self.total_read_time = 0
    end
    self.pages_stats = {}
    -- last page must be added once more
    self.pages_stats[TimeVal:now().sec] = self.curr_page
    conn:close()
end

function ReaderStatistics:getPageTimeTotalStats(id_book)
    if id_book == nil then
        return
    end
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT total_read_pages,
               total_read_time
        FROM   book
        WHERE  id = '%s'
    ]]
    local total_pages, total_time = conn:rowexec(string.format(sql_stmt, id_book))
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
    conn:close()
    return total_pages, total_time
end

function ReaderStatistics:getBookProperties()
    local props = self.view.document:getProps()
    if props.title == "No document" or props.title == "" then
        -- FIXME: sometimes crengine returns "No document", try one more time
        props = self.view.document:getProps()
    end
    return props
end

function ReaderStatistics:getStatisticEnabledMenuItem()
    return {
        text = _("Enabled"),
        checked_func = function() return self.is_enabled end,
        callback = function()
            -- if was enabled, have to save data to file
            if self.is_enabled and not self:isDocless() then
                self:insertDB(self.id_curr_book)
                self.ui.doc_settings:saveSetting("stats", self.data)
            end

            self.is_enabled = not self.is_enabled
            -- if was disabled have to get data from db
            if self.is_enabled and not self:isDocless() then
                self:initData()
                self.pages_stats = {}
                self.start_current_period = TimeVal:now().sec
                if self.document.info.has_pages then
                    self.curr_page = self.ui.paging.current_page
                else
                    self.curr_page = self.document:getCurrentPage()
                end
                self.pages_stats[self.start_current_period] = self.curr_page
            end
            self:saveSettings()
            if not self:isDocless() then
                self.view.footer:updateFooter()
            end
        end,
    }
end

function ReaderStatistics:updateSettings()
    self.settings_dialog = MultiInputDialog:new {
        title = _("Statistics settings"),
        fields = {
            {
                text = self.page_min_read_sec,
                description = T(_("Min seconds, default is %1"), DEFAULT_MIN_READ_SEC),
                input_type = "number",
            },
            {
                text = self.page_max_read_sec,
                description = T(_("Max seconds, default is %1"), DEFAULT_MAX_READ_SEC),
                input_type = "number",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings(MultiInputDialog:getFields())
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
        input_type = "number",
    }
    self.settings_dialog:onShowKeyboard()
    UIManager:show(self.settings_dialog)
end

function ReaderStatistics:addToMainMenu(menu_items)
    menu_items.statistics = {
        text = _("Reading statistics"),
        sub_item_table = {
            self:getStatisticEnabledMenuItem(),
            {
                text = _("Settings"),
                callback = function() self:updateSettings() end,
            },
            {
                text = _("Reset book statistics"),
                callback = function()
                    self:resetBook()
                end
            },
            {
                text = _("Current book"),
                callback = function()
                    UIManager:show(KeyValuePage:new{
                        title = _("Statistics"),
                        kv_pairs = self:getCurrentStat(self.id_curr_book),
                    })
                end,
                enabled_func = function() return not self:isDocless() and self.is_enabled end,
            },
            {
                text = _("Reading progress"),
                callback = function()
                    self:insertDB(self.id_curr_book)
                    local current_period, current_pages = self:getCurrentBookStats()
                    local today_period, today_pages = self:getTodayBookStats()
                    local dates_stats = self:getReadingProgressStats(7)
                    if dates_stats then
                        UIManager:show(ReaderProgress:new{
                            dates = dates_stats,
                            current_period = current_period,
                            current_pages = current_pages,
                            today_period = today_period,
                            today_pages = today_pages,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text =T(_("Reading progress unavailable.\nNo data from last %1 days."),7)})
                    end
                end
            },
            {
                text = _("Time range"),
                callback = function()
                    self:statMenu()
                end
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
            "----",
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
            "----",
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
            }
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
               sum(sum_period)
        FROM    (
                     SELECT sum(period)      AS sum_period
                     FROM   page_stat
                     WHERE  start_time >= '%s'
                     GROUP  BY id_book, page
	            )
    ]]
    local today_pages, today_period = conn:rowexec(string.format(sql_stmt, start_today_time))
    if today_pages == nil then
        today_pages = 0
    end
    if today_period == nil then
        today_period = 0
    end
    today_period = tonumber(today_period)
    today_pages = tonumber(today_pages)
    conn:close()
    return today_period, today_pages
end

function ReaderStatistics:getCurrentBookStats()
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT count(*),
               sum(sum_period)
        FROM   (
                    SELECT sum(period)      AS sum_period
                    FROM   page_stat
                    WHERE  start_time >= '%s'
                    GROUP  BY id_book, page
               )
    ]]
    local current_pages, current_period = conn:rowexec(string.format(sql_stmt, self.start_current_period))
    if current_pages == nil then
        current_pages = 0
    end
    if current_period == nil then
        current_period = 0
    end
    current_period = tonumber(current_period)
    current_pages = tonumber(current_pages)
    return current_period, current_pages
end

function ReaderStatistics:getCurrentStat(id_book)
    if id_book == nil then
        return
    end
    self:insertDB(id_book)
    local today_period, today_pages = self:getTodayBookStats()
    local current_period, current_pages = self:getCurrentBookStats()

    local conn = SQ3.open(db_location)
    local notes, highlights = conn:rowexec(string.format("SELECT notes, highlights  FROM book WHERE id = '%s';)", id_book))
    local sql_stmt = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = '%s'
                    GROUP  BY dates
               )
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_book))
    sql_stmt = [[
        SELECT sum(period),
               count(DISTINCT page)
        FROM   page_stat
        WHERE  id_book = '%s'
    ]]
    local total_time_book, total_read_pages = conn:rowexec(string.format(sql_stmt, id_book))
    conn:close()

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    self.data.pages = self.view.document:getPageCount()
    total_time_book = tonumber(total_time_book)
    total_read_pages = tonumber(total_read_pages)
    local avg_time_per_page = total_time_book / total_read_pages
    return {
        { _("Current period"), util.secondsToClock(current_period, false) },
        { _("Current pages"), tonumber(current_pages) },
        { _("Today period"), util.secondsToClock(today_period, false) },
        { _("Today pages"), tonumber(today_pages) },
        { _("Time to read"), util.secondsToClock((self.data.pages - self.view.state.page) * avg_time_per_page, false) },
        { _("Total time"), util.secondsToClock(total_time_book, false) },
        { _("Total highlights"), tonumber(highlights) },
        { _("Total notes"), tonumber(notes) },
        { _("Total days"), tonumber(total_days) },
        { _("Average time per page"), util.secondsToClock(avg_time_per_page, false) },
        { _("Read pages/Total pages"), total_read_pages .. "/" .. self.data.pages },
        -- adding 0.5 rounds to nearest integer with math.floor
        { _("Percentage completed"), math.floor(total_read_pages / self.data.pages * 100 + 0.5) .. "%" },
    }
end

function ReaderStatistics:getBookStat(id_book)
    if id_book == nil then
        return
    end
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT title, authors, notes, highlights, pages, last_open
        FROM book
        WHERE id = '%s'
    ]]
    local title, authors, notes, highlights, pages, last_open = conn:rowexec(string.format(sql_stmt, id_book))

    sql_stmt = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = '%s'
                    GROUP  BY dates
               )
    ]]
    local total_days = conn:rowexec(string.format(sql_stmt, id_book))

    sql_stmt = [[
        SELECT sum(period),
               count(DISTINCT page)
        FROM   page_stat
        WHERE  id_book = '%s'
    ]]
    local total_time_book, total_read_pages = conn:rowexec(string.format(sql_stmt, id_book))

    sql_stmt = [[
        SELECT min(start_time)
        FROM   page_stat
        WHERE  id_book = '%s'
    ]]
    local first_open = conn:rowexec(string.format(sql_stmt, id_book))
    conn:close()

    if total_time_book == nil then
        total_time_book = 0
    end
    if total_read_pages == nil then
        total_read_pages = 0
    end
    total_time_book = tonumber(total_time_book)
    total_read_pages = tonumber(total_read_pages)
    pages = tonumber(pages)
    if pages == nil or pages == 0 then
        pages = 1
    end
    local avg_time_per_page = total_time_book / total_read_pages
    return {
        { _("Title"), title},
        { _("Authors"), authors},
        { _("First opened"), os.date("%Y-%m-%d (%H:%M)", tonumber(first_open))},
        { _("Last opened"), os.date("%Y-%m-%d (%H:%M)", tonumber(last_open))},
        { _("Total time"), util.secondsToClock(total_time_book, false) },
        { _("Total highlights"), tonumber(highlights) },
        { _("Total notes"), tonumber(notes) },
        { _("Total days"), tonumber(total_days) },
        { _("Average time per page"), util.secondsToClock(avg_time_per_page, false) },
        { _("Read pages/Total pages"), total_read_pages .. "/" .. pages },
        -- adding 0.5 rounds to nearest integer with math.floor
        { _("Percentage completed"), math.floor(total_read_pages / pages * 100 + 0.5) .. "%" },
        "----",
        { _("Show days"), _("Tap to display"),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)
                self.kv = KeyValuePage:new{
                    title = _("Read in days"),
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
                   sum(sum_period)      AS periods,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                               sum(period)                                                   AS sum_period,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= '%s'
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC
    ]]
end

local function sqlWeekly()
    return
    [[
            SELECT dates,
                   count(*)             AS pages,
                   sum(sum_period)      AS periods,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%W', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(period)                                                   AS sum_period,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= '%s'
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC
    ]]
end

local function sqlMonthly()
    return
    [[
            SELECT dates,
                   count(*)             AS pages,
                   sum(sum_period)      AS periods,
                   start_time
            FROM   (
                        SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(period)                                                   AS sum_period,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= '%s'
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC
    ]]
end

function ReaderStatistics:callbackMonthly(begin, finish, date_text, book_mode)
    local kv = self.kv
    UIManager:close(kv)
    if book_mode then
        self.kv = KeyValuePage:new{
            title = T(_("Books from: %1"), date_text),
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
            title = T(_("Books from: %1"), date_text),
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
    local year_begin, year_end, month_begin, month_end
    local timestamp
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour *3600 + now_t.min*60 + now_t.sec
    local now_stamp = os.time()
    local one_day = 86400 -- one day in seconds
    local sql_stmt_res_book
    local period_begin = 0
    if sdays > 0 then
        period_begin = now_stamp - ((sdays-1) * one_day) - from_begin_day
    end
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
        local date_text
        timestamp = tonumber(result_book[4][i])
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
            year_begin = tonumber(os.date("%Y", timestamp))
            month_begin = tonumber(os.date("%m", timestamp))
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClock(tonumber(result_book[3][i]), false)),
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClock(tonumber(result_book[3][i]), false)),
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
                T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClock(tonumber(result_book[3][i]), false)),
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
               sum(sum_period)      AS periods,
               start_time
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                           sum(period)                                                   AS sum_period,
                           start_time
                    FROM   page_stat
                    WHERE  start_time >= '%s' AND start_time < '%s'
                    GROUP  BY id_book, page, dates
               )
        GROUP  BY dates
        ORDER  BY dates DESC
    ]]
    local conn = SQ3.open(db_location)
    local result_book = conn:exec(string.format(sql_stmt_res_book, period_begin, period_end))
    conn:close()
    if result_book == nil then
        return {}
    end
    for i=1, #result_book.dates do
        local time_begin = os.time{year=string.sub(result_book[1][i],1,4), month=string.sub(result_book[1][i],6,7),
            day=string.sub(result_book[1][i],9,10), hour=0, min=0, sec=0 }
        table.insert(results, {
            result_book[1][i],
            T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClock(tonumber(result_book[3][i]), false)),
            callback = function()
                local kv = self.kv
                UIManager:close(kv)
                self.kv = KeyValuePage:new{
                    title = T(_("Books in %1"), result_book[1][i]),
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

function ReaderStatistics:getBooksFromPeriod(period_begin, period_end)
    local results = {}
    local sql_stmt_res_book = [[
        SELECT  book_tbl.title AS title,
                sum(page_stat_tbl.period),
                count(distinct page_stat_tbl.page),
                book_tbl.id
        FROM    page_stat AS page_stat_tbl, book AS book_tbl
        WHERE   page_stat_tbl.id_book=book_tbl.id AND page_stat_tbl.start_time > '%s' AND page_stat_tbl.start_time <= '%s'
        GROUP   BY book_tbl.id
        ORDER   BY book_tbl.last_open DESC
    ]]
    local conn = SQ3.open(db_location)
    local result_book = conn:exec(string.format(sql_stmt_res_book, period_begin, period_end))
    conn:close()
    if result_book == nil then
        return {}
    end
    for i=1, #result_book.title do
        table.insert(results, {
            result_book[1][i],
            T(_("%1 (%2)"), util.secondsToClock(tonumber(result_book[2][i]), false), tonumber(result_book[3][i])),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)
                self.kv = KeyValuePage:new{
                    title = _("Read in days"),
                    value_overflow_align = "right",
                    kv_pairs = self:getDatesForBook(tonumber(result_book[4][i])),
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

function ReaderStatistics:getReadingProgressStats(sdays)
    local results = {}
    local pages, period, date_read
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour *3600 + now_t.min*60 + now_t.sec
    local now_stamp = os.time()
    local one_day = 86400 -- one day in seconds
    local period_begin = now_stamp - ((sdays-1) * one_day) - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT dates,
               count(*)             AS pages,
               sum(sum_period)      AS periods,
               start_time
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                           sum(period)                                                   AS sum_period,
                           start_time
                    FROM   page_stat
                    WHERE  start_time >= '%s'
                    GROUP  BY id_book, page, dates
               )
        GROUP  BY dates
        ORDER  BY dates DESC
    ]]
    local result_book = conn:exec(string.format(sql_stmt, period_begin))
    if not result_book then return end
    for i = 1, sdays do
        pages = tonumber(result_book[2][i])
        period = tonumber(result_book[3][i])
        date_read = result_book[1][i]
        if pages == nil then pages = 0 end
        if period == nil then period = 0 end
        table.insert(results, {
            pages,
            period,
            date_read
        })
    end
    conn:close()
    return results
end

function ReaderStatistics:getDatesForBook(id_book)
    local results = {}
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT date(start_time, 'unixepoch', 'localtime') AS dates,
               count(DISTINCT page)                       AS pages,
               sum(period)                                AS periods
        FROM   page_stat
        WHERE  id_book = '%s'
        GROUP  BY Date(start_time, 'unixepoch', 'localtime')
        ORDER  BY dates DESC
    ]]
    local result_book = conn:exec(string.format(sql_stmt, id_book))
    conn:close()
    if result_book == nil then
        return {}
    end
    for i=1, #result_book.dates do
        table.insert(results, {
            result_book[1][i],
            T(_("Pages: (%1) Time: %2"), tonumber(result_book[2][i]), util.secondsToClock(tonumber(result_book[3][i]), false))
        })
    end
    return results
end

function ReaderStatistics:getTotalStats()
    self:insertDB(self.id_curr_book)
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(period)
        FROM   page_stat
    ]]
    local total_books_time = conn:rowexec(sql_stmt)
    if total_books_time == nil then
        total_books_time = 0
    end
    local total_stats = {}
    sql_stmt = [[
        SELECT id
        FROM   book
        ORDER  BY last_open DESC
    ]]
    local id_book_tbl = conn:exec(sql_stmt)
    local nr_books
    if id_book_tbl ~= nil then
        nr_books = #id_book_tbl.id
    else
        nr_books = 0
    end

    local total_time_book
    for i=1, nr_books do
        local id_book = tonumber(id_book_tbl[1][i])
        sql_stmt = [[
            SELECT title
            FROM   book
            WHERE  id = '%s'
        ]]
        local book_title = conn:rowexec(string.format(sql_stmt, id_book))
        sql_stmt = [[
            SELECT sum(period)
            FROM   page_stat
            WHERE  id_book = '%s'
        ]]
        total_time_book = conn:rowexec(string.format(sql_stmt,id_book))
        if total_time_book == nil then
            total_time_book = 0
        end
        table.insert(total_stats, {
            book_title,
            util.secondsToClock(total_time_book, false),
            callback = function()
                local kv = self.kv
                UIManager:close(self.kv)

                self.kv = KeyValuePage:new{
                    title = book_title,
                    value_overflow_align = "right",
                    kv_pairs = self:getBookStat(id_book),
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
    return T(_("Total hours read %1"), util.secondsToClock(total_books_time, false)), total_stats
end

function ReaderStatistics:resetBook()
    local total_stats = {}
    local kv_reset_book

    self:insertDB(self.id_curr_book)
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT id
        FROM   book
        ORDER  BY last_open DESC
    ]]
    local id_book_tbl = conn:exec(sql_stmt)
    local nr_books
    if id_book_tbl ~= nil then
        nr_books = #id_book_tbl.id
    else
        nr_books = 0
    end

    local total_time_book
    for i=1, nr_books do
        local id_book = tonumber(id_book_tbl[1][i])
        sql_stmt = [[
            SELECT title
            FROM   book
            WHERE  id = '%s'
        ]]
        local book_title = conn:rowexec(string.format(sql_stmt, id_book))
        sql_stmt = [[
            SELECT sum(period)
            FROM   page_stat
            WHERE  id_book = '%s'
        ]]
        total_time_book = conn:rowexec(string.format(sql_stmt,id_book))
        if total_time_book == nil then
            total_time_book = 0
        end

        if id_book ~= self.id_curr_book then
            table.insert(total_stats, {
                book_title,
                util.secondsToClock(total_time_book, false),
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
                            --refresh window after delete item
                            kv_reset_book:_populateItems()
                        end,
                    })
                end,
            })
        end
    end
    kv_reset_book = KeyValuePage:new{
        title = _("Reset book statistics"),
        value_align = "right",
        kv_pairs = total_stats,
    }
    UIManager:show(kv_reset_book)
    conn:close()
end

function ReaderStatistics:deleteBook(id_book)
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
            DELETE from book
            WHERE  id = ?
        ]]
    local stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(id_book):step()

    sql_stmt = [[
            DELETE from page_stat
            WHERE  id_book = ?
        ]]
    stmt = conn:prepare(sql_stmt)
    stmt:reset():bind(id_book):step()
    stmt:close()
    conn:close()
end

function ReaderStatistics:onPosUpdate(pos, pageno)
    if self.curr_page ~= pageno then
        self:onPageUpdate(pageno)
    end
end

function ReaderStatistics:onPageUpdate(pageno)
    if self:isDocless() or not self.is_enabled then
        return
    end
    self.curr_page = pageno
    self.pages_stats[TimeVal:now().sec] = pageno
    local mem_read_pages = 0
    local mem_read_time = 0
    if util.tableSize(self.pages_stats) > 1 then
        mem_read_pages = util.tableSize(self.pages_stats) - 1
        local sorted_performance = {}
        for time, page in pairs(self.pages_stats) do
            table.insert(sorted_performance, time)
        end
        table.sort(sorted_performance)
        local diff_time
        for i=1, #sorted_performance - 1 do
            diff_time = sorted_performance[i + 1] - sorted_performance[i]
            if diff_time <= self.page_max_read_sec and diff_time >= self.page_min_read_sec  then
                mem_read_time = mem_read_time + diff_time
            elseif diff_time > self.page_max_read_sec then
                mem_read_time = mem_read_time + self.page_max_read_sec
            end
        end
    end
    -- every 50 pages we write stats to database
    if util.tableSize(self.pages_stats) % PAGE_INSERT == 0 then
        self:insertDB(self.id_curr_book)
        mem_read_pages = 0
        mem_read_time = 0
    end
    if self.total_read_pages > 0 or mem_read_pages > 0 then
        self.avg_time = math.ceil((self.total_read_time + mem_read_time) / (self.total_read_pages + mem_read_pages))
    end
end

-- For backward compatibility
function ReaderStatistics:importFromFile(base_path, item)
    item = string.gsub(item, "^%s*(.-)%s*$", "%1") -- trim
    if item ~= ".stat" then
        local statistic_file = joinPath(base_path, item)
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
    if not self:isDocless() and self.is_enabled then
        self.ui.doc_settings:saveSetting("stats", self.data)
        self:insertDB(self.id_curr_book)
    end
end

function ReaderStatistics:onAddHighlight()
    self.data.highlights = self.data.highlights + 1
    return true
end

function ReaderStatistics:onDelHighlight()
    if self.data.highlights > 0 then
        self.data.highlights = self.data.highlights - 1
    end
    return true
end

function ReaderStatistics:onAddNote()
    self.data.notes = self.data.notes + 1
end

function ReaderStatistics:onSaveSettings()
    self:saveSettings()
    if not self:isDocless() then
        self.ui.doc_settings:saveSetting("stats", self.data)
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
    self.start_current_period = TimeVal:now().sec
    self.pages_stats = {}
    self.pages_stats[self.start_current_period] = self.curr_page
end

function ReaderStatistics:saveSettings(fields)
    if fields then
        self.page_min_read_sec = tonumber(fields[1])
        self.page_max_read_sec = tonumber(fields[2])
    end

    local settings = {
        min_sec = self.page_min_read_sec,
        max_sec = self.page_max_read_sec,
        is_enabled = self.is_enabled,
        convert_to_db = self.convert_to_db
    }
    G_reader_settings:saveSetting("statistics", settings)
end

function ReaderStatistics:onReadSettings(config)
    self.data = config.data.stats
end

function ReaderStatistics:onReaderReady()
    -- we have correct page count now, do the actual initialization work
    self:initData()
    self.view.footer:updateFooter()
end

return ReaderStatistics
