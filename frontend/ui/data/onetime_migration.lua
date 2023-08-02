--[[
Centralizes any and all one time migration concerns.
--]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util")
local _ = require("gettext")

-- Date at which the last migration snippet was added
local CURRENT_MIGRATION_DATE = 20230802

-- Retrieve the date of the previous migration, if any
local last_migration_date = G_reader_settings:readSetting("last_migration_date", 0)

-- If there's nothing new to migrate since the last time, we're done.
if last_migration_date == CURRENT_MIGRATION_DATE then
    return
end

-- Keep this in rough chronological order, with a reference to the PR that implemented the change.

-- Global settings, https://github.com/koreader/koreader/pull/4945 & https://github.com/koreader/koreader/pull/5655
-- Limit the check to the most recent update. ReaderUI calls this one unconditionally to update docsettings, too.
if last_migration_date < 20191129 then
    logger.info("Performing one-time migration for 20191129")

    local SettingsMigration = require("ui/data/settings_migration")
    SettingsMigration:migrateSettings(G_reader_settings)
end

-- ReaderTypography, https://github.com/koreader/koreader/pull/6072
if last_migration_date < 20200421 then
    logger.info("Performing one-time migration for 20200421")

    -- Drop the Fontlist cache early, in case it's in an incompatible format for some reason...
    -- c.f., https://github.com/koreader/koreader/issues/9771#issuecomment-1546308746
    -- (This is basically the 20220914 migration step applied preemptively, as readertypography *will* attempt to load it).
    local cache_path = DataStorage:getDataDir() .. "/cache/fontlist"
    local ok, err = os.remove(cache_path .. "/fontinfo.dat")
    if not ok then
       logger.warn("os.remove:", err)
    end

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
-- NOTE: The Gestures plugin also handles its settings migration on its own, but deals with it sanely.

-- ScreenSaver, https://github.com/koreader/koreader/pull/7371
if last_migration_date < 20210306 then
    logger.info("Performing one-time migration for 20210306 (1/2)")

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
if last_migration_date < 20210306 then
    logger.info("Performing one-time migration for 20210306 (2/2)")

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
if last_migration_date < 20210330 then
    logger.info("Performing one-time migration for 20210330")

    -- c.f., PluginLoader
    local package_path = package.path
    package.path = string.format("%s/?.lua;%s", "plugins/statistics.koplugin", package_path)
    local ok, ReaderStatistics = pcall(dofile, "plugins/statistics.koplugin/main.lua")
    package.path = package_path
    if not ok or not ReaderStatistics then
        logger.warn("Error when loading plugins/statistics.koplugin/main.lua:", ReaderStatistics)
    else
        local settings = G_reader_settings:readSetting("statistics")
        if settings then
            -- Handle a snafu in 2021.03 that could lead to an empty settings table on fresh installs.
            for k, v in pairs(ReaderStatistics.default_settings) do
                if settings[k] == nil then
                    settings[k] = v
                end
            end
            G_reader_settings:saveSetting("statistics", settings)
        end
    end
end

-- ScreenSaver, https://github.com/koreader/koreader/pull/7496
if last_migration_date < 20210404 then
    logger.info("Performing one-time migration for 20210404")

    -- Migrate settings from 2021.03 or older.
    if G_reader_settings:has("screensaver_background") then
        G_reader_settings:saveSetting("screensaver_img_background", G_reader_settings:readSetting("screensaver_background"))
        G_reader_settings:delSetting("screensaver_background")
    end
end

-- Fontlist, cache migration, https://github.com/koreader/koreader/pull/7524
if last_migration_date < 20210409 then
    logger.info("Performing one-time migration for 20210409")

    -- NOTE: Before 2021.04, fontlist used to squat our folder, needlessly polluting our state tracking.
    local cache_path = DataStorage:getDataDir() .. "/cache"
    local new_path = cache_path .. "/fontlist"
    lfs.mkdir(new_path)
    local ok, err = os.rename(cache_path .. "/fontinfo.dat", new_path .. "/fontinfo.dat")
    if not ok then
       logger.warn("os.rename:", err)
    end

    -- Make sure DocCache gets the memo
    local DocCache = require("document/doccache")
    DocCache:refreshSnapshot()
end

-- Calibre, cache migration, https://github.com/koreader/koreader/pull/7528
if last_migration_date < 20210412 then
    logger.info("Performing one-time migration for 20210412")

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

    -- Make sure DocCache gets the memo
    local DocCache = require("document/doccache")
    DocCache:refreshSnapshot()
end

-- Calibre, cache encoding format change, https://github.com/koreader/koreader/pull/7543
if last_migration_date < 20210414 then
    logger.info("Performing one-time migration for 20210414")

    local cache_path = DataStorage:getDataDir() .. "/cache/calibre"
    local ok, err = os.remove(cache_path .. "/books.dat")
    if not ok then
       logger.warn("os.remove:", err)
    end
end

-- 20210503: DocCache, migration to Persist, https://github.com/koreader/koreader/pull/7624
-- 20210508: DocCache, KOPTInterface hash fix, https://github.com/koreader/koreader/pull/7634
if last_migration_date < 20210508 then
    logger.info("Performing one-time migration for 20210503 & 20210508")

    local DocCache = require("document/doccache")
    DocCache:clearDiskCache()
end

-- 20210518, ReaderFooter, https://github.com/koreader/koreader/pull/7702
-- 20210622, ReaderFooter, https://github.com/koreader/koreader/pull/7876
if last_migration_date < 20210622 then
    logger.info("Performing one-time migration for 20210622")

    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local settings = G_reader_settings:readSetting("footer", ReaderFooter.default_settings)

    -- Make sure we have a full set, some of these were historically kept as magic nils...
    for k, v in pairs(ReaderFooter.default_settings) do
        if settings[k] == nil then
            settings[k] = v
        end
    end
    G_reader_settings:saveSetting("footer", settings)
end

-- 20210521, ReaderZooming, zoom_factor -> kopt_zoom_factor, https://github.com/koreader/koreader/pull/7728
if last_migration_date < 20210521 then
    logger.info("Performing one-time migration for 20210521")

    -- ReaderZooming:init has the same logic for individual DocSettings in onReadSettings
    if G_reader_settings:has("zoom_factor") and G_reader_settings:hasNot("kopt_zoom_factor") then
        G_reader_settings:saveSetting("kopt_zoom_factor", G_reader_settings:readSetting("zoom_factor"))
        G_reader_settings:delSetting("zoom_factor")
    elseif G_reader_settings:has("zoom_factor") and G_reader_settings:has("kopt_zoom_factor") then
        G_reader_settings:delSetting("zoom_factor")
    end
end

-- 20210531, ReaderZooming, deprecate zoom_mode in global settings, https://github.com/koreader/koreader/pull/7780
if last_migration_date < 20210531 then
    logger.info("Performing one-time migration for 20210531")

    if G_reader_settings:has("zoom_mode") then
        local ReaderZooming = require("apps/reader/modules/readerzooming")
        -- NOTE: For simplicity's sake, this will overwrite potentially existing genus/type globals,
        --       as they were ignored in this specific case anyway...
        local zoom_mode_genus, zoom_mode_type = ReaderZooming:mode_to_combo(G_reader_settings:readSetting("zoom_mode"))
        G_reader_settings:saveSetting("kopt_zoom_mode_genus", zoom_mode_genus)
        G_reader_settings:saveSetting("kopt_zoom_mode_type", zoom_mode_type)
        G_reader_settings:delSetting("zoom_mode")
    end
end

-- 20210629, Moves Duration Format to Date Time settings for other plugins to use, https://github.com/koreader/koreader/pull/7897
if last_migration_date < 20210629 then
    logger.info("Performing one-time migration for 20210629")

    local footer = G_reader_settings:child("footer")
    if footer and footer:has("duration_format") then
        local user_format = footer:readSetting("duration_format")
        G_reader_settings:saveSetting("duration_format", user_format)
        footer:delSetting("duration_format")
    end
end

-- 20210715, Rename `numeric` to `natural`, https://github.com/koreader/koreader/pull/7978
if last_migration_date < 20210715 then
    logger.info("Performing one-time migration for 20210715")
    if G_reader_settings:has("collate") then
        local collate = G_reader_settings:readSetting("collate")
        if collate == "numeric" then
            G_reader_settings:saveSetting("collate", "natural")
        end
    end
end

-- 20210720, Reset all user's duration time to classic, https://github.com/koreader/koreader/pull/8008
if last_migration_date < 20210720 then
    logger.info("Performing one-time migration for 20210720")
    -- With PR 7897 and migration date 20210629, we migrated everyone's duration format to the combined setting.
    -- However, the footer previously defaulted to "modern", so users who were used to seeing "classic" in the UI
    -- started seeing the modern format unexpectedly. Therefore, reset everyone back to classic so users go back
    -- to a safe default. Users who use "modern" will need to reselect it in Time and Date settings after this migration.
    G_reader_settings:saveSetting("duration_format", "classic")
end

-- 20210831, Clean VirtualKeyboard settings of disabled layouts, https://github.com/koreader/koreader/pull/8159
if last_migration_date < 20210831 then
    logger.info("Performing one-time migration for 20210831")
    local FFIUtil = require("ffi/util")
    local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
    local keyboard_layouts_new = {}
    local selected_layouts_count = 0
    for k, v in FFIUtil.orderedPairs(keyboard_layouts) do
        if v == true and selected_layouts_count < 4 then
            selected_layouts_count = selected_layouts_count + 1
            keyboard_layouts_new[selected_layouts_count] = k
        end
    end
    G_reader_settings:saveSetting("keyboard_layouts", keyboard_layouts_new)
end

-- 20210902, Remove unneeded auto_warmth settings after #8154
if last_migration_date < 20210925 then
    logger.info("Performing one-time migration for 20210925")
    G_reader_settings:delSetting("frontlight_auto_warmth")
    G_reader_settings:delSetting("frontlight_max_warmth_hour")
end

-- OPDS, add new server, https://github.com/koreader/koreader/pull/8606
if last_migration_date < 20220116 then
    logger.info("Performing one-time migration for 20220116")

    local opds_servers = G_reader_settings:readSetting("opds_servers")
    if opds_servers then
        -- Check if the user hadn't already added it
        local found = false
        local gutenberg_id
        for i = #opds_servers, 1, -1 do
            local server = opds_servers[i]

            if server.url == "https://standardebooks.org/opds" then
                found = true
            elseif server.url == "https://m.gutenberg.org/ebooks.opds/?format=opds" then
                gutenberg_id = i
            end
        end

        if not found then
            local std_ebooks = {
                title = "Standard Ebooks",
                url = "https://standardebooks.org/opds",
            }

            -- Append it at the same position as on stock installs, if possible
            if gutenberg_id then
                table.insert(opds_servers, gutenberg_id + 1, std_ebooks)
            else
                table.insert(opds_servers, std_ebooks)
            end
            G_reader_settings:saveSetting("opds_servers", opds_servers)
        end
    end
end

-- Disable the jump marker on the Libra 2, to avoid the worst of epdc race issues...
-- c.f., https://github.com/koreader/koreader/issues/8414
if last_migration_date < 20220205 then
    logger.info("Performing one-time migration for 20220205")

    local Device = require("device")
    if Device:isKobo() and Device.model == "Kobo_io" then
        G_reader_settings:makeFalse("followed_link_marker")
    end
end

-- Rename several time storing settings and shift their value to the new meaning see (#8999)
if last_migration_date < 20220426 then
    local function migrateSettingsName(old, new, factor)
        factor = factor or 1
        if G_reader_settings:readSetting(old) then
            local value = math.floor(G_reader_settings:readSetting(old) * factor)
            G_reader_settings:saveSetting(new, value)
            G_reader_settings:delSetting(old)
        end
    end
    migrateSettingsName("ges_tap_interval", "ges_tap_interval_ms", 1e-3)
    migrateSettingsName("ges_double_tap_interval", "ges_double_tap_interval_ms", 1e-3)
    migrateSettingsName("ges_two_finger_tap_duration", "ges_two_finger_tap_duration_ms", 1e-3)
    migrateSettingsName("ges_hold_interval", "ges_hold_interval_ms", 1e-3)
    migrateSettingsName("ges_swipe_interval", "ges_swipe_interval_ms", 1e-3)
    migrateSettingsName("ges_tap_interval_on_keyboard", "ges_tap_interval_on_keyboard_ms", 1e-3)

    migrateSettingsName("device_status_battery_interval", "device_status_battery_interval_minutes")
    migrateSettingsName("device_status_memory_interval", "device_status_memory_interval_minutes")
end

-- Rename several time storing settings and shift their value to the new meaning follow up to (#8999)
if last_migration_date < 20220523 then
    local function migrateSettingsName(old, new, factor)
        factor = factor or 1
        if G_reader_settings:readSetting(old) then
            local value = math.floor(G_reader_settings:readSetting(old) * factor)
            G_reader_settings:saveSetting(new, value)
            G_reader_settings:delSetting(old)
        end
    end
    migrateSettingsName("highlight_long_hold_threshold", "highlight_long_hold_threshold_s")
end

-- #9104
if last_migration_date < 20220625 then
    os.remove("afterupdate.marker")

    -- Move an existing `koreader/patch.lua` to `koreader/patches/1-patch.lua` (-> will be excuted in `early`)
    local data_dir = DataStorage:getDataDir()
    local patch_dir = data_dir .. "/patches"
    if lfs.attributes(data_dir .. "/patch.lua", "mode") == "file" then
        if lfs.attributes(patch_dir, "mode") == nil then
            if not lfs.mkdir(patch_dir, "mode") then
                logger.err("User patch error creating directory", patch_dir)
            end
        end
        os.rename(data_dir .. "/patch.lua", patch_dir .. "/1-patch.lua")
    end
end

-- OPDS, same as above
if last_migration_date < 20220819 then
    logger.info("Performing one-time migration for 20220819")

    local opds_servers = G_reader_settings:readSetting("opds_servers")
    if opds_servers then
        -- Update deprecated URLs
        for i = #opds_servers, 1, -1 do
            local server = opds_servers[i]

            if server.url == "https://standardebooks.org/opds" then
                server.url = "https://standardebooks.org/feeds/opds"
            end
        end
        G_reader_settings:saveSetting("opds_servers", opds_servers)
    end
end

-- Fontlist, cache format change (#9513)
if last_migration_date < 20220914 then
    logger.info("Performing one-time migration for 20220914")

    local cache_path = DataStorage:getDataDir() .. "/cache/fontlist"
    local ok, err = os.remove(cache_path .. "/fontinfo.dat")
    if not ok then
       logger.warn("os.remove:", err)
    end
end

-- The great defaults.persistent.lua migration to LuaDefaults (#9546)
if last_migration_date < 20220930 then
    logger.info("Performing one-time migration for 20220930")

    local defaults_path = DataStorage:getDataDir() .. "/defaults.persistent.lua"
    local defaults = {}
    local load_defaults, err = loadfile(defaults_path, "t", defaults)
    if not load_defaults then
        logger.warn("loadfile:", err)
    else
        -- User input, there may be syntax errors, go through pcall like we used to.
        local ok, perr = pcall(load_defaults)
        if not ok then
            logger.warn("Failed to execute defaults.persistent.lua:", perr)
            -- Don't keep *anything* around, to make it more obvious that something went screwy...
            logger.warn("/!\\ YOU WILL HAVE TO MIGRATE YOUR CUSTOM defaults.lua SETTINGS MANUALLY /!\\")
            defaults = {}
        end
    end

    for k, v in pairs(defaults) do
        -- Don't migrate deprecated settings
        if G_defaults:has(k) then
            G_defaults:saveSetting(k, v)
        end
    end
    -- Handle NETWORK_PROXY & STARDICT_DATA_DIR, which default to nil (and as such don't actually exist in G_defaults).
    G_defaults:saveSetting("NETWORK_PROXY", defaults.NETWORK_PROXY)
    G_defaults:saveSetting("STARDICT_DATA_DIR", defaults.STARDICT_DATA_DIR)

    G_defaults:flush()

    local archived_path = DataStorage:getDataDir() .. "/defaults.legacy.lua"
    local ok
    ok, err = os.rename(defaults_path, archived_path)
    if not ok then
       logger.warn("os.rename:", err)
    end
end

-- Extend the 20220205 hack to *all* the devices flagged as unreliable...
if last_migration_date < 20221027 then
    logger.info("Performing one-time migration for 20221027")

    local Device = require("device")
    if Device:isKobo() and not Device:hasReliableMxcWaitFor() then
        G_reader_settings:makeFalse("followed_link_marker")
    end
end

-- 20230531, Rename `strcoll_mixed` to `strcoll`+`collate_mixed`, https://github.com/koreader/koreader/pull/10198
if last_migration_date < 20230531 then
    logger.info("Performing one-time migration for 20230531")
    if G_reader_settings:readSetting("collate") == "strcoll_mixed" then
        G_reader_settings:saveSetting("collate", "strcoll")
        G_reader_settings:makeTrue("collate_mixed")
    end
end

-- 20230703, FileChooser Sort by: "date modified" only
if last_migration_date < 20230703 then
    logger.info("Performing one-time migration for 20230703")
    local collate = G_reader_settings:readSetting("collate")
    if collate == "modification" or collate == "access" or collate == "change" then
        G_reader_settings:saveSetting("collate", "date")
    end
end

-- 20230707, OPDS, no more special calibre catalog
if last_migration_date < 20230707 then
    logger.info("Performing one-time migration for 20230707")

    local calibre_opds = G_reader_settings:readSetting("calibre_opds")
    if calibre_opds and calibre_opds.host and calibre_opds.port then
        local opds_servers = G_reader_settings:readSetting("opds_servers") or {}
        table.insert(opds_servers, 1, {
            title    = _("Local calibre library"),
            url      = string.format("http://%s:%d/opds", calibre_opds.host, calibre_opds.port),
            username = calibre_opds.username,
            password = calibre_opds.password,
        })
       G_reader_settings:saveSetting("opds_servers", opds_servers)
       G_reader_settings:delSetting("calibre_opds")
    end
end

-- 20230710, Migrate to a full settings table, and disable KOSync's auto sync mode if wifi_enable_action is not turn_on
if last_migration_date < 20230710 then
    logger.info("Performing one-time migration for 20230710")

    -- c.f., PluginLoader
    local package_path = package.path
    package.path = string.format("%s/?.lua;%s", "plugins/kosync.koplugin", package_path)
    local ok, KOSync = pcall(dofile, "plugins/kosync.koplugin/main.lua")
    package.path = package_path
    if not ok or not KOSync then
        logger.warn("Error when loading plugins/kosync.koplugin/main.lua:", KOSync)
    else
        local settings = G_reader_settings:readSetting("kosync")
        if settings then
            -- Make sure the table is complete
            for k, v in pairs(KOSync.default_settings) do
                if settings[k] == nil then
                    settings[k] = v
                end
            end

            -- Migrate the whisper_* keys
            settings.sync_forward = settings.whisper_forward or KOSync.default_settings.sync_forward
            settings.whisper_forward = nil
            settings.sync_backward = settings.whisper_backward or KOSync.default_settings.sync_backward
            settings.whisper_backward = nil

            G_reader_settings:saveSetting("kosync", settings)
        end
    end

    local Device = require("device")
    if Device:hasWifiToggle() and G_reader_settings:readSetting("wifi_enable_action") ~= "turn_on" then
        local kosync = G_reader_settings:readSetting("kosync")
        if kosync and kosync.auto_sync then
            kosync.auto_sync = false
            G_reader_settings:saveSetting("kosync", kosync)
        end
    end
end

-- 20230731, aka., "let's kill all those stupid and weird mxcfb workarounds"
if last_migration_date < 20230731 then
    logger.info("Performing one-time migration for 20230731")

    local Device = require("device")
    if Device:isKobo() then
        if not Device:hasReliableMxcWaitFor() then
            G_reader_settings:delSetting("followed_link_marker")
        end
    end
end

-- 20230802, Statistics plugin null id_book in page_stat_data
if last_migration_date < 20230802 then
    logger.info("Performing one-time migration for 20230802")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if util.fileExists(db_location) then
        local conn = SQ3.open(db_location)
        local ok, value = pcall(conn.exec, conn, "PRAGMA table_info('page_stat_data')")
        if ok and value then
            -- Has table
            conn:exec("DELETE FROM page_stat_data WHERE id_book IS null;")
            local ok2, errmsg = pcall(conn.exec, conn, "VACUUM;")
            if not ok2 then
                logger.warn("Failed compacting statistics database when fixing null id_book:", errmsg)
            end
        else
            logger.warn("db not compatible when performing onetime migration:", ok, value)
        end
        conn:close()
    else
        logger.info("statistics.sqlite3 not found.")
    end
end

-- We're done, store the current migration date
G_reader_settings:saveSetting("last_migration_date", CURRENT_MIGRATION_DATE)
