local msg = require("plugindefs").deprecation_messages
local _ = require("gettext")

return {
    name = "exporter",
    fullname = _("Export highlights"),
    description = _("Exports highlights and notes."),
    deprecated = msg.feature .. "Flomo, Memos",
}
