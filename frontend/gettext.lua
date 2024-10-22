--[[--
A pure Lua implementation of a gettext subset.

Example:
    local _ = require("gettext")           -- @{gettext.gettext|gettext}()
    local C_ = _.pgettext                  -- @{pgettext}()
    local N_ = _.ngettext                  -- @{ngettext}()
    local NC_ = _.npgettext                -- @{npgettext}()
    local T = require("ffi/util").template -- @{ffi.util.template}()

    -- The most common use case with regular @{gettext.gettext|gettext}().
    local simple_string = _("item")

    -- A more complex example. The correct plural form will be automatically
    -- selected by @{ngettext}() based on the number.
    local numbered_string = T(N_("1 item", "%1 items", num_items), num_items)

It's required to pass along the number twice, because @{ngettext}() doesn't do anything with placeholders.
See @{ffi.util.template}() for more information about the template function.
--]]

local isAndroid, android = pcall(require, "android")
local logger = require("logger")

local GetText = {
    context = {},
    translation = {},
    current_lang = "C",
    dirname = "l10n",
    textdomain = "koreader",
    plural_default = "n != 1",
}

local GetText_mt = {
    __index = {}
}

-- wrapUntranslated() will be overridden by bidi.lua when UI language is RTL,
-- to wrap untranslated english strings as LTR-isolated segments.
-- It should do nothing when the UI language is LTR.
GetText.wrapUntranslated_nowrap = function(text) return text end
GetText.wrapUntranslated = GetText.wrapUntranslated_nowrap
-- Note: this won't be possible if we switch from our Lua GetText to
-- GetText through FFI (but hopefully, RTL languages will be fully
-- translated by then).

--[[--
Returns a translation.

@function gettext

@string msgid

@treturn string translation

@usage
    local _ = require("gettext")
    local translation = _("A meaningful message.")
--]]
function GetText_mt.__call(gettext, msgid)
    return gettext.translation[msgid] and gettext.translation[msgid][0] or gettext.translation[msgid] or gettext.wrapUntranslated(msgid)
end

local function c_escape(what_full, what)
    if what == "\n" then return ""
    elseif what == "a" then return "\a"
    elseif what == "b" then return "\b"
    elseif what == "f" then return "\f"
    elseif what == "n" then return "\n"
    elseif what == "r" then return "\r"
    elseif what == "t" then return "\t"
    elseif what == "v" then return "\v"
    elseif what == "0" then return "\0" -- shouldn't happen, though
    else
        return what_full
    end
end

--- Converts C logical operators to Lua.
local function logicalCtoLua(logical_str)
    logical_str = logical_str:gsub("&&", "and")
    logical_str = logical_str:gsub("!=", "~=")
    logical_str = logical_str:gsub("||", "or")
    return logical_str
end

--- Default getPlural function.
local function getDefaultPlural(n)
    if n ~= 1 then
        return 1
    else
        return 0
    end
end

--- Generates a proper Lua function out of logical gettext math tests.
local function getPluralFunc(pl_tests, nplurals, plural_default)
    -- the return function() stuff is a bit of loadstring trickery
    local plural_func_str = "return function(n) if "

    if #pl_tests > 1 then
        for i = 1, #pl_tests do
            local pl_test = pl_tests[i]
            pl_test = logicalCtoLua(pl_test)

            if i > 1 and tonumber(pl_test) == nil then
                pl_test = " elseif "..pl_test
            end
            if tonumber(pl_test) ~= nil then
                -- no condition, just a number
                pl_test = " else return "..pl_test
            end
            pl_test = pl_test:gsub("?", " then return")

            -- append to plural function
            plural_func_str = plural_func_str..pl_test
        end
        plural_func_str = plural_func_str.." end end"
    else
        local pl_test = pl_tests[1]
        -- Ensure JIT compiled function if we're dealing with one of the many simpler languages.
        -- After all, loadstring won't be.
        -- Potential workaround: write to file and use require.
        if pl_test == plural_default then
            return getDefaultPlural
        end
        -- language with no plural forms
        if tonumber(pl_test) ~= nil then
            plural_func_str = "return function(n) return "..pl_test.." end"
        else
            pl_test = logicalCtoLua(pl_test)
            plural_func_str = "return function(n) if "..pl_test.." then return 1 else return 0 end end"
        end
    end
    logger.dbg("gettext: plural function", plural_func_str)
    return loadstring(plural_func_str)()
end

local function addTranslation(msgctxt, msgid, msgstr, n)
    -- translated string
    local unescaped_string = string.gsub(msgstr, "(\\(.))", c_escape)
    if msgctxt and msgctxt ~= "" then
        if not GetText.context[msgctxt] then
            GetText.context[msgctxt] = {}
        end
        if n then
            if not GetText.context[msgctxt][msgid] then
                GetText.context[msgctxt][msgid] = {}
            end
            GetText.context[msgctxt][msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetText.context[msgctxt][msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    else
        if n then
            if not GetText.translation[msgid] then
                GetText.translation[msgid] = {}
            end
            GetText.translation[msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetText.translation[msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    end
end

-- for PO file syntax, see
-- https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html
-- we only implement a sane subset for now

function GetText_mt.__index.changeLang(new_lang)
    GetText.context = {}
    GetText.translation = {}
    GetText.current_lang = "C"

    -- the "C" locale disables localization altogether
    -- can be various things such as `en_US` or `en_US:en`
    if new_lang == "C" or new_lang == nil or new_lang == ""
       or new_lang:match("^en_US") == "en_US" then return end

    -- strip encoding suffix in locale like "zh_CN.utf8"
    new_lang = new_lang:sub(1, new_lang:find(".%."))

    local file = GetText.dirname .. "/" .. new_lang .. "/" .. GetText.textdomain .. ".po"
    local po = io.open(file, "r")

    if not po then
        logger.dbg("cannot open translation file:", file)
        return false
    end

    local data = {}
    local fuzzy = false
    local headers
    local what = nil
    while true do
        local line = po:read("*l")
        if line == nil or line == "" then
            if data.msgid and data.msgid_plural and data["msgstr[0]"] then
                for k, v in pairs(data) do
                    local n = tonumber(k:match("msgstr%[([0-9]+)%]"))
                    local msgstr = v

                    if n and msgstr then
                        addTranslation(data.msgctxt, data.msgid, msgstr, n)
                    end
                end
            elseif data.msgid and data.msgstr and data.msgstr ~= "" then
                -- header
                if not headers and data.msgid == "" then
                    headers = data.msgstr
                    local plural_forms = data.msgstr:match("Plural%-Forms: (.*)")
                    local nplurals = plural_forms:match("nplurals=([0-9]+);") or 2
                    local plurals = plural_forms:match("plural=%((.*)%);")

                    -- Hardcoded workaround for Hebrew which has 4 plural forms.
                    if plurals == "n == 1) ? 0 : ((n == 2) ? 1 : ((n > 10 && n % 10 == 0) ? 2 : 3)" then
                        plurals = "n == 1 ? 0 : (n == 2) ? 1 : (n > 10 && n % 10 == 0) ? 2 : 3"
                    end
                    -- Hardcoded workaround for Latvian.
                    if plurals == "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19) ? 0 : ((n % 10 == 1 && n % 100 != 11) ? 1 : 2" then
                        plurals = "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19 ? 0 : (n % 10 == 1 && n % 100 != 11) ? 1 : 2"
                    end
                    -- Hardcoded workaround for Romanian which has 3 plural forms.
                    if plurals == "n == 1) ? 0 : ((n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2" then
                        plurals = "n == 1 ? 0 : (n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2"
                    end

                    if not plurals then
                        -- Some languages (e.g., Arabic) may not use parentheses.
                        -- However, the following more inclusive match is more likely
                        -- to accidentally include junk and seldom relevant.
                        -- We might also be dealing with a language without plurals.
                        -- That would look like `plural=0`.
                        plurals = plural_forms:match("plural=(.*);")
                    end

                    if plurals:find("[^n!=%%<>&:%(%)|?0-9 ]") then
                        -- we don't trust this input, go with default instead
                        plurals = GetText.plural_default
                    end

                    local pl_tests = {}
                    for pl_test in plurals:gmatch("[^:]+") do
                        table.insert(pl_tests, pl_test)
                    end

                    GetText.getPlural = getPluralFunc(pl_tests, nplurals, GetText.plural_default)
                    if not GetText.getPlural then
                        GetText.getPlural = getDefaultPlural
                    end
                end

                addTranslation(data.msgctxt, data.msgid, data.msgstr)
            end
            -- stop at EOF:
            if line == nil then break end
            data = {}
            what = nil
        else
            -- comment
            if not line:match("^#") then
                -- new data item (msgid, msgstr, ...
                local w, s = line:match("^%s*([%a_%[%]0-9]+)%s+\"(.*)\"%s*$")
                if w then
                    what = w
                else
                    -- string continuation
                    s = line:match("^%s*\"(.*)\"%s*$")
                end
                if what and s and not fuzzy then
                    -- unescape \n or msgid won't match
                    s = s:gsub("\\n", "\n")
                    -- unescape " or msgid won't match
                    s = s:gsub('\\"', '"')
                    -- unescape \\ or msgid won't match
                    s = s:gsub("\\\\", "\\")
                    data[what] = (data[what] or "") .. s
                elseif what and s == "" and fuzzy then -- luacheck: ignore 542
                    -- Ignore the likes of msgid "" and msgstr ""
                else
                    -- Don't save this fuzzy string and unset fuzzy for the next one.
                    fuzzy = false
                end
            elseif line:match("#, fuzzy") then
                fuzzy = true
            end
        end
    end
    po:close()
    GetText.current_lang = new_lang
end

GetText_mt.__index.getPlural = getDefaultPlural

--[[--
Returns a plural form.

Many languages have more forms than just singular and plural. This function
abstracts the complexity away. The translation can contain as many
pluralizations as it requires.

See [gettext plural forms](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html)
and [translating plural forms](https://www.gnu.org/software/gettext/manual/html_node/Translating-plural-forms.html)
for more information.

It's required to pass along the number twice, because @{ngettext}() doesn't do anything with placeholders.
See @{ffi.util.template}() for more information about the template function.

@function ngettext

@string msgid
@string msgid_plural
@int n

@treturn string translation

@usage
    local _ = require("gettext")
    local N_ = _.ngettext
    local T = require("ffi/util").template

    local items_string = T(N_("1 item", "%1 items", num_items), num_items)
--]]
function GetText_mt.__index.ngettext(msgid, msgid_plural, n)
    local plural = GetText.getPlural(n)

    if plural == 0 then
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or GetText.wrapUntranslated(msgid)
    else
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or GetText.wrapUntranslated(msgid_plural)
    end
end

--[[--
Returns a context-disambiguated plural form.

This is the logical combination between @{ngettext}() and @{pgettext}().
Please refer there for more information.

@function npgettext

@string msgctxt
@string msgid
@string msgid_plural
@int n

@treturn string translation

@usage
    local _ = require("gettext")
    local NC_ = _.npgettext
    local T = require("ffi/util").template

    local statistics_items_string = T(NC_("Statistics", "1 item", "%1 items", num_items), num_items)
    local books_items_string = T(NC_("Books", "1 item", "%1 items", num_items), num_items)
--]]
function GetText_mt.__index.npgettext(msgctxt, msgid, msgid_plural, n)
    local plural = GetText.getPlural(n)

    if plural == 0 then
        return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] and GetText.context[msgctxt][msgid][plural] or GetText.wrapUntranslated(msgid)
    else
        return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] and GetText.context[msgctxt][msgid][plural] or GetText.wrapUntranslated(msgid_plural)
    end
end

--[[--
Returns a context-disambiguated translation.

The same string might occur multiple times, but require a different translation based on context.
An example within KOReader is **Pages** meaning *page styles* (within the context of style tweaks)
and **Pages** meaning *number of pages*.

We generally don't apply context unless a conflict is known. This is only likely to occur with
short strings, of which of course there are many.

See [gettext contexts](https://www.gnu.org/software/gettext/manual/html_node/Contexts.html) for more information.

@function pgettext

@string msgctxt
@string msgid

@treturn string translation

@usage
    local _ = require("gettext")
    local C_ = _.pgettext

    local copy_file = C_("File", "Copy")
    local copy_text = C_("Text", "Copy")
--]]
function GetText_mt.__index.pgettext(msgctxt, msgid)
    return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] or GetText.wrapUntranslated(msgid)
end

setmetatable(GetText, GetText_mt)

if os.getenv("LANGUAGE") then
    GetText.changeLang(os.getenv("LANGUAGE"))
elseif os.getenv("LC_ALL") then
    GetText.changeLang(os.getenv("LC_ALL"))
elseif os.getenv("LC_MESSAGES") then
    GetText.changeLang(os.getenv("LC_MESSAGES"))
elseif os.getenv("LANG") then
    GetText.changeLang(os.getenv("LANG"))
end

if isAndroid then
    local ffi = require("ffi")
    local buf = ffi.new("char[?]", 16)
    android.lib.AConfiguration_getLanguage(android.app.config, buf)
    local lang = ffi.string(buf)
    android.lib.AConfiguration_getCountry(android.app.config, buf)
    local country = ffi.string(buf)
    if lang and country then
        GetText.changeLang(lang.."_"..country)
    end
end

return GetText
