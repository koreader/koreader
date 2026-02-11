local _ = require("gettext")

return {
    name = "readaloud",
    fullname = _("Read aloud"),
    description = _([[Reads the current page aloud using text-to-speech.

Offline support depends on the installed system text-to-speech engine and voice data.]]),
}
