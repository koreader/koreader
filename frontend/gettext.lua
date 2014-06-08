local isAndroid, android = pcall(require, "android")
local DEBUG = require("dbg")

local GetText = {
    translation = {},
    current_lang = "C",
    dirname = "l10n",
    textdomain = "koreader"
}

local GetText_mt = {
    __index = {}
}

function GetText_mt.__call(gettext, string)
    return gettext.translation[string] or string
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

-- for PO file syntax, see
-- https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html
-- we only implement a sane subset for now

function GetText_mt.__index.changeLang(new_lang)
    GetText.translation = {}
    GetText.current_lang = "C"

    -- the "C" locale disables localization alltogether
    if new_lang == "C" or new_lang == nil then return end

    -- strip encoding suffix in locale like "zh_CN.utf8"
    new_lang = new_lang:sub(1, new_lang:find(".%."))

    local file = GetText.dirname .. "/" .. new_lang .. "/" .. GetText.textdomain .. ".po"
    local po = io.open(file, "r")

    if not po then
        DEBUG("cannot open translation file " .. file)
        return
    end

    local data = {}
    local what = nil
    while true do
        local line = po:read("*l")
        if line == nil or line == "" then
            if data.msgid and data.msgstr and data.msgstr ~= "" then
                GetText.translation[data.msgid] = string.gsub(data.msgstr, "\\(.)", c_escape)
            end
            -- stop at EOF:
            if line == nil then break end
            data = {}
            what = nil
        else
            -- comment
            if not line:match("^#") then
                -- new data item (msgid, msgstr, ...
                local w, s = line:match("^%s*(%a+)%s+\"(.*)\"%s*$")
                if w then
                    what = w
                else
                    -- string continuation
                    s = line:match("^%s*\"(.*)\"%s*$")
                end
                if what and s then
                    data[what] = (data[what] or "") .. s
                end
            end
        end
    end
    GetText.current_lang = new_lang
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
    ffi.C.AConfiguration_getLanguage(android.app.config, buf)
    local lang = ffi.string(buf)
    ffi.C.AConfiguration_getCountry(android.app.config, buf)
    local country = ffi.string(buf)
    if lang and country then
        GetText.changeLang(lang.."_"..country)
    end
end

return GetText
