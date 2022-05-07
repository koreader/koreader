
local DataStorage = require("datastorage")
local Device = require("device")
-- local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")
local LuaData = require("luadata")
local VocabBuilderWidget = require("frontend/ui/widget/vocabularybuilderwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")


local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"

local DB_SCHEMA_VERSION = 20220522
local VOCABULARY_DB_SCHEMA = [[
    -- To store looked up words
    CREATE TABLE IF NOT EXISTS "vocabulary" (
        "word"	        TEXT NOT NULL UNIQUE,
        "book_title"	TEXT,
        "create_time"	REAL NOT NULL,
        "review_time"	REAL,
        "due_time"      REAL NOT NULL,
        "review_count"	REAL NOT NULL DEFAULT 0,
        PRIMARY KEY("word")
    );
    
    CREATE INDEX IF NOT EXISTS due_time_index ON vocabulary(due_time);
]]
-- CREATE INDEX IF NOT EXISTS create_time_index ON vocabulary(create_time);
-- CREATE INDEX IF NOT EXISTS review_time_index ON vocabulary(review_time);

local VocabularyBuilder = {}

function VocabularyBuilder:init()
    VocabularyBuilder:createDB()
    local conn = SQ3.open(db_location)
    local count = conn:rowexec("SELECT count(0) FROM vocabulary;")
    self["has_items"] = count > 0
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
        -- if not lookup_history_table return
        for i = #lookup_history_table, 1, -1 do
            local value = lookup_history_table[i]
            if not words[value.word] then
                local insert_sql = [[INSERT OR REPLACE INTO vocabulary
                            (word, book_title, create_time, due_time) values
                            (?, ?, ?, ?);
                            ]]
                local stmt = db_conn:prepare(insert_sql)

                stmt:bind(value.word, value.book_title, value.time, value.time + 5*60)
                stmt:step()
                stmt:clearbind():reset()

                words[value.word] = true
            end
        end
        

        -- os.remove(file_path)
    end
end

function VocabularyBuilder:getDuration(seconds)
    local abs = math.abs(seconds)
    local readable_time
    if abs < 60 then
        readable_time = "0m"
    elseif abs < 3600 then
        readable_time = string.format("%dm", abs/60)
    elseif abs < 3600 * 24 then
        readable_time = string.format("%dh", abs/3600)
    else
        readable_time = string.format("%dd", abs/3600/24)
    end

    if seconds < 0 then
        return " " .. readable_time
    else
        return readable_time
    end
end

function VocabularyBuilder:showUI(onSelect)
    local conn = SQ3.open(db_location)

    local results = conn:exec("SELECT * FROM vocabulary ORDER BY due_time;")
    local current_time = os.time()

    local vocab_items = {}
    for i = 1, #results.word, 1 do
        local reviewable = results.due_time[i] < current_time

        table.insert(vocab_items, {
            word = results.word[i],
            reviewable = reviewable,
            review_count = results.review_count[i],
            book_title = results.book_title[i],
            create_time = results.create_time[i],
            review_time = results.review_time[i],
            elapse_time = results.review_count[i] < 8 and self:getDuration(current_time - results.due_time[i]) .. " | " or "",
            got_it_callback = function(item)
                VocabularyBuilder:gotOrForgot(item, true)
            end,
            forgot_callback = function(item)
                VocabularyBuilder:gotOrForgot(item, false)
            end,
            remove_callback = function(item)
                VocabularyBuilder:remove(item)
            end,
            callback = onSelect
        })
    end
    conn:close()
    

    local vocab_widget = VocabBuilderWidget:new{
        title = _("Vocabulary Builder"),
        item_table = vocab_items,
        callback = function()
            UIManager:setDirty(nil, "ui")
            changed_callback()
        end
    }
    UIManager:show(vocab_widget)
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
        due_time = current_time + 25 * 30 * 3600
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
        item.elapse_time = target_count < 8 and self:getDuration(current_time - due_time) .. " | " or ""
    end
    conn:close()
end

function VocabularyBuilder:insertOrUpdate(entry) 
    local conn = SQ3.open(db_location)
    local current_time = os.time()

    conn:exec(string.format([[INSERT INTO vocabulary (word, book_title, create_time, due_time) 
                    VALUES ('%s', '%s', %d, %d)
                    ON CONFLICT(word) DO UPDATE SET book_title = excluded.book_title,
                        create_time = excluded.create_time,
                        review_count = MAX(review_count-1, 0),
                        due_time = %d;
              ]], entry.word, entry.book_title, entry.time, entry.time+300, entry.time+300))
    conn:close()
end

function VocabularyBuilder:remove(item)
    local conn = SQ3.open(db_location)
    conn:exec(string.format("DELETE FROM vocabulary WHERE word = '%s' ;", item.word))
end

function VocabularyBuilder:reset()
    local conn = SQ3.open(db_location)
    conn:exec("DELETE * FROM vocabulary;")
end

VocabularyBuilder:init()

return VocabularyBuilder