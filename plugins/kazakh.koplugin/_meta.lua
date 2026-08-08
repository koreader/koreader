local _ = require("gettext")
return {
    fullname = _("Kazakh support"),
    description = _([[
Kazakh language support for KOReader.

Kazakh is agglutinative: a word like "мектептерімізде" carries plural, possessive and locative endings on top of the root "мектеп". Dictionaries are keyed on the root, so tapping an inflected word in a book normally finds nothing, and fuzzy search does not help because it measures spelling distance rather than morphology.

This plugin analyses the tapped word and offers every morphologically legal dictionary form to the dictionary, which then returns whichever ones actually exist.

You must have at least one Kazakh dictionary installed for this plugin to be useful.]]),
}
