local DataStorage = require("datastorage")
local Device = require("device")
local SQ3 = require("lua-ljsqlite3/init")
local LuaData = require("luadata")

local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"

local DB_SCHEMA_VERSION = 20220608
local VOCABULARY_DB_SCHEMA = [[
    -- To store looked up words
    CREATE TABLE IF NOT EXISTS "vocabulary" (
        "word"          TEXT NOT NULL UNIQUE,
        "title_id"      INTEGER,
        "create_time"   INTEGER NOT NULL,
        "review_time"   INTEGER,
        "due_time"      INTEGER NOT NULL,
        "review_count"  INTEGER NOT NULL DEFAULT 0,
        "prev_context"  TEXT,
        "next_context"  TEXT,
        PRIMARY KEY("word")
    );
    CREATE TABLE IF NOT EXISTS "title" (
        "id"            INTEGER NOT NULL UNIQUE,
        "name"          TEXT UNIQUE,
        PRIMARY KEY("id" AUTOINCREMENT)
    );
    CREATE INDEX IF NOT EXISTS due_time_index ON vocabulary(due_time);
    CREATE INDEX IF NOT EXISTS title_name_index ON title(name);
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
        elseif db_version < 20220608 then
            db_conn:exec([[ ALTER TABLE vocabulary ADD prev_context TEXT;
                            ALTER TABLE vocabulary ADD next_context TEXT;
                            ALTER TABLE vocabulary ADD title_id INTEGER;

                            INSERT INTO title (name)
                            SELECT DISTINCT book_title FROM vocabulary;

                            UPDATE vocabulary SET title_id = (
                               SELECT id FROM title WHERE name = book_title
                            );

                            ALTER TABLE vocabulary DROP book_title;]])
        end

        db_conn:exec("CREATE INDEX IF NOT EXISTS title_id_index ON vocabulary(title_id);")
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
        local book_titles = {}
        local stmt = db_conn:prepare("INSERT INTO title (name) values (?);")
        for i = #lookup_history_table, 1, -1 do
            local book_title = lookup_history_table[i].book_title or ""
            if not book_titles[book_title] then
                stmt:bind(book_title)
                stmt:step()
                stmt:clearbind():reset()
                book_titles[book_title] = true
            end
        end

        local words = {}
        local insert_sql = [[INSERT OR REPLACE INTO vocabulary
                            (word, title_id, create_time, due_time) values
                            (?, (SELECT id FROM title WHERE name = ?), ?, ?);]]
        stmt = db_conn:prepare(insert_sql)
        for i = #lookup_history_table, 1, -1 do
            local value = lookup_history_table[i]
            if not words[value.word] then
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
    local sql = string.format("SELECT * FROM vocabulary LEFT JOIN title ON title_id = title.id ORDER BY due_time limit %d OFFSET %d;", 32, start_idx-1)

    local results = conn:exec(sql)
    conn:close()
    if not results then return end

    local current_time = os.time()

    for i = 1, #results.word do
        local item = items[start_idx+i-1]
        if item and not item.word then
            item.word = results.word[i]
            item.review_count = math.max(0, math.min(8, tonumber(results.review_count[i])))
            item.book_title = results.name[i] or ""
            item.create_time = tonumber( results.create_time[i])
            item.review_time = nil --use this field to flag change
            item.due_time = tonumber(results.due_time[i])
            item.is_dim = tonumber(results.due_time[i]) > current_time
            item.prev_context = results.prev_context[i]
            item.next_context = results.next_context[i]
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

    item.review_count = target_count
    item.review_time = current_time
    item.due_time = due_time
end

function VocabularyBuilder:batchUpdateItems(items)
    local sql = [[UPDATE vocabulary
                SET review_count = ?,
                    review_time = ?,
                        due_time = ?
                    WHERE word = ?;]]

    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql)

    for _, item in ipairs(items) do
        if item.review_time then
            stmt:bind(item.review_count, item.review_time, item.due_time, item.word)
            stmt:step()
            stmt:clearbind():reset()
        end
    end

    conn:exec("DELETE FROM title WHERE NOT EXISTS( SELECT title_id FROM vocabulary WHERE id = title_id );")
    conn:close()
end

function VocabularyBuilder:insertOrUpdate(entry)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("INSERT OR IGNORE INTO title (name) VALUES (?);")
    stmt:bind(entry.book_title)
    stmt:step()
    stmt:clearbind():reset()

    stmt = conn:prepare([[INSERT INTO vocabulary (word, title_id, create_time, due_time, prev_context, next_context)
                        VALUES (?, (SELECT id FROM title WHERE name = ?), ?, ?, ?, ?)
                        ON CONFLICT(word) DO UPDATE SET title_id = excluded.title_id,
                        create_time = excluded.create_time,
                        review_count = MAX(review_count-1, 0),
                        due_time = ?,
                        prev_context = ifnull(excluded.prev_context, prev_context),
                        next_context = ifnull(excluded.next_context, next_context);]]);
    stmt:bind(entry.word, entry.book_title, entry.time, entry.time+300,
              entry.prev_context, entry.next_context, entry.time+300)
    stmt:step()
    stmt:clearbind():reset()
    self.count = tonumber(conn:rowexec("SELECT count(0) from vocabulary;"))
    conn:close()
end

function VocabularyBuilder:remove(item)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("DELETE FROM vocabulary WHERE word = ? ;")
    stmt:bind(item.word)
    stmt:step()
    stmt:clearbind():reset()

    self.count = self.count - 1
    conn:close()
end

function VocabularyBuilder:resetProgress()
    local conn = SQ3.open(db_location)
    local due_time = os.time()
    conn:exec(string.format("UPDATE vocabulary SET review_count = 0, due_time = %d;", due_time))
    conn:close()
end

function VocabularyBuilder:purge()
    local conn = SQ3.open(db_location)
    conn:exec("DELETE FROM vocabulary; DELETE FROM title;")
    self.count = 0
    conn:close()
end

VocabularyBuilder:init()

return VocabularyBuilder
