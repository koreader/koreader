local _ = require("gettext")
return {
    name = "autowarmth",
    fullname = require("device"):hasNaturalLight() and _("Auto warmth and night mode") or _("Auto night mode"),
    description = require("device"):hasNaturalLight() and _([[This plugin allows to set the frontlight warmth and night mode automagically.]]) or _([[This plugin allows to enable night mode automagically.]]),
}
