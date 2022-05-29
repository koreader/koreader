local DataStorage = require("datastorage")
local Device = require("device")
local SQ3 = require("lua-ljsqlite3/init")
local LuaData = require("luadata")

local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"

local DB_SCHEMA_VERSION = 20220522
local VOCABULARY_DB_SCHEMA = [[
    -- To store looked up words
    CREATE TABLE IF NOT EXISTS "vocabulary" (
        "word"          TEXT NOT NULL UNIQUE,
        "book_title"    TEXT DEFAULT '',
        "create_time"   INTEGER NOT NULL,
        "review_time"   INTEGER,
        "due_time"      INTEGER NOT NULL,
        "review_count"  INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY("word")
    );
    CREATE INDEX IF NOT EXISTS due_time_index ON vocabulary(due_time);
]]

local VocabularyBuilder = {
    count = 0,
}

function VocabularyBuilder:init()
    VocabularyBuilder:createDB()
end

function VocabularyBuilder:hasItems()
    if self.count > 0 then
        return true
    end
    self.count = self:selectCount()
    return self.count > 0
end

function VocabularyBuilder:selectCount(conn)
    if conn then
        return tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
    else
        local db_conn = SQ3.open(db_location)
        local count = tonumber(db_conn:rowexec("SELECT count(0) FROM vocabulary;"))
        db_conn:close()
        return count
    end
end

function VocabularyBuilder:createDB()
    local db_conn = SQ3.open(db_location)
    -- Make it WAL, if possible
    if Device:canUseWAL() then
        db_conn:exec("PRAGMA journal_mode=WAL;")
    else
        db_conn:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    -- Create db
    db_conn:exec(VOCABULARY_DB_SCHEMA)
    -- Check version
    local db_version = tonumber(db_conn:rowexec("PRAGMA user_version;"))
    if db_version < DB_SCHEMA_VERSION then
        if db_version == 0 then
            self:insertLookupData(db_conn)
        end
        -- Update version
        db_conn:exec(string.format("PRAGMA user_version=%d;", DB_SCHEMA_VERSION))

    end
    db_conn:close()
end

function VocabularyBuilder:insertLookupData(db_conn)
    local file_path = DataStorage:getSettingsDir() .. "/lookup_history.lua"

    local lookup_history = LuaData:open(file_path, { name = "LookupHistory" })
    if lookup_history:has("lookup_history") then
        local lookup_history_table = lookup_history:readSetting("lookup_history")
        local words = {}

        for i = #lookup_history_table, 1, -1 do
            local value = lookup_history_table[i]
            if not words[value.word] then
                local insert_sql = [[INSERT OR REPLACE INTO vocabulary
                            (word, book_title, create_time, due_time) values
                            (?, ?, ?, ?);
                            ]]
                local stmt = db_conn:prepare(insert_sql)

                stmt:bind(value.word, value.book_title or "", value.time, value.time + 5*60)
                stmt:step()
                stmt:clearbind():reset()

                words[value.word] = true
            end
        end

    end
end

function VocabularyBuilder:_select_items(items, start_idx)

    local conn = SQ3.open(db_location)
    local sql = string.format("SELECT * FROM vocabulary ORDER BY due_time limit %d OFFSET %d;",32, start_idx-1)

    local results = conn:exec(sql)
    conn:close()
    if not results then return end

    local current_time = os.time()

    for i = 1, #results.word do
        local item = items[start_idx+i-1]
        if item then
            item.word = results.word[i]
            item.review_count = math.max(0, math.min(8, tonumber(results.review_count[i])))
            item.book_title = results.book_title[i] or ""
            item.create_time = tonumber( results.create_time[i])
            item.review_time = tonumber( results.review_time[i])
            item.due_time = tonumber(results.due_time[i])
            item.is_dim = tonumber(results.due_time[i]) > current_time
            item.got_it_callback = function(item_input)
                VocabularyBuilder:gotOrForgot(item_input, true)
            end
            item.forgot_callback = function(item_input)
                VocabularyBuilder:gotOrForgot(item_input, false)
            end
            item.remove_callback = function(item_input)
                VocabularyBuilder:remove(item_input)
            end
        end
    end


end

function VocabularyBuilder:select_items(items, start_idx, end_idx)

    local start_cursor
    if #items == 0 then
        start_cursor = 0
    else
        for i = start_idx+1, end_idx do
            if not items[i].word then
                start_cursor = i
                break
            end
        end
    end

    if not start_cursor then return end
    self:_select_items(items, start_cursor)
end


function VocabularyBuilder:gotOrForgot(item, isGot)
    local conn = SQ3.open(db_location)
    local current_time = os.time()

    local due_time
    local target_count = math.min(math.max(item.review_count + (isGot and 1 or -1), 0), 8)
    if target_count == 0 then
        due_time = current_time + 5 * 60
    elseif target_count == 1 then
        due_time = current_time + 30 * 60
    elseif target_count == 2 then
        due_time = current_time + 12 * 3600
    elseif target_count == 3 then
        due_time = current_time + 24 * 3600
    elseif target_count == 4 then
        due_time = current_time + 48 * 3600
    elseif target_count == 5 then
        due_time = current_time + 96 * 3600
    elseif target_count == 6 then
        due_time = current_time + 24 * 7 * 3600
    elseif target_count == 7 then
        due_time = current_time + 24 * 15 * 3600
    else
        due_time = current_time + 24 * 30 * 3600
    end

    local sql = string.format([[UPDATE vocabulary
    SET review_count = %d,
        review_time = %d,
        due_time = %d
    WHERE word = '%s';]], target_count, current_time, due_time, item.word)

    local x = conn:exec(sql)

    if x == nil then
        item.review_count = target_count
        item.reviewable = false
        item.due_time = due_time
    end
    conn:close()
end

function VocabularyBuilder:insertOrUpdate(entry)
    local conn = SQ3.open(db_location)

    conn:exec(string.format([[INSERT INTO vocabulary (word, book_title, create_time, due_time)
                    VALUES ('%s', '%s', %d, %d)
                    ON CONFLICT(word) DO UPDATE SET book_title = excluded.book_title,
                        create_time = excluded.create_time,
                        review_count = MAX(review_count-1, 0),
                        due_time = %d;
              ]], entry.word, entry.book_title, entry.time, entry.time+300, entry.time+300))
    self.count = tonumber(conn:rowexec("SELECT count(0) from vocabulary;"))
    conn:close()
end

function VocabularyBuilder:remove(item)
    local conn = SQ3.open(db_location)
    conn:exec(string.format("DELETE FROM vocabulary WHERE word = '%s' ;", item.word))
    self.count = self.count - 1
    conn:close()
end

function VocabularyBuilder:resetProgress()
    local conn = SQ3.open(db_location)
    local due_time = os.time()
    conn:exec(string.format("UPDATE vocabulary SET review_count = 0, due_time = %d;", due_time))
    conn:close()
end

function VocabularyBuilder:resetWordProgress(word)
    local conn = SQ3.open(db_location)
    local due_time = os.time()
    conn:exec(string.format("UPDATE vocabulary SET review_count = 0, due_time = %d WHERE word = '%s';", due_time, word))
    conn:close()
end

function VocabularyBuilder:purge()
    local conn = SQ3.open(db_location)
    conn:exec("DELETE FROM vocabulary;")
    self.count = 0
    conn:close()
end

VocabularyBuilder:init()

return VocabularyBuilder
