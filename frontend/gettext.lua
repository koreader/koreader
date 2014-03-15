lua_gettext.init("./i18n", "koreader")

local GetText = {}
local GetText_mt = {}

function GetText_mt.__call(gettext, string)
    return lua_gettext.translate(string)
end

function GetText.changeLang(new_lang)
    lua_gettext.change_lang(new_lang)
end

setmetatable(GetText, GetText_mt)

return GetText
