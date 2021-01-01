local _ = require("gettext")
return {
    name = "goodreads",
    fullname = _("Goodreads"),
    description = _([[Allows browsing and searching the Goodreads database of books.]]),
    deprecated = "The Goodreads API has been discontinued. Some keys might still work, but this plugin will be removed soon.",
}
