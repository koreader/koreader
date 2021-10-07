local _ = require("gettext")
return {
    name = "japanese",
    fullname = _("Japanese Support"),
    description = _([[
Adds support to KoReader for Japanese-specific language handling to improve the
dictionary lookup system for Japanese text.

This plugin supports Yomichan-style deinflection and text scanning, allowing
you to far more easily look up words and phrases without having to manually
select the correct highlight and work around StarDict through the use of
synonym-based "deinflection" entries. You must have at least one Japanese
dictionary installed in order for this plugin to work.]]),
}
