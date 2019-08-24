local isAndroid, android = pcall(require, "android")
local logger = require("logger")

local GetText = {
    translation = {},
    current_lang = "C",
    dirname = "l10n",
    textdomain = "koreader",
    plural_default = "n != 1",
}

local GetText_mt = {
    __index = {}
}

function GetText_mt.__call(gettext, msgstr)
    return gettext.translation[msgstr] or msgstr
end

local function c_escape(what)
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
        return what
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
    -- something went wrong, abort, abort
    if not (#pl_tests+1 == tonumber(nplurals)) then
        logger.warn("GetText: using default plural function, declared and detected number of plurals don't match")
        return getDefaultPlural
    end
    -- the return function() stuff is a bit of loadstring trickery
    local plural_func_str = "return function(n) if "

    if #pl_tests > 1 then
        for i = 1, #pl_tests do
            local pl_test = pl_tests[i]
            pl_test = logicalCtoLua(pl_test)

            if i > 1 and not (tonumber(pl_test) ~= nil) then
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
        pl_test = logicalCtoLua(pl_test)
        plural_func_str = "return function(n) if "..pl_test.." then return 1 else return 0 end end"
    end
    return loadstring(plural_func_str)()
end

local function addTranslation(msgctxt, msgid, msgstr, n)
    -- translated string
    local unescaped_string = string.gsub(msgstr, "\\(.)", c_escape)
    if msgctxt and msgctxt ~= "" then
        if not GetText.context[msgctxt] then
            GetText.context[msgctxt] = {}
        end
        if n then
            if not GetText.context[msgctxt][msgid][n] then
                GetText.context[msgctxt][msgid][n] = {}
            end
            GetText.context[msgctxt][msgid][n] = unescaped_string
        else
            GetText.context[msgctxt][msgid] = unescaped_string
        end
    else
        if n then
            if not GetText.translation[msgid] then
                GetText.translation[msgid] = {}
            end
            GetText.translation[msgid][n] = unescaped_string
        else
            GetText.translation[msgid] = unescaped_string
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
                    local util = require("util")
                    headers = data.msgstr
                    local plural_forms = data.msgstr:match("Plural%-Forms: (.*);")
                    local nplurals = plural_forms:match("nplurals=([0-9]+);") or 2
                    local plurals = plural_forms:match("%((.*)%)")

                    if plurals:find("[^n!=%%<>&:%(%)|?0-9 ]") then
                        -- we don't trust this input, go with default instead
                        plurals = GetText.plural_default
                    end

                    local pl_tests = util.splitToArray(plurals, " : ")

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
                if what and s then
                    -- unescape \n or msgid won't match
                    s = s:gsub("\\n", "\n")
                    -- unescape " or msgid won't match
                    s = s:gsub('\\"', '"')
                    data[what] = (data[what] or "") .. s
                end
            end
        end
    end
    GetText.current_lang = new_lang
end

GetText_mt.__index.getPlural = getDefaultPlural

function GetText_mt.__index.ngettext(msgid, msgid_plural, n)
    local plural = GetText.getPlural(n)

    if plural == 0 then
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or msgid
    else
        return GetText.translation[msgid] and GetText.translation[msgid][plural] or msgid_plural
    end
end

function GetText_mt.__index.pgettext(msgctxt, msgid)
    return GetText.context[msgctxt] and GetText.context[msgctxt][msgid] or msgid
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
