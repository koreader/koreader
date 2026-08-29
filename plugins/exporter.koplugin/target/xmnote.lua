local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local InputDialog = require("ui/widget/inputdialog")
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local logger = require("logger")
local rapidjson = require("rapidjson")
local util = require("util")
local _ = require("gettext")

local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local XMNoteExporter = require("base"):new{
    name = "xmnote",
    title = _("XMNote"),
    is_remote = true,
    server_port = 8080,
    help_text = _([[Before starting the export process, please make sure that your mobile and KOReader are connected to the same local network. Open XMNote and go to "My" - "Import Highlights" - "Import via API". At the bottom of the interface, you will find the IP address of your mobile device. Enter this IP address into KOReader to complete the configuration.]]),
}

function XMNoteExporter:genTargetSubMenu()
    local dialog_title = _("Set XMNote IP")
    return {
        self:genExportToMenuItem(),
        self:genHelpMenuItem(),
        -- separator
        {
            text = dialog_title,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local url_dialog
                url_dialog = InputDialog:new{
                    title = dialog_title,
                    input = self.settings.ip,
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(url_dialog)
                                end,
                            },
                            {
                                text = _("Set IP"),
                                callback = function()
                                    self.settings.ip = url_dialog:getInputText()
                                    UIManager:close(url_dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        },
                    },
                }
                UIManager:show(url_dialog)
                url_dialog:onShowKeyboard()
            end
        },
    }
end

local function emptyJsonArray()
    return rapidjson.array({})
end

function XMNoteExporter:findBookIdInStatistics(conn, title, author, md5)
    local function findByMd5(author_value)
        local stmt = conn:prepare([[
            SELECT id
            FROM   book
            WHERE  title = ?
              AND  authors = ?
              AND  md5 = ?
            LIMIT 1;
        ]])
        local row = stmt:reset():bind(title, author_value, md5):step()
        stmt:close()
        return row and tonumber(row[1])
    end

    local function findUniqueWithoutMd5(author_values)
        local sql_stmt
        if #author_values == 1 then
            sql_stmt = [[
                SELECT id
                FROM   book
                WHERE  title = ?
                  AND  authors = ?
                LIMIT 2;
            ]]
        else
            sql_stmt = [[
                SELECT id
                FROM   book
                WHERE  title = ?
                  AND  authors IN (?, ?)
                LIMIT 2;
            ]]
        end
        local stmt = conn:prepare(sql_stmt)
        local first_row = stmt:reset():bind(title, unpack(author_values)):step()
        local second_row = first_row and stmt:step()
        stmt:close()
        if first_row and not second_row then
            return tonumber(first_row[1])
        end
    end

    title = title or ""
    local author_values
    if author and author ~= "" then
        author_values = { author }
    else
        author_values = { "N/A", "" }
    end

    if md5 and md5 ~= "" then
        for _, author_value in ipairs(author_values) do
            local book_id = findByMd5(author_value)
            if book_id then
                return book_id
            end
        end
    end

    return findUniqueWithoutMd5(author_values)
end

function XMNoteExporter:getBookReadingDurationsByDay(title, author, md5, md5_source)
    if not util.fileExists(db_location) then
        return emptyJsonArray()
    end

    local ok, durations = pcall(function()
        local conn = SQ3.open(db_location)
        local book_id = self:findBookIdInStatistics(conn, title, author, md5)
        if not book_id then
            conn:close()
            return emptyJsonArray()
        end

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

        local result_durations = conn:exec(string.format(sql_query_durations, book_id))
        conn:close()

        if not (result_durations and result_durations.date) then
            return emptyJsonArray()
        end

        local result = {}
        for i = 1, #result_durations.date do
            local entry = {
                date = tonumber(result_durations[4][i]) * 1000,
                durationSeconds = tonumber(result_durations[3][i]),
                position = tonumber(result_durations[2][i]),
            }
            table.insert(result, entry)
        end
        if #result == 0 then
            return emptyJsonArray()
        end
        return result
    end)
    if not ok then
        local err = tostring(durations):gsub("\n.*", "")
        logger.warn("XMNote: statistics query failed",
            string.format("title=%q author=%q md5_source=%s err=%s",
                title or "", author or "", tostring(md5_source), err))
        return emptyJsonArray()
    end
    return durations
end

function XMNoteExporter:createRequestBody(booknotes)
    local doc_settings = DocSettings:open(booknotes.file)
    local summary = doc_settings:readSetting("summary") or {}
    local md5 = doc_settings:readSetting("partial_md5_checksum")
    local md5_source = "sidecar"
    if not md5 then
        md5 = util.partialMD5(booknotes.file)
        md5_source = md5 and "computed" or "missing"
    end

    local reading_status_map = {
        reading = 2,
        complete = 3,
        abandoned = 4,
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
    book.fuzzyReadingDurations = self:getBookReadingDurationsByDay(
        book.title, book.author, md5, md5_source)
    return book
end

function XMNoteExporter:createHighlights(booknotes)
    local body = self:createRequestBody(booknotes)
    local url = "http://".. self.settings.ip .. ":" .. self.server_port .. "/send"

    local result, err = self:makeJsonRequest(url, "POST", body)
    if not result then
        logger.warn("XMNote: request failed", err)
        return false
    end
    if result.code ~= 200 then
        logger.warn("XMNote: request failed",
            string.format("code=%s message=%s", tostring(result.code), tostring(result.message)))
        return false
    end

    return true
end

function XMNoteExporter:isReadyToExport()
    if self.settings.ip then return true end
    return false
end

function XMNoteExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        if booknotes.file then
            local ok = self:createHighlights(booknotes)
            if not ok then return false end
        end
    end
    return true
end

return XMNoteExporter
