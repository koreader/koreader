local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("json")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

-- We'll store the list of available dictionaries as a module local
-- so we only have to look for them on the first :init()
local available_ifos = nil
local lookup_history = nil

local function getIfosInDir(path)
    -- Get all the .ifo under directory path.
    -- We use the same logic as sdcv to walk directories and ifos files
    -- (so we get them in the order sdcv queries them) :
    -- - No sorting, entries are processed in the order the dir_read_name() call
    --   returns them (inodes linked list)
    -- - If entry is a directory, Walk in it first and recurse
    -- With a small optimisation to avoid walking dict subdirectories that
    -- may contain many images: if .ifo found, don't recurse subdirectories.
    local ifos = {}
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        local ifo_found = false
        local subdirs = {}
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." then
                local fullpath = path.."/"..name
                if fullpath:match("%.ifo$") then
                    table.insert(ifos, fullpath)
                    ifo_found = true
                elseif not ifo_found then -- don't check for dirs anymore if we found one .ifo
                    local attributes = lfs.attributes(fullpath)
                    if attributes ~= nil and attributes.mode == "directory" then
                        table.insert(subdirs, fullpath)
                    end
                end
            end
        end
        if not ifo_found and #subdirs > 0 then
            for _, subdir in pairs(subdirs) do
                local dirifos = getIfosInDir(subdir)
                for _, ifo in pairs(dirifos) do
                    table.insert(ifos, ifo)
                end
            end
        end
    end
    return ifos
end

local ReaderDictionary = InputContainer:new{
    data_dir = nil,
    dict_window_list = {},
    disable_lookup_history = G_reader_settings:isTrue("disable_lookup_history"),
    lookup_msg = _("Searching dictionary for:\n%1"),
}

local function readDictionaryCss(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()
    return content
end

function ReaderDictionary:init()
    self.ui.menu:registerToMainMenu(self)
    self.data_dir = os.getenv("STARDICT_DATA_DIR") or
        DataStorage:getDataDir() .. "/data/dict"

    -- Gather info about available dictionaries
    if not available_ifos then
        available_ifos = {}
        logger.dbg("Getting list of dictionaries")
        local ifo_files = getIfosInDir(self.data_dir)
        local dict_ext = self.data_dir.."_ext"
        if lfs.attributes(dict_ext, "mode") == "directory" then
            local extifos = getIfosInDir(dict_ext)
            for _, ifo in pairs(extifos) do
                table.insert(ifo_files, ifo)
            end
        end
        for _, ifo_file in pairs(ifo_files) do
            local f = io.open(ifo_file, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local dictname = content:match("\nbookname=(.-)\n")
                local is_html = content:find("sametypesequence=h", 1, true) ~= nil
                -- sdcv won't use dict that don't have a bookname=
                if dictname then
                    table.insert(available_ifos, {
                        file = ifo_file,
                        name = dictname,
                        is_html = is_html,
                        css = readDictionaryCss(ifo_file:gsub("%.ifo$", ".css"))
                    })
                end
            end
        end
        logger.dbg("found", #available_ifos, "dictionaries")

        if not G_reader_settings:readSetting("dicts_disabled") then
            -- Create an empty dict for this setting, so that we can
            -- access and update it directly through G_reader_settings
            -- and it will automatically be saved.
            G_reader_settings:saveSetting("dicts_disabled", {})
        end
    end
    -- Prepare the -u options to give to sdcv if some dictionaries are disabled
    self:updateSdcvDictNamesOptions()
    if not lookup_history then
        lookup_history = LuaData:open(DataStorage:getSettingsDir() .. "/lookup_history.lua", { name = "LookupHistory" })
    end
end

function ReaderDictionary:updateSdcvDictNamesOptions()
    -- We cannot tell sdcv which dictionaries to ignore, but we
    -- can tell it which dictionaries to use, by using multiple
    -- -u <dictname> options.
    -- (The order of the -u does not matter, and we can not use
    -- them for ordering queries and results)
    local dicts_disabled = G_reader_settings:readSetting("dicts_disabled")
    if not next(dicts_disabled) then
        -- no dict disabled, no need to use any -u option
        self.sdcv_dictnames_options_raw = nil
        self.sdcv_dictnames_options_escaped = nil
        return
    end
    local u_options_raw = {} -- for android call (individual unesscaped elements)
    local u_options_escaped = {} -- for other devices call via shell
    for _, ifo in pairs(available_ifos) do
        if not dicts_disabled[ifo.file] then
            table.insert(u_options_raw, "-u")
            table.insert(u_options_raw, ifo.name)
            -- Escape chars in dictname so it's ok for the shell command
            -- local u_esc = ("-u %q"):format(ifo.name)
            -- This may be safer than using lua's %q:
            local u_esc = "-u '" .. ifo.name:gsub("'", "'\\''") .. "'"
            table.insert(u_options_escaped, u_esc)
        end
        -- Note: if all dicts are disabled, we won't get any -u, and so
        -- all dicts will be queried.
    end
    self.sdcv_dictnames_options_raw = u_options_raw
    self.sdcv_dictnames_options_escaped = table.concat(u_options_escaped, " ")
end

function ReaderDictionary:addToMainMenu(menu_items)
    menu_items.dictionary_lookup = {
        text = _("Dictionary lookup"),
        tap_input = {
            title = _("Enter a word to look up"),
            ok_text = _("Search dictionary"),
            type = "text",
            callback = function(input)
                self:onLookupWord(input)
            end,
        },
    }
    menu_items.dictionary_lookup_history = {
        text = _("Dictionary lookup history"),
        enabled_func = function()
            return lookup_history:has("lookup_history")
        end,
        callback = function()
            local lookup_history_table = lookup_history:readSetting("lookup_history")
            local kv_pairs = {}
            local previous_title
            for i = #lookup_history_table, 1, -1 do
                local value = lookup_history_table[i]
                if value.book_title ~= previous_title then
                    table.insert(kv_pairs, { value.book_title..":", "" })
                end
                previous_title = value.book_title
                table.insert(kv_pairs, {
                    os.date("%Y-%m-%d %H:%M:%S", value.time),
                    value.word,
                    callback = function()
                        self:onLookupWord(value.word)
                    end
                })
            end
            UIManager:show(KeyValuePage:new{
                title = _("Dictionary lookup history"),
                kv_pairs = kv_pairs,
            })
        end,
    }
    menu_items.dictionary_settings = {
        text = _("Dictionary settings"),
        sub_item_table = {
            {
                text_func = function()
                    local nb_available, nb_enabled, nb_disabled = self:getNumberOfDictionaries()
                    local nb_str = nb_available
                    if nb_disabled > 0 then
                        nb_str = nb_enabled .. "/" .. nb_available
                    end
                    return T(_("Installed dictionaries (%1)"), nb_str)
                end,
                enabled_func = function()
                    return self:getNumberOfDictionaries() > 0
                end,
                sub_item_table = self:genDictionariesMenu(),
            },
            {
                text = _("Info on dictionary order"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[
If you'd like to change the order in which dictionaries are queried (and their results displayed), you can:
- move all dictionary directories out of %1.
- move them back there, one by one, in the order you want them to be used.]]), self.data_dir)
                    })
                end,
            },
            {
                text = _("Enable fuzzy search"),
                checked_func = function()
                    return not self.disable_fuzzy_search == true
                end,
                callback = function()
                    self.disable_fuzzy_search = not self.disable_fuzzy_search
                end,
                hold_callback = function()
                    self:makeDisableFuzzyDefault(self.disable_fuzzy_search)
                end,
                separator = true,
            },
            {
                text = _("Enable dictionary lookup history"),
                checked_func = function()
                    return not self.disable_lookup_history
                end,
                callback = function()
                    self.disable_lookup_history = not self.disable_lookup_history
                    G_reader_settings:saveSetting("disable_lookup_history", self.disable_lookup_history)
                end,
            },
            {
                text = _("Clean dictionary lookup history"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clean dictionary lookup history?"),
                        ok_text = _("Clean"),
                        ok_callback = function()
                            -- empty data table to replace current one
                            lookup_history:reset{}
                        end,
                    })
                end,
                separator = true,
            },
            { -- setting used by dictquicklookup
                text = _("Large window"),
                checked_func = function()
                    return G_reader_settings:isTrue("dict_largewindow")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("dict_largewindow")
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Justify text"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("dict_justify")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("dict_justify")
                end,
            }
        }
    }
end

function ReaderDictionary:onLookupWord(word, box, highlight, link)
    self.highlight = highlight
    -- Wrapped through Trapper, as we may be using Trapper:dismissablePopen() in it
    Trapper:wrap(function()
        self:stardictLookup(word, box, link)
    end)
    return true
end

--- Gets number of available, enabled, and disabled dictionaries
-- @treturn int nb_available
-- @treturn int nb_enabled
-- @treturn int nb_disabled
function ReaderDictionary:getNumberOfDictionaries()
    local nb_available = #available_ifos
    local nb_disabled = 0
    for _ in pairs(G_reader_settings:readSetting("dicts_disabled")) do
        nb_disabled = nb_disabled + 1
    end
    local nb_enabled = nb_available - nb_disabled
    return nb_available, nb_enabled, nb_disabled
end

function ReaderDictionary:genDictionariesMenu()
    local items = {}
    for _, ifo in pairs(available_ifos) do
        table.insert(items, {
            text = ifo.name,
            callback = function()
                local dicts_disabled = G_reader_settings:readSetting("dicts_disabled")
                if dicts_disabled[ifo.file] then
                    dicts_disabled[ifo.file] = nil
                else
                    dicts_disabled[ifo.file] = true
                end
                -- Update the -u options to give to sdcv
                self:updateSdcvDictNamesOptions()
            end,
            checked_func = function()
                local dicts_disabled = G_reader_settings:readSetting("dicts_disabled")
                return not dicts_disabled[ifo.file]
            end
        })
    end
    return items
end

local function dictDirsEmpty(dict_dirs)
    for _, dict_dir in ipairs(dict_dirs) do
        if not util.isEmptyDir(dict_dir) then
            return false
        end
    end
    return true
end

local function getAvailableIfoByName(dictionary_name)
    for _, ifo in ipairs(available_ifos) do
        if ifo.name == dictionary_name then
            return ifo
        end
    end

    return nil
end

local function tidyMarkup(results)
    local cdata_tag = "<!%[CDATA%[(.-)%]%]>"
    local format_escape = "&[29Ib%+]{(.-)}"
    for _, result in ipairs(results) do
        local ifo = getAvailableIfoByName(result.dict)
        if ifo and ifo.is_html then
            result.is_html = ifo.is_html
            result.css = ifo.css
        else
            local def = result.definition
            -- preserve the <br> tag for line break
            def = def:gsub("<[bB][rR] ?/?>", "\n")
            -- parse CDATA text in XML
            if def:find(cdata_tag) then
                def = def:gsub(cdata_tag, "%1")
                -- ignore format strings
                while def:find(format_escape) do
                    def = def:gsub(format_escape, "%1")
                end
            end
            -- ignore all markup tags
            def = def:gsub("%b<>", "")
            -- strip all leading empty lines/spaces
            def = def:gsub("^%s+", "")
            result.definition = def
        end
    end
    return results
end

function ReaderDictionary:cleanSelection(text)
    -- Will be used by ReaderWikipedia too
    if not text then
        return ""
    end
    -- crengine does now a much better job at finding word boundaries, but
    -- some cleanup is still needed for selection we get from other engines
    -- (example: pdf selection "qu’autrefois," will be cleaned to "autrefois")
    --
    -- Replace extended quote (included in the general puncturation range)
    -- with plain ascii quote (for french words like "aujourd’hui")
    text = string.gsub(text, "\xE2\x80\x99", "'") -- U+2019 (right single quotation mark)
    -- Strip punctuation characters around selection
    text = util.stripePunctuations(text)
    -- Strip some common english grammatical construct
    text = string.gsub(text, "'s$", '') -- english possessive
    -- Strip some common french grammatical constructs
    text = string.gsub(text, "^[LSDMNTlsdmnt]'", '') -- french l' s' t'...
    text = string.gsub(text, "^[Qq][Uu]'", '') -- french qu'
    -- Replace no-break space with regular space
    text = string.gsub(text, "\xC2\xA0", ' ') -- U+00A0 no-break space
    -- There may be a need to remove some (all?) diacritical marks
    -- https://en.wikipedia.org/wiki/Combining_character#Unicode_ranges
    -- see discussion at https://github.com/koreader/koreader/issues/1649
    -- Commented for now, will have to be checked by people who read
    -- languages and texts that use them.
    -- text = string.gsub(text, "\204[\128-\191]", '') -- U+0300 to U+033F
    -- text = string.gsub(text, "\205[\128-\175]", '') -- U+0340 to U+036F
    return text
end

function ReaderDictionary:showLookupInfo(word)
    local text = T(self.lookup_msg, word)
    self.lookup_progress_msg = InfoMessage:new{text=text}
    UIManager:show(self.lookup_progress_msg)
    UIManager:forceRePaint()
end

function ReaderDictionary:dismissLookupInfo()
    if self.lookup_progress_msg then
        UIManager:close(self.lookup_progress_msg)
        UIManager:forceRePaint()
    end
    self.lookup_progress_msg = nil
end

function ReaderDictionary:stardictLookup(word, box, link)
    logger.dbg("lookup word:", word, box)
    -- escape quotes and other funny characters in word
    word = self:cleanSelection(word)
    logger.dbg("stripped word:", word)
    if word == "" then
        return
    end

    if not self.disable_lookup_history then
        local book_title = self.ui.doc_settings and self.ui.doc_settings:readSetting("doc_props").title or _("Dictionary lookup")
        lookup_history:addTableItem("lookup_history", {
            book_title = book_title,
            time = os.time(),
            word = word,
        })
    end

    if not self.disable_fuzzy_search then
        self:showLookupInfo(word)
    end
    local final_results = {}
    local seen_results = {}
    -- Allow for two sdcv calls : one in the classic data/dict, and
    -- another one in data/dict_ext if it exists
    -- We could put in data/dict_ext dictionaries with a great number of words
    -- but poor definitions as a fall back. If these were in data/dict,
    -- they would prevent fuzzy searches in other dictories with better
    -- definitions, and masks such results. This way, we can get both.
    local dict_dirs = {self.data_dir}
    local dict_ext = self.data_dir.."_ext"
    if lfs.attributes(dict_ext, "mode") == "directory" then
        table.insert(dict_dirs, dict_ext)
    end
    -- early exit if no dictionaries
    if dictDirsEmpty(dict_dirs) then
        final_results = {
            {
                dict = "",
                word = word,
                definition = _([[No dictionaries installed. Please search for "Dictionary support" in the KOReader Wiki to get more information about installing new dictionaries.]]),
            }
        }
        self:showDict(word, final_results, box, link)
        return
    end
    local lookup_cancelled = false
    local common_options = self.disable_fuzzy_search and "-nje" or "-nj"
    for _, dict_dir in ipairs(dict_dirs) do
        if lookup_cancelled then
            break -- don't do any more lookup on additional dict_dirs
        end
        local results_str = nil
        if Device:isAndroid() then
            local A = require("android")
            local args = {"./sdcv", "--utf8-input", "--utf8-output", common_options, word, "--data-dir", dict_dir}
            if self.sdcv_dictnames_options_raw then
                for _, opt in pairs(self.sdcv_dictnames_options_raw) do
                    table.insert(args, opt)
                end
            end
            results_str = A.stdout(unpack(args))
        else
            local cmd = ("./sdcv --utf8-input --utf8-output %q %q --data-dir %q"):format(common_options, word, dict_dir)
            if self.sdcv_dictnames_options_escaped then
                cmd = cmd .. " " .. self.sdcv_dictnames_options_escaped
            end
            -- cmd = "sleep 7 ; " .. cmd     -- uncomment to simulate long lookup time

            if self.lookup_progress_msg then
                -- Some sdcv lookups, when using fuzzy search with many dictionaries
                -- and a really bad selected text, can take up to 10 seconds.
                -- It is nice to be able to cancel it when noticing wrong text was selected.
                -- As we have a lookup_progress_msg (that can be used to catch a tap
                -- and trigger cancellation), and because sdcv starts outputing its
                -- output only at the end when it has done its work, we can
                -- use Trapper:dismissablePopen() to cancel it as long as we are waiting
                -- for output.
                -- We must ensure we will have some output to be readable (if no
                -- definition found, sdcv will output some message on stderr, and
                -- let stdout empty) by appending an "echo":
                cmd = cmd .. "; echo"
                local completed
                completed, results_str = Trapper:dismissablePopen(cmd, self.lookup_progress_msg)
                lookup_cancelled = not completed
            else
                -- Fuzzy search disabled, usual option for people who don't want
                -- a "Looking up..." InfoMessage and usually fast: do a classic
                -- blocking io.popen()
                local std_out = io.popen(cmd, "r")
                if std_out then
                    results_str = std_out:read("*all")
                    std_out:close()
                end
            end
        end
        if results_str and results_str ~= "\n" then -- \n is when lookup was cancelled
            local ok, results = pcall(JSON.decode, results_str)
            if ok and results then
                -- we may get duplicates (sdcv may do multiple queries,
                -- in fixed mode then in fuzzy mode), we have to remove them
                local h
                for _,r in ipairs(results) do
                    h = r.dict .. r.word .. r.definition
                    if seen_results[h] == nil then
                        table.insert(final_results, r)
                        seen_results[h] = true
                    end
                end
            else
                logger.warn("JSON data cannot be decoded", results)
            end
        end
    end
    if #final_results == 0 then
        -- dummy results
        final_results = {
            {
                dict = "",
                word = word,
                definition = lookup_cancelled and _("Dictionary lookup canceled.") or _("No definition found."),
            }
        }
    end
    self:showDict(word, tidyMarkup(final_results), box, link)
end

function ReaderDictionary:showDict(word, results, box, link)
    self:dismissLookupInfo()
    if results and results[1] then
        logger.dbg("showing quick lookup window", word, results)
        self.dict_window = DictQuickLookup:new{
            window_list = self.dict_window_list,
            ui = self.ui,
            highlight = self.highlight,
            dialog = self.dialog,
            -- original lookup word
            word = word,
            -- selected link, if any
            selected_link = link,
            results = results,
            dictionary = self.default_dictionary,
            width = Screen:getWidth() - Screen:scaleBySize(80),
            word_box = box,
            -- differentiate between dict and wiki
            is_wiki = self.is_wiki,
            wiki_languages = self.wiki_languages,
            refresh_callback = function()
                if self.view then
                    -- update info in footer (time, battery, etc)
                    self.view.footer:updateFooter()
                end
            end,
        }
        table.insert(self.dict_window_list, self.dict_window)
        UIManager:show(self.dict_window)
    end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
    logger.dbg("make default dictionary:", dict)
    self.default_dictionary = dict
    UIManager:show(InfoMessage:new{
        text = T(_("%1 is now the default dictionary for this document."),
                 dict),
        timeout = 2,
    })
    return true
end

function ReaderDictionary:onReadSettings(config)
    self.default_dictionary = config:readSetting("default_dictionary")
    self.disable_fuzzy_search = config:readSetting("disable_fuzzy_search")
    if self.disable_fuzzy_search == nil then
        self.disable_fuzzy_search = G_reader_settings:isTrue("disable_fuzzy_search")
    end
end

function ReaderDictionary:onSaveSettings()
    logger.dbg("save default dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("disable_fuzzy_search", self.disable_fuzzy_search)
end

function ReaderDictionary:makeDisableFuzzyDefault(disable_fuzzy_search)
    logger.dbg("disable fuzzy search", self.disable_fuzzy_search)
    UIManager:show(ConfirmBox:new{
        text = T(
            disable_fuzzy_search
            and _("Disable fuzzy search by default?")
            or _("Enable fuzzy search by default?")
        ),
        ok_text = T(
            disable_fuzzy_search
            and _("Disable")
            or _("Enable")
        ),
        ok_callback = function()
            G_reader_settings:saveSetting("disable_fuzzy_search", disable_fuzzy_search)
        end,
    })
end

return ReaderDictionary
