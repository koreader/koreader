local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ffiUtil  = require("ffi/util")
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
    -- Don't walk into "res/" subdirectories, as per Stardict specs, they
    -- may contain possibly many resource files (image, audio files...)
    -- that could slow down our walk here.
    local ifos = {}
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." and name ~= "res" then
                local fullpath = path.."/"..name
                local attributes = lfs.attributes(fullpath)
                if attributes ~= nil then
                    if attributes.mode == "directory" then
                        local dirifos = getIfosInDir(fullpath) -- recurse
                        for _, ifo in pairs(dirifos) do
                            table.insert(ifos, ifo)
                        end
                    elseif fullpath:match("%.ifo$") then
                        table.insert(ifos, fullpath)
                    end
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

-- For a HTML dict, one can specify a specific stylesheet
-- in a file named as the .ifo with a .css extension
local function readDictionaryCss(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()
    return content
end

-- For a HTML dict, one can specify a function called on
-- the raw returned definition to "fix" the HTML if needed
-- (as MuPDF, used for rendering, is quite sensitive to the
-- HTML quality) in a file named as the .ifo with a .lua
-- extension, containing for example:
--    return function(html)
--        html = html:gsub("<hr>", "<hr/>")
--        return html
--    end
local function getDictionaryFixHtmlFunc(path)
    if lfs.attributes(path, "mode") == "file" then
        local ok, func = pcall(dofile, path)
        if ok and func then
            return func
        else
            logger.warn("Dict's user provided file failed:", func)
        end
    end
end

function ReaderDictionary:init()
    self.ui.menu:registerToMainMenu(self)
    self.data_dir = STARDICT_DATA_DIR or
        os.getenv("STARDICT_DATA_DIR") or
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
                        css = readDictionaryCss(ifo_file:gsub("%.ifo$", ".css")),
                        fix_html_func = getDictionaryFixHtmlFunc(ifo_file:gsub("%.ifo$", ".lua")),
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
    self.enabled_dict_names = nil

    -- We cannot tell sdcv which dictionaries to ignore, but we
    -- can tell it which dictionaries to use, by using multiple
    -- -u <dictname> options.
    -- (The order of the -u does not matter, and we can not use
    -- them for ordering queries and results)
    local dicts_disabled = G_reader_settings:readSetting("dicts_disabled")
    if not next(dicts_disabled) then
        return
    end
    for _, ifo in pairs(available_ifos) do
        if not dicts_disabled[ifo.file] then
            if not self.enabled_dict_names then
                self.enabled_dict_names = {}
            end
            table.insert(self.enabled_dict_names, ifo.name)
        end
    end
end

function ReaderDictionary:addToMainMenu(menu_items)
    menu_items.dictionary_lookup = {
        text = _("Dictionary lookup"),
        callback = function()
            self:onShowDictionaryLookup()
        end,
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
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[
If you'd like to change the order in which dictionaries are queried (and their results displayed), you can:
- move all dictionary directories out of %1.
- move them back there, one by one, in the order you want them to be used.]]), BD.dirpath(self.data_dir))
                    })
                end,
            },
            {
                text = _("Download dictionaries"),
                sub_item_table = self:_genDownloadDictionariesMenu()
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
                    self:toggleFuzzyDefault()
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
                keep_menu_open = true,
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
            },
            { -- setting used by dictquicklookup
                text_func = function()
                    local font_size = G_reader_settings:readSetting("dict_font_size") or 20
                    return T(_("Font size (%1)"), font_size)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local font_size = G_reader_settings:readSetting("dict_font_size") or 20
                    local items_font = SpinWidget:new{
                        width = Screen:getWidth() * 0.6,
                        value = font_size,
                        value_min = 8,
                        value_max = 32,
                        default_value = 20,
                        ok_text = _("Set size"),
                        title_text =  _("Dictionary font size"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("dict_font_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            }
        }
    }
    if Device:canExternalDictLookup() then
        local function genExternalDictItems()
            local items_table = {}
            for i, v in ipairs(Device:getExternalDictLookupList()) do
                local setting = v[1]
                local dict_name = v[2]
                local is_enabled = v[3]
                table.insert(items_table, {
                    text = dict_name,
                    checked_func = function()
                        return setting == G_reader_settings:readSetting("external_dict_lookup_method")
                    end,
                    enabled_func = function()
                        return is_enabled == true
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("external_dict_lookup_method", v[1])
                    end,
                })
            end
            return items_table
        end
        table.insert(menu_items.dictionary_settings.sub_item_table, 1, {
            text = _("Use external dictionary"),
            checked_func = function()
                return G_reader_settings:isTrue("external_dict_lookup")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("external_dict_lookup")
            end,
        })
        table.insert(menu_items.dictionary_settings.sub_item_table, 2, {
            text_func = function()
                local display_name = _("none")
                local ext_id = G_reader_settings:readSetting("external_dict_lookup_method")
                for i, v in ipairs(Device:getExternalDictLookupList()) do
                    if v[1] == ext_id then
                        display_name = v[2]
                        break
                    end
                end
                return T(_("Dictionary: %1"), display_name)
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("external_dict_lookup")
            end,
            sub_item_table = genExternalDictItems(),
            separator = true,
        })
    end
end

function ReaderDictionary:onLookupWord(word, box, highlight, link)
    logger.dbg("dict lookup word:", word, box)
    -- escape quotes and other funny characters in word
    word = self:cleanSelection(word)
    logger.dbg("dict stripped word:", word)

    self.highlight = highlight

    -- Wrapped through Trapper, as we may be using Trapper:dismissablePopen() in it
    Trapper:wrap(function()
        self:stardictLookup(word, self.enabled_dict_names, not self.disable_fuzzy_search, box, link)
    end)
    return true
end

function ReaderDictionary:onHtmlDictionaryLinkTapped(dictionary, link)
    if not link.uri then
        return
    end

    -- The protocol is either "bword" or there is no protocol, only the word.
    -- https://github.com/koreader/koreader/issues/3588#issuecomment-357088125
    local url_prefix = "bword://"
    local word
    if link.uri:sub(1,url_prefix:len()) == url_prefix then
        word = link.uri:sub(url_prefix:len() + 1)
    elseif link.uri:find("://") then
        return
    else
        word = link.uri
    end

    if word == "" then
        return
    end

    local link_box = Geom:new{
        x = link.x0,
        y = link.y0,
        w = math.abs(link.x1 - link.x0),
        h = math.abs(link.y1 - link.y0),
    }

    -- Only the first dictionary window stores the highlight, this way the highlight
    -- is only removed when there are no more dictionary windows open.
    self.highlight = nil

    -- Wrapped through Trapper, as we may be using Trapper:dismissablePopen() in it
    Trapper:wrap(function()
        self:stardictLookup(word, {dictionary}, false, link_box, nil)
    end)
end

--- Gets number of available, enabled, and disabled dictionaries
-- @treturn int nb_available
-- @treturn int nb_enabled
-- @treturn int nb_disabled
function ReaderDictionary:getNumberOfDictionaries()
    local nb_available = #available_ifos
    local nb_enabled = 0
    local nb_disabled = 0
    local dicts_disabled = G_reader_settings:readSetting("dicts_disabled")
    for _, ifo in pairs(available_ifos) do
        if dicts_disabled[ifo.file] then
            nb_disabled = nb_disabled + 1
        else
            nb_enabled = nb_enabled + 1
        end
    end
    return nb_available, nb_enabled, nb_disabled
end

function ReaderDictionary:_genDownloadDictionariesMenu()
    local downloadable_dicts = require("ui/data/dictionaries")
    local languages = {}

    for i = 1, #downloadable_dicts do
        local dict = downloadable_dicts[i]
        local dict_lang_in = dict.lang_in
        local dict_lang_out = dict.lang_out
        if not languages[dict_lang_in] then
            languages[dict_lang_in] = {}
        end
        table.insert(languages[dict_lang_in], dict)
        if not languages[dict_lang_out] then
            languages[dict_lang_out] = {}
        end
        table.insert(languages[dict_lang_out], dict)
    end

    -- remove duplicates
    for lang_key,lang in pairs(languages) do
        local hash = {}
        local res = {}
        for k,v in ipairs(lang) do
           if not hash[v.name] then
               res[#res+1] = v
               hash[v.name] = true
           end
        end
        languages[lang_key] = res
    end

    local menu_items = {}
    for lang_key, available_langs in ffiUtil.orderedPairs(languages) do
        table.insert(menu_items, {
            keep_menu_open = true,
            text = lang_key,
            callback = function()
                self:showDownload(available_langs)
            end
        })
    end

    return menu_items
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
            if ifo.fix_html_func then
                local ok, fixed_definition = pcall(ifo.fix_html_func, result.definition)
                if ok then
                    result.definition = fixed_definition
                else
                    logger.warn("Dict's user provided funcion failed:", fixed_definition)
                end
            end
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
            -- convert any htmlentities (&gt;, &quot;...)
            def = util.htmlEntitiesToUtf8(def)
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
    -- Trim any space at start or end
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    -- Replace extended quote (included in the general puncturation range)
    -- with plain ascii quote (for french words like "aujourd’hui")
    text = text:gsub("\xE2\x80\x99", "'") -- U+2019 (right single quotation mark)
    -- Strip punctuation characters around selection
    text = util.stripPunctuation(text)
    -- Strip some common english grammatical construct
    text = text:gsub("'s$", '') -- english possessive
    -- Strip some common french grammatical constructs
    text = text:gsub("^[LSDMNTlsdmnt]'", '') -- french l' s' t'...
    text = text:gsub("^[Qq][Uu]'", '') -- french qu'
    -- Replace no-break space with regular space
    text = text:gsub("\xC2\xA0", ' ') -- U+00A0 no-break space
    -- There may be a need to remove some (all?) diacritical marks
    -- https://en.wikipedia.org/wiki/Combining_character#Unicode_ranges
    -- see discussion at https://github.com/koreader/koreader/issues/1649
    -- Commented for now, will have to be checked by people who read
    -- languages and texts that use them.
    -- text = text:gsub("\204[\128-\191]", '') -- U+0300 to U+033F
    -- text = text:gsub("\205[\128-\175]", '') -- U+0340 to U+036F
    -- Trim any space now at start or end after above changes
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
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
        -- UIManager:forceRePaint()
    end
    self.lookup_progress_msg = nil
end

function ReaderDictionary:onShowDictionaryLookup()
    self.dictionary_lookup_dialog = InputDialog:new{
        title = _("Enter a word to look up"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.dictionary_lookup_dialog)
                    end,
                },
                {
                    text = _("Search dictionary"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(self.dictionary_lookup_dialog)
                        self:onLookupWord(self.dictionary_lookup_dialog:getInputText())
                    end,
                },
            }
        },
    }
    UIManager:show(self.dictionary_lookup_dialog)
    self.dictionary_lookup_dialog:onShowKeyboard()
    return true
end

function ReaderDictionary:startSdcv(word, dict_names, fuzzy_search)
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
        return final_results
    end
    local lookup_cancelled = false
    for _, dict_dir in ipairs(dict_dirs) do
        if lookup_cancelled then
            break -- don't do any more lookup on additional dict_dirs
        end

        local args = {"./sdcv", "--utf8-input", "--utf8-output", "--json-output", "--non-interactive", "--data-dir", dict_dir, word}
        if not fuzzy_search then
            table.insert(args, "--exact-search")
        end
        if dict_names then
            for _, opt in pairs(dict_names) do
                table.insert(args, "-u")
                table.insert(args, opt)
            end
        end

        local cmd = util.shell_escape(args)
        -- cmd = "sleep 7 ; " .. cmd     -- uncomment to simulate long lookup time

        -- Some sdcv lookups, when using fuzzy search with many dictionaries
        -- and a really bad selected text, can take up to 10 seconds.
        -- It is nice to be able to cancel it when noticing wrong text was
        -- selected.
        -- Because sdcv starts outputing its output only at the end when it has
        -- done its work, we can use Trapper:dismissablePopen() to cancel it as
        -- long as we are waiting for output.
        -- When fuzzy search is enabled, we have a lookup_progress_msg that can
        -- be used to catch a tap and trigger cancellation.
        -- When fuzzy search is disabled, we provide false instead so an
        -- invisible non-event-forwarding TrapWidget is used to catch a tap
        -- and trigger cancellation (invisible so there's no need for repaint
        -- and refresh with the usually fast non-fuzzy search lookups).
        -- We must ensure we will have some output to be readable (if no
        -- definition found, sdcv will output some message on stderr, and
        -- let stdout empty) by appending an "echo":
        cmd = cmd .. "; echo"
        local completed, results_str = Trapper:dismissablePopen(cmd, self.lookup_progress_msg or false)
        lookup_cancelled = not completed

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

    return final_results
end

function ReaderDictionary:stardictLookup(word, dict_names, fuzzy_search, box, link)
    if word == "" then
        return
    end

    if not self.disable_lookup_history then
        local book_title = self.ui.doc_settings and self.ui.doc_settings:readSetting("doc_props").title or _("Dictionary lookup")
        if book_title == "" then -- no or empty metadata title
            if self.ui.document and self.ui.document.file then
                local directory, filename = util.splitFilePathName(self.ui.document.file) -- luacheck: no unused
                book_title = util.splitFileNameSuffix(filename)
            end
        end
        lookup_history:addTableItem("lookup_history", {
            book_title = book_title,
            time = os.time(),
            word = word,
        })
    end

    if Device:canExternalDictLookup() and G_reader_settings:isTrue("external_dict_lookup") then
        Device:doExternalDictLookup(word, G_reader_settings:readSetting("external_dict_lookup_method"), function()
            if self.highlight then
                local clear_id = self.highlight:getClearId()
                UIManager:scheduleIn(0.5, function()
                    self.highlight:clear(clear_id)
                end)
            end
        end)
        return
    end

    if fuzzy_search then
        self:showLookupInfo(word)
    end

    local results = self:startSdcv(word, dict_names, fuzzy_search)
    self:showDict(word, tidyMarkup(results), box, link)
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
            html_dictionary_link_tapped_callback = function(dictionary, html_link)
                self:onHtmlDictionaryLinkTapped(dictionary, html_link)
            end,
        }
        table.insert(self.dict_window_list, self.dict_window)
        UIManager:show(self.dict_window)
    end
end

function ReaderDictionary:showDownload(downloadable_dicts)
    local kv_pairs = {}
    for dummy, dict in ipairs(downloadable_dicts) do
        table.insert(kv_pairs, {dict.name, "",
            callback = function()
                if not NetworkMgr:isOnline() then
                    NetworkMgr:promptWifiOn()
                    return
                end
                self:downloadDictionaryPrep(dict)
            end})
        local lang
        if dict.lang_in == dict.lang_out then
            lang = string.format("    %s", dict.lang_in)
        else
            lang = string.format("    %s–%s", dict.lang_in, dict.lang_out)
        end
        table.insert(kv_pairs, {lang, ""})
        table.insert(kv_pairs, {"    ".._("License"), dict.license})
        table.insert(kv_pairs, {"    ".._("Entries"), dict.entries})
        table.insert(kv_pairs, "----------------------------")
    end
    self.download_window = KeyValuePage:new{
        title = _("Tap dictionary name to download"),
        kv_pairs = kv_pairs,
    }
    UIManager:show(self.download_window)
end

function ReaderDictionary:downloadDictionaryPrep(dict, size)
    local dummy, filename = util.splitFilePathName(dict.url)
    local download_location = string.format("%s/%s", self.data_dir, filename)

    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(download_location) then
        UIManager:show(ConfirmBox:new{
            text =  _("File already exists. Overwrite?"),
            ok_text =  _("Overwrite"),
            ok_callback = function()
                self:downloadDictionary(dict, download_location)
            end,
        })
    else
        self:downloadDictionary(dict, download_location)
    end
end

function ReaderDictionary:downloadDictionary(dict, download_location, continue)
    continue = continue or false
    local socket = require("socket")
    local http = socket.http
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local url = socket.url

    local parsed = url.parse(dict.url)
    local httpRequest = parsed.scheme == "http" and http.request or https.request

    if not continue then
        local file_size
        --local r, c, h = httpRequest {
        local dummy, headers, dummy = socket.skip(1, httpRequest{
            method = "HEAD",
            url = dict.url,
            --redirect = true,
        })
        --logger.dbg(status)
        --logger.dbg(headers)
        --logger.dbg(code)
        file_size = headers and headers["content-length"]

        UIManager:show(ConfirmBox:new{
            text =  T(_("Dictionary filesize is %1 (%2 bytes). Continue with download?"), util.getFriendlySize(file_size), util.getFormattedSize(file_size)),
            ok_text =  _("Download"),
            ok_callback = function()
                -- call ourselves with continue = true
                self:downloadDictionary(dict, download_location, true)
            end,
        })
        return
    else
        UIManager:nextTick(function()
            UIManager:show(InfoMessage:new{
                text = _("Downloading…"),
                timeout = 3,
            })
        end)
    end

    local dummy, c, dummy = httpRequest{
        url = dict.url,
        sink = ltn12.sink.file(io.open(download_location, "w")),
    }
    if c == 200 then
        logger.dbg("file downloaded to", download_location)
    else
        UIManager:show(InfoMessage:new{
            text = _("Could not save file to:\n") .. BD.filepath(download_location),
            --timeout = 3,
        })
        return false
    end

    local ok, error = util.unpackArchive(download_location, self.data_dir)

    if ok then
        available_ifos = false
        self:init()
        UIManager:show(InfoMessage:new{
            text = _("Dictionary downloaded:\n") .. dict.name,
        })
        return true
    else
        UIManager:show(InfoMessage:new{
            text = _("Dictionary failed to download:\n") .. string.format("%s\n%s", dict.name, error),
        })
        return false
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
    if self.ui.doc_settings then
        logger.dbg("save default dictionary", self.default_dictionary)
        self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
        self.ui.doc_settings:saveSetting("disable_fuzzy_search", self.disable_fuzzy_search)
    end
end

function ReaderDictionary:toggleFuzzyDefault()
    local disable_fuzzy_search = G_reader_settings:isTrue("disable_fuzzy_search")
    UIManager:show(MultiConfirmBox:new{
        text = T(
            disable_fuzzy_search
            and _([[
Would you like to enable or disable fuzzy search by default?

Fuzzy search can match epuisante, épuisante and épuisantes to épuisant, even if only the latter has an entry in the dictionary. It can be disabled to improve performance, but it might be worthwhile to look into disabling unneeded dictionaries before disabling fuzzy search.

The current default (★) is disabled.]])
            or _([[
Would you like to enable or disable fuzzy search by default?

Fuzzy search can match epuisante, épuisante and épuisantes to épuisant, even if only the latter has an entry in the dictionary. It can be disabled to improve performance, but it might be worthwhile to look into disabling unneeded dictionaries before disabling fuzzy search.

The current default (★) is enabled.]])
        ),
        choice1_text_func =  function()
            return disable_fuzzy_search and _("Disable (★)") or _("Disable")
        end,
        choice1_callback = function()
            G_reader_settings:saveSetting("disable_fuzzy_search", true)
        end,
        choice2_text_func = function()
            return disable_fuzzy_search and _("Enable") or _("Enable (★)")
        end,
        choice2_callback = function()
            G_reader_settings:saveSetting("disable_fuzzy_search", false)
        end,
    })
end

return ReaderDictionary
