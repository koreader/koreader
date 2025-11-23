local _ = require("gettext")
return {
    name = "incompatible",
    fullname = _("Incompatible"),
    description = _([[This is a debugging plugin for incompatible plugins.]]),
    compatibility = {
        min_version = "v0000.1-1",
        max_version = "v9999.9-9",
    },
}
