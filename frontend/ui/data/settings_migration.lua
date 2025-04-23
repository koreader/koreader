--[[
Centralizes migration concerns for LuaSettings & DocSettings
--]]

local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local logger = require("logger")

local SettingsMigration = {}

-- Shockingly, handles settings migration
-- NOTE: supports LuaSettings & DocSettings objects as input, as both implement the same API
function SettingsMigration:migrateSettings(config)
    -- Figure out what kind of object we were passed, to make the logging more precise
    local cfg_mt_idx = getmetatable(config).__index
    local cfg_class
    if cfg_mt_idx == DocSettings then
        cfg_class = "book"
    elseif cfg_mt_idx == LuaSettings then
        cfg_class = "global"
    else
        -- Input object isn't a supported *Settings class, warn & abort instead of going kablooey.
        logger.warn("Passed an unsupported object class to SettingsMigration!")
        return
    end

    -- Fine-grained CRe margins (https://github.com/koreader/koreader/pull/4945)
    if config:has("copt_page_margins") then
        local old_margins = config:readSetting("copt_page_margins")
        logger.info("Migrating old", cfg_class, "CRe margin settings: L", old_margins[1], "T", old_margins[2], "R", old_margins[3], "B", old_margins[4])
        -- Format was: {left, top, right, bottom}
        config:saveSetting("copt_h_page_margins", {old_margins[1], old_margins[3]})
        config:saveSetting("copt_t_page_margin", old_margins[2])
        config:saveSetting("copt_b_page_margin", old_margins[4])
        -- Wipe it
        config:delSetting("copt_page_margins")
    end

    -- Space condensing to Word spacing (https://github.com/koreader/koreader/pull/5655)
    -- From a single number (space condensing) to a table of 2 numbers ({space width scale, space condensing}).
    -- Be conservative and don't change space width scale: use 100%
    if config:hasNot("copt_word_spacing") and config:has("copt_space_condensing") then
        local space_condensing = config:readSetting("copt_space_condensing")
        logger.info("Migrating old", cfg_class, "CRe space condensing:", space_condensing)
        config:saveSetting("copt_word_spacing", { 100, space_condensing })
    end

    if config:has("style_tweaks") then
        local tweaks = config:readSetting("style_tweaks")

        if tweaks then
            --            base hint
            --
            --          | n | t | f |
            --       ---+---+---+---+
            -- small  n | n | t | f |
            -- hint   t | t | t | t |
            --        f | f | t | f |
            --
            -- If either hint is true, enable the base hint to keep that type of footnote.
            -- Otherwise if one was false and the other nil or also false, we had a default
            -- that was disabled for the current book and want to keep it false.

            if tweaks["footnote-inpage_epub"] or tweaks["footnote-inpage_epub_smaller"] then
                tweaks["footnote-inpage_epub"] = true
            elseif tweaks["footnote-inpage_epub"] == false or tweaks["footnote-inpage_epub_smaller"] == false then
                tweaks["footnote-inpage_epub"] = false
            end
            if tweaks["footnote-inpage_wikipedia"] or tweaks["footnote-inpage_wikipedia_smaller"] then
                tweaks["footnote-inpage_wikipedia"] = true
            elseif tweaks["footnote-inpage_wikipedia"] == false or tweaks["footnote-inpage_wikipedia_smaller"] == false then
                tweaks["footnote-inpage_wikipedia"] = false
            end
            if tweaks["footnote-inpage_classic_classnames"] or tweaks["footnote-inpage_classic_classnames_smaller"] then
                tweaks["footnote-inpage_classic_classnames"] = true
            elseif tweaks["footnote-inpage_classic_classnames"] == false or tweaks["footnote-inpage_classic_classnames_smaller"] == false then
                tweaks["footnote-inpage_classic_classnames"] = false
            end

            local forced_size = false
            for __, pct in ipairs( { 100, 90, 85, 80, 75, 70, 65 } ) do
                if tweaks["inpage_footnote_font-size_" .. pct] then
                    forced_size = true
                end
            end
            if not forced_size
                and (tweaks["footnote-inpage_epub_smaller"]
                    or tweaks["footnote-inpage_wikipedia_smaller"]
                    or tweaks["footnote-inpage_classic_classnames_smaller"]
            ) then
                tweaks["inpage_footnote_font-size_smaller"] = true
            end

            tweaks["footnote-inpage_epub_smaller"] = nil
            tweaks["footnote-inpage_wikipedia_smaller"] = nil
            tweaks["footnote-inpage_classic_classnames_smaller"] = nil
        end
    end
end

return SettingsMigration
