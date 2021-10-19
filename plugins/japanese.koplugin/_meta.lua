local _ = require("gettext")
return {
    name = "japanese",
    fullname = _("Japanese support"),
    description = _([[
Japanese language support for KOReader, modeled after Yomichan.

This plugin extends KOReader's built-in dictionary and selection system to support Yomichan-style deinflection and text scanning, allowing for one-tap searches of inflected verbs and multi-character words and phrases. As such, this plugin removes the need for synonym-based deinflection rules for StarDict-converted Japanese dictionaries.

You must have at least one Japanese dictionary installed in order for this plugin to work smoothly with Japanese text.]]),
}
