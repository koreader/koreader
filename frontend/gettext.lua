
lua_gettext.init("./i18n", "koreader")


function _(string)
	return lua_gettext.translate(string)
end

function gettextChangeLang(new_lang)
	lua_gettext.change_lang(new_lang)
end
