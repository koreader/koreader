local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

-- xmnote exporter
local XMNoteExporter = require("base"):new {
    name = "xmnote",
    is_remote = true,
    server_port = 8080
}

function XMNoteExporter:getMenuTable()
    return  {
        text = _("XMNote"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set XMNote IP"),
                keep_menu_open = true,
                callback = function()
                    local url_dialog
                    url_dialog = InputDialog:new {
                        title = _("Set XMNote IP"),
                        input = self.settings.ip,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(url_dialog)
                                    end
                                },
                                {
                                    text = _("Set IP"),
                                    callback = function()
                                        local ip = url_dialog:getInputText()
                                        self.settings.ip = ip
                                        self:saveSettings()
                                        UIManager:close(url_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(url_dialog)
                    url_dialog:onShowKeyboard()
                end
            } ,
            {
                text = _("Export to XMNote"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new {
                        text = T(_([[Before starting the export process, please make sure that your mobile and KOReader are connected to the same local network. Open XMNote and go to "My" - "Import Highlights" - "Import via API". At the bottom of the interface, you will find the IP address of your mobile device. Enter this IP address into KOReader to complete the configuration.]])
                    , BD.dirpath(DataStorage:getDataDir()))
                    })
                end
            }
        }
    }
end

function XMNoteExporter:getBookReadingDurationsByDay(title, md5)
    if util.fileExists(db_location) then
        local conn = SQ3.open(db_location)
        local sql_query_book_id = [[SELECT id FROM book WHERE title = "%s" and md5 = "%s" LIMIT 1]]
        local sql_query_durations = [[
            SELECT date(start_time, 'unixepoch', 'localtime') AS date,
                   max(page)                                  AS last_page,
                   sum(duration)                              AS total_duration,
                   min(start_time)                            AS first_start_time
            FROM   page_stat
            WHERE  id_book = %d
            GROUP  BY Date(start_time, 'unixepoch', 'localtime')
            ORDER  BY date DESC;
        ]]

        local result_book_id = conn:exec(string.format(sql_query_book_id, title, md5))
        if not (result_book_id and result_book_id[1] and result_book_id[1][1]) then
            return {}
        end
        local book_id = tonumber(result_book_id[1][1])

        local result_durations = conn:exec(string.format(sql_query_durations, book_id))
        conn:close()

        if not result_durations then
            return {}
        end

        local durations = {}
        for i = 1, #result_durations.date do
            local entry = {
                date = tonumber(result_durations[4][i]) * 1000,
                durationSeconds = tonumber(result_durations[3][i]),
                position = tonumber(result_durations[2][i]),
            }
            table.insert(durations, entry)
        end
        return durations
    else
        return {}
    end
end

function XMNoteExporter:createRequestBody(booknotes)
    local doc_settings = DocSettings:open(booknotes.file)
    local summary = doc_settings:readSetting("summary") or {}
    local md5 = doc_settings:readSetting("partial_md5_checksum")

    local reading_status_map = {
        reading = 2,
        complete = 3,
        abandoned = 5,
    }

    local reading_status_changed_date
    if summary.modified and summary.modified ~= "" then
        reading_status_changed_date = datetime.stringToSeconds(summary.modified)
    else
        reading_status_changed_date = 0
    end

    local book = {
        title = booknotes.title or "",
        author = booknotes.author or "",
        type = 1,
        locationUnit = 1,
        readingStatus = reading_status_map[summary.status] or reading_status_map.reading,
        readingStatusChangedDate = reading_status_changed_date,
        source = "KOReader"
    }
    local entries = {}

    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local entry = {
                text = clipping.text,
                note = clipping.note or "",
                chapter = clipping.chapter,
                time = clipping.time
            }
            local page = tonumber(clipping.page)
            if page ~= nil then
                entry.page = page
            end
            table.insert(entries, entry)
        end
    end
    book.entries = entries
    book.fuzzyReadingDurations = self:getBookReadingDurationsByDay(book.title, md5)
    return book
end

function XMNoteExporter:createHighlights(booknotes)
    local body = self:createRequestBody(booknotes)
    local url = "http://".. self.settings.ip .. ":" .. self.server_port .. "/send"

    local result, err = self:makeJsonRequest(url, "POST", body)
    if not result then
        logger.warn("error creating highlights", err)
        return false
    end

    logger.dbg("createHighlights result", result)
    return true
end

function XMNoteExporter:isReadyToExport()
    if self.settings.ip then return true end
    return false
end

function XMNoteExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return XMNoteExporter
