--[[
Centralizes any and all one time migration concerns.
--]]

local DataStorage = require("datastorage")
local Version = require("version")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- Retrieve the last migration version
local from_version = G_reader_settings:readSetting("last_migration_version", 0)
print("from_version:", from_version)
print("Version:getCurrentDate():", Version:getCurrentDate())

-- If we haven't actually changed version since the last launch, we're done.
if from_version == Version:getCurrentDate() then
    return
end

-- Keep this in rough chronological order, with a reference to the PR that implemented the change.

-- Global settings, https://github.com/koreader/koreader/pull/4945 & https://github.com/koreader/koreader/pull/5655
-- Limit the check to the most recent update. ReaderUI calls this one unconditionally to update docsettings, too.
if from_version < 20191129 then
    logger.info("Running one-time migration for 20191129")

    local SettingsMigration = require("ui/data/settings_migration")
    SettingsMigration:migrateSettings(G_reader_settings)
end

-- ReaderTypography, https://github.com/koreader/koreader/pull/6072
if from_version < 20200421 then
    logger.info("Running one-time migration for 20200421")

    local ReaderTypography = require("apps/reader/modules/readertypography")
    -- Migrate old readerhyphenation settings
    -- (but keep them in case one goes back to a previous version)
    if G_reader_settings:hasNot("text_lang_default") and G_reader_settings:hasNot("text_lang_fallback") then
        local g_text_lang_set = false
        local hyph_alg_default = G_reader_settings:readSetting("hyph_alg_default")
        if hyph_alg_default then
            local dict_info = ReaderTypography.HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg_default]
            if dict_info then
                G_reader_settings:saveSetting("text_lang_default", dict_info[2])
                g_text_lang_set = true
                -- Tweak the other settings if the default hyph algo happens to be one of these:
                if hyph_alg_default == "@none" then
                    G_reader_settings:makeFalse("hyphenation")
                elseif hyph_alg_default == "@softhyphens" then
                    G_reader_settings:makeTrue("hyph_soft_hyphens_only")
                elseif hyph_alg_default == "@algorithm" then
                    G_reader_settings:makeTrue("hyph_force_algorithmic")
                end
            end
        end
        local hyph_alg_fallback = G_reader_settings:readSetting("hyph_alg_fallback")
        if not g_text_lang_set and hyph_alg_fallback then
            local dict_info = ReaderTypography.HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg_fallback]
            if dict_info then
                G_reader_settings:saveSetting("text_lang_fallback", dict_info[2])
                g_text_lang_set = true
                -- We can't really tweak other settings if the hyph algo fallback happens to be
                -- @none, @softhyphens, @algortihm...
            end
        end
        if not g_text_lang_set then
            -- If nothing migrated, set the fallback to DEFAULT_LANG_TAG,
            -- as we'll always have one of text_lang_default/_fallback set.
            G_reader_settings:saveSetting("text_lang_fallback", ReaderTypography.DEFAULT_LANG_TAG)
        end
    end
end

-- NOTE: ReaderRolling, on the other hand, does some lower-level things @ onReadSettings tied to CRe that would be much harder to factor out.
--       https://github.com/koreader/koreader/pull/1930
-- NOTE: The Gestures plugin also handles its settings migration its own, but deals with it sanely.

-- ScreenSaver, https://github.com/koreader/koreader/pull/7371
if from_version < 20210306 then
    logger.info("Running one-time migration for 20210306 (1/2)")

    -- Migrate settings from 2021.02 or older.
    if G_reader_settings:readSetting("screensaver_type") == "message" then
        G_reader_settings:saveSetting("screensaver_type", "disable")
        G_reader_settings:makeTrue("screensaver_show_message")
    end
    if G_reader_settings:has("screensaver_no_background") then
        if G_reader_settings:isTrue("screensaver_no_background") then
            G_reader_settings:saveSetting("screensaver_background", "none")
        end
        G_reader_settings:delSetting("screensaver_no_background")
    end
    if G_reader_settings:has("screensaver_white_background") then
        if G_reader_settings:isTrue("screensaver_white_background") then
            G_reader_settings:saveSetting("screensaver_background", "white")
        end
        G_reader_settings:delSetting("screensaver_white_background")
    end
end

-- OPDS, same as above
if from_version < 20210306 then
    logger.info("Running one-time migration for 20210306 (2/2)")

    local opds_servers = G_reader_settings:readSetting("opds_servers")
    if opds_servers then
        -- Update deprecated URLs & remove deprecated entries
        for i = #opds_servers, 1, -1 do
            local server = opds_servers[i]

            if server.url == "http://bookserver.archive.org/catalog/" then
                server.url = "https://bookserver.archive.org"
            elseif server.url == "http://m.gutenberg.org/ebooks.opds/?format=opds" then
                server.url = "https://m.gutenberg.org/ebooks.opds/?format=opds"
            elseif server.url == "http://www.feedbooks.com/publicdomain/catalog.atom" then
                server.url = "https://catalog.feedbooks.com/catalog/public_domain.atom"
            end

            if server.title == "Gallica [Fr] [Searchable]" or server.title == "Project Gutenberg [Searchable]" then
                table.remove(opds_servers, i)
            end
        end
        G_reader_settings:saveSetting("opds_servers", opds_servers)
    end
end

-- Statistics, https://github.com/koreader/koreader/pull/7471
if from_version < 20210330 then
    logger.info("Running one-time migration for 20210330")

    local package_path = package.path
    package.path = string.format("%s/?.lua;%s", "plugins/statistics.koplugin", package_path)
    local ReaderStatistics = dofile("plugins/statistics.koplugin/main.lua")
    package.path = package_path

    local settings = G_reader_settings:readSetting("statistics", ReaderStatistics.default_settings)
    -- Handle a snafu in 2021.03 that could lead to an empty settings table on fresh installs.
    for k, v in pairs(ReaderStatistics.default_settings) do
        if settings[k] == nil then
            settings[k] = v
        end
    end
    G_reader_settings:saveSetting("statistics", settings)
end

-- ScreenSaver, https://github.com/koreader/koreader/pull/7496
if from_version < 20210404 then
    logger.info("Running one-time migration for 20210404")

    -- Migrate settings from 2021.03 or older.
    if G_reader_settings:has("screensaver_background") then
        G_reader_settings:saveSetting("screensaver_img_background", G_reader_settings:readSetting("screensaver_background"))
        G_reader_settings:delSetting("screensaver_background")
    end
end

-- Fontlist, cache migration, https://github.com/koreader/koreader/pull/7524
if from_version < 20210409 then
    logger.info("Running one-time migration for 20210409")

    -- NOTE: Before 2021.04, fontlist used to squat our folder, needlessly polluting our state tracking.
    local cache_path = DataStorage:getDataDir() .. "/cache"
    local new_path = cache_path .. "/fontlist"
    lfs.mkdir(new_path)
    local ok, err = os.rename(cache_path .. "/fontinfo.dat", new_path .. "/fontinfo.dat")
    if not ok then
       logger.warn("os.rename:", err)
    end
end

-- Calibre, cache migration, https://github.com/koreader/koreader/pull/7528
if from_version < 20210412 then
    logger.info("Running one-time migration for 20210412")

    -- Ditto for Calibre
    local cache_path = DataStorage:getDataDir() .. "/cache"
    local new_path = cache_path .. "/calibre"
    lfs.mkdir(new_path)
    local ok, err = os.rename(cache_path .. "/calibre-libraries.lua", new_path .. "/libraries.lua")
    if not ok then
       logger.warn("os.rename:", err)
    end
    ok, err = os.rename(cache_path .. "/calibre-books.dat", new_path .. "/books.dat")
    if not ok then
       logger.warn("os.rename:", err)
    end
end

-- We're done, store the current migration version
G_reader_settings:saveSetting("last_migration_version", Version:getCurrentDate())
