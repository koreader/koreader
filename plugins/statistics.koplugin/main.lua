local InputContainer = require("ui/widget/container/inputcontainer")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Menu = require("ui/widget/menu")
local Font = require("ui/font")
local TimeVal = require("ui/timeval")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")
local util = require("util")
local tableutil = require("tableutil")

local statistics_dir = DataStorage:getDataDir() .. "/statistics/"
local history_dir = DataStorage:getDataDir() .. "/history/"

local ReaderStatistics = InputContainer:new {
    last_time = nil,
    page_min_read_sec = 5,
    page_max_read_sec = 90,
    current_period = 0,
    is_enabled = nil,
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
    },
}

function ReaderStatistics:init()
    if self.ui.document.is_djvu or self.ui.document.is_pdf or self.ui.document.is_pic then
        return
    end

    self.ui.menu:registerToMainMenu(self)
    self.current_period = 0

    local settings = G_reader_settings:readSetting("statistics") or {}
    self.page_min_read_sec = tonumber(settings.min_sec)
    self.page_max_read_sec = tonumber(settings.max_sec)
    self.is_enabled = not (settings.is_enabled == false)
    self.last_time = TimeVal:now()
end

function ReaderStatistics:initData(config)
    --first execution
    if self.is_enabled then
        local book_properties = self:getBookProperties()
        self:savePropertiesInToData(book_properties)
        if config.data.stats then
            self.data = config.data.stats
        else
           --first time merge data
            self:inplaceMigration();
        end
        self.data.pages = self.view.document:getPageCount()
        return
    end
end

function ReaderStatistics:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Statistics"),
        sub_item_table = {
            self:getStatisticEnabledMenuTable(),
            self:getStatisticSettingsMenuTable(),
            self:getStatisticForCurrentBookMenuTable(),
            self:getStatisticTotalStatisticMenuTable(),
        }
    })
end

function ReaderStatistics:getStatisticEnabledMenuTable()
    return {
        text_func = function()
            return _("Enabled")
        end,
        checked_func = function() return self.is_enabled end,
        callback = function()
            -- if was enabled, have to save data to file
            if self.last_time and self.is_enabled then
                self.ui.doc_settings:saveSetting("stats", self.data)
            end

            self.is_enabled = not self.is_enabled
            -- if was disabled have to get data from file
            if self.is_enabled then
                self:initData(self.ui.doc_settings)
            end
            self:saveSettings()
        end,
    }
end

function ReaderStatistics:getStatisticSettingsMenuTable()
    return {
        text_func = function()
            return _("Settings")
        end,
        checked_func = function() return false end,
        callback = function()
            self:updateSettings()
        end,
    }
end

function ReaderStatistics:updateSettings()
    self.settings_dialog = MultiInputDialog:new {
        title = _("Statistics settings"),
        fields = {
            {
                text = "",
                input_type = "number",
                hint = _("Min seconds, default is 5"),
            },
            {
                text = "",
                input_type = "number",
                hint = _("Max seconds, default is 90"),
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
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                        self:saveSettings(MultiInputDialog:getFields())
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

function ReaderStatistics:getStatisticForCurrentBookMenuTable()
    self.status_menu = {}

    local book_status = Menu:new {
        title = _("Status"),
        item_table = self:updateCurrentStat(),
        is_borderless = true,
        is_popout = false,
        is_enable_shortcut = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("cfont", 20),
    }

    self.status_menu = CenterContainer:new {
        dimen = Screen:getSize(),
        book_status,
    }

    book_status.close_callback = function()
        UIManager:close(self.status_menu)
    end

    book_status.show_parent = self.status_menu

    return {
        text = _("Current"),
        enabled_func = function() return true end,
        checked_func = function() return false end,
        callback = function()
            book_status:swithItemTable(nil, self:updateCurrentStat())
            UIManager:show(self.status_menu)
            return true
        end
    }
end

function ReaderStatistics:getStatisticTotalStatisticMenuTable()
    self.total_status = Menu:new {
        title = _("Total"),
        item_table = self:updateTotalStat(),
        is_borderless = true,
        is_popout = false,
        is_enable_shortcut = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("cfont", 20),
    }

    self.total_menu = CenterContainer:new {
        dimen = Screen:getSize(),
        self.total_status,
    }

    self.total_status.close_callback = function()
        UIManager:close(self.total_menu)
    end

    self.total_status.show_parent = self.total_menu

    return {
        text = _("Total"),
        callback = function()
            self.total_status:swithItemTable(nil, self:updateTotalStat())
            UIManager:show(self.total_menu)
            return true
        end
    }
end

function ReaderStatistics:updateCurrentStat()
    local stats = {}
    local dates = {}

    for k, v in pairs(self.data.performance_in_pages) do
        dates[os.date("%Y-%m-%d", k)] = ""
    end

    local read_pages = util.tablelength(self.data.performance_in_pages)
    local average_time_per_page = self.data.total_time_in_sec / read_pages

    table.insert(stats, { text = _("Current period"), mandatory = util.secondsToClock(self.current_period, false) })
    table.insert(stats, { text = _("Time to read"), mandatory = util.secondsToClock(self.data.pages * average_time_per_page, false) })
    table.insert(stats, { text = _("Total time"), mandatory = util.secondsToClock(self.data.total_time_in_sec, false) })
    table.insert(stats, { text = _("Total highlights"), mandatory = self.data.highlights })
    table.insert(stats, { text = _("Total notes"), mandatory = self.data.notes })
    table.insert(stats, { text = _("Total days"), mandatory = util.tablelength(dates) })
    table.insert(stats, { text = _("Average time per page"), mandatory = util.secondsToClock(average_time_per_page, false) })
    table.insert(stats, { text = _("Read pages/Total pages"), mandatory = read_pages .. "/" .. self.data.pages })
    return stats
end

-- For backward compatibility
function ReaderStatistics:getDatesForBookOldFormat(book)
    local dates = {}

    for k, v in pairs(book.details) do
        local date_text = os.date("%Y-%m-%d", v.time)
        if not dates[date_text] then
            dates[date_text] = {
                date = v.time,
                read = v.read,
                count = 1
            }
        else
            dates[date_text] = {
                read = dates[date_text].read + v.read,
                count = dates[date_text].count + 1,
                date = dates[date_text].date
            }
        end
    end

    return self:generateReadBooksTable(book.title, dates)
end


function ReaderStatistics:getDatesForBook(book)
    local dates = {}

    for k, v in pairs(book.performance_in_pages) do
        local date_text = os.date("%Y-%m-%d", k)
        if not dates[date_text] then
            dates[date_text] = {
                date = k,
                read = v,
                count = 1
            }
        else
            dates[date_text] = {
                read = dates[date_text].read + v,
                count = dates[date_text].count + 1,
                date = dates[date_text].date
            }
        end
    end

    return self:generateReadBooksTable(book.title, dates)
end


function ReaderStatistics:generateReadBooksTable(title, dates)
    local result = {}
    table.insert(result, { text = title })
    for k, v in tableutil.spairs(dates, function(t, a, b) return t[b].date < t[a].date end) do
        table.insert(result, { text = k, mandatory = T(_("Pages (%1) Time: %2"), v.count, util.secondsToClock(v.read, false)) })
    end
    return result
end


function ReaderStatistics:updateTotalStat()
    local total_stats = {}
    local total_books_time = 0

    local proceded_titles = self:getStatisticsFromHistory(total_stats, total_books_time)
    self:getOldStatisticsFromDirectory(proceded_titles, total_stats, total_books_time)

    total_books_time = total_books_time + tonumber(self.data.total_time_in_sec)

    DEBUG ("TOTALSTATS", total_stats)
    table.insert(total_stats, 1, { text = _("Total hours read"), mandatory = util.secondsToClock(total_books_time, false) })
    table.insert(total_stats, 2, { text = _("----------------------------------------------------") })
    table.insert(total_stats, 3, {
        text = self.data.title,
        mandatory = util.secondsToClock(self.data.total_time_in_sec, false),
        callback = function()
            self.total_status:swithItemTable(nil, self:getDatesForBook(self.data))
            UIManager:show(self.total_menu)
            return true
        end,
    })
    return total_stats
end

function ReaderStatistics:getStatisticsFromHistory(total_stats, total_books_time)
    local titles = {}
    for curr_file in lfs.dir(history_dir) do
        local path = history_dir .. curr_file
        if lfs.attributes(path, "mode") == "file" then
            local book_result = self:importFromFile(history_dir, curr_file)
            local book_stats = book_result.stats
            if book_stats and book_stats.title ~= self.data.title then
                titles[book_stats.title] = true
                table.insert(total_stats, {
                    text = book_stats.title,
                    mandatory = util.secondsToClock(book_stats.total_time_in_sec, false),
                    callback = function()
                        self.total_status:swithItemTable(nil, self:getDatesForBook(book_stats))
                        UIManager:show(self.total_menu)
                        return true
                    end,
                })
                total_books_time = total_books_time + tonumber(book_stats.total_time_in_sec)
            end
        end
    end
    return titles
end

-- For backward compatibility
function ReaderStatistics:getOldStatisticsFromDirectory(exlude_titles, total_stats, total_books_time)
    if lfs.attributes(statistics_dir, "mode") ~= "directory" then
        return
    end
    for curr_file in lfs.dir(statistics_dir) do
        local path = statistics_dir .. curr_file
        if lfs.attributes(path, "mode") == "file" then
            local book_result = self:importFromFile(statistics_dir, curr_file)
            if book_result and book_result.title ~= self.data.title and not exlude_titles[book_result.title] then
                table.insert(total_stats, {
                    text = book_result.title,
                    mandatory = util.secondsToClock(book_result.total_time, false),
                    callback = function()
                        self.total_status:swithItemTable(nil, self:getDatesForBookOldFormat(book_result))
                        UIManager:show(self.total_menu)
                        return true
                    end,
                })
                total_books_time = total_books_time + tonumber(book_result.total_time)
            end
        end
    end
end

function ReaderStatistics:getBookProperties()
    local props = self.view.document:getProps()
    if props.title == "No document" or props.title == "" then --sometime crengine returns "No document" try to get one more time
      props = self.view.document:getProps()
    end
    return props
end

function ReaderStatistics:onPageUpdate(pageno)
    if self.is_enabled then
        local curr_time = TimeVal:now()
        local diff_time = curr_time.sec - self.last_time.sec

        -- if last update was more then 10 minutes then current period set to 0
        if (diff_time > 600) then
            self.current_period = 0
        end

        if diff_time >= self.page_min_read_sec and diff_time <= self.page_max_read_sec then
            self.current_period = self.current_period + diff_time
            self.data.total_time_in_sec = self.data.total_time_in_sec + diff_time
            self.data.performance_in_pages[curr_time.sec] = pageno
        end

        self.last_time = curr_time
        self.ui.doc_settings:saveSetting("stats", self.data)
    end
end

function ReaderStatistics:savePropertiesInToData(item)
    self.data.title = item.title
    self.data.authors = item.authors
    self.data.language = item.language
    self.data.series = item.series
end


-- For backward compatibility
function ReaderStatistics:inplaceMigration()
    local oldData = self:importFromFile(statistics_dir, self.data.title .. ".stat")
    if oldData then
        for k, v in pairs(oldData.details) do
            self.data.performance_in_pages[v.time] = v.page
        end
    end
end

-- For backward compatibility
function ReaderStatistics:importFromFile(base_path, item)
    item = string.gsub(item, "^%s*(.-)%s*$", "%1") --trim
    if lfs.attributes(base_path .. item, "mode") == "directory" then
        return
    end
    local statisticFile = base_path .. item
    local ok, stored = pcall(dofile, statisticFile)
    if ok then
        return stored
    else
        DEBUG(stored)
    end
end

function ReaderStatistics:onCloseDocument()
    if self.last_time and self.is_enabled then
        self.ui.doc_settings:saveSetting("stats", self.data)
    end
end

function ReaderStatistics:onAddHighlight()
    self.data.highlights = self.data.highlights + 1
end

function ReaderStatistics:onAddNote()
    self.data.notes = self.data.notes + 1
end

-- in case when screensaver starts
function ReaderStatistics:onSaveSettings()
    self:saveSettings()
    self.ui.doc_settings:saveSetting("stats", self.data)
    self.current_period = 0
end

-- screensaver off
function ReaderStatistics:onResume()
    self.current_period = 0
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
    }
    G_reader_settings:saveSetting("statistics", settings)
end

function ReaderStatistics:onReadSettings(config)
    UIManager:scheduleIn(0.1, function() self:initData(config) end)
end

return ReaderStatistics

