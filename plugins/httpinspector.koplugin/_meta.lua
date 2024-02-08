local _ = require("gettext")
return {
    name = "httpinspector",
    fullname = _("HTTP KOReader Inspector"),
    description = _([[Allow browsing KOReader internal objects over HTTP. This is aimed at developpers, and may pose some security risks. Only enable this on networks you can trust.]]),
}
