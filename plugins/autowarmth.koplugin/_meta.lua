local _ = require("gettext")
return {
    name = "autowarmth",
    fullname = require("device"):hasNaturalLight() and _("Auto warmth and night mode") or _("Auto night mode"),
    description = _([[This plugin allows to set the frontlight warmth automagically.]]),
}
