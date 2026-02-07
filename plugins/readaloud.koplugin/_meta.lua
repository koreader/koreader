local _ = require("gettext")

return {
    name = "readaloud",
    fullname = _("Read aloud"),
    description = _([[Reads the current page aloud using Android Text-to-Speech.

Offline support depends on the installed system TTS engine and voice data.]]),
}
