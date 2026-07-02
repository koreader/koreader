local _ = require("gettext")

return {
    name = "text2speech",
    fullname = _("Text-to-speech"),
    description = _([[Reads the current page aloud using text-to-speech.

Offline support depends on the installed system text-to-speech engine and voice data.]]),
}
