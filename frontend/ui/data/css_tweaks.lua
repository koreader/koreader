--[[--
CSS tweaks must have the following attributes:
 - id: unique ID identifying this tweak, to be stored in settings
 - title: menu item title (must not be too long)
 - css: stylesheet text to append to external stylesheet
They may have the following optional attributes:
 - description: text displayed when holding on menu item
 - priority: higher numbers are appended after lower numbers
   (if not specified, default to 0)
]]

local _ = require("gettext")

local CssTweaks = {
    {
        title = _("Page"),
        {
            id = "margin_body_0";
            title = _("Ignore publisher page margins"),
            description = _("Force page margins to be 0, and may allow KOReader's margin settings to work on books where they would not."),
            css = [[body { margin: 0 !important; }]],
        },
        {
            id = "margin_all_0";
            title = _("Ignore all publisher margins"),
            priority = 2,
            css = [[* { margin: 0 !important; }]],
        },
        {
            id = "titles_page-break-before_avoid ";
            title = _("Avoid blank page on chapter start"),
            css = [[h1, h2, h3, .title, .title1, .title2, .title3 { page-break-before: avoid !important; }]],
        },
    },
    {
        title = _("Text"),
        {
            title = _("Links color and weight"),
            {
                id = "a_black";
                title = _("Links always black"),
                css = [[a { color: black !important; }]],
            },
            {
                id = "a_blue";
                title = _("Links always blue"),
                css = [[a { color: blue !important; }]],
                separator = true,
            },
            {
                id = "a_bold";
                title = _("Links always bold"),
                css = [[a { font-weight: bold !important; }]],
            },
            {
                id = "a_not_bold";
                title = _("Links never bold"),
                css = [[a { font-weight: normal !important; }]],
            },
        },
        {
            id = "sub_sup_smaller";
            title = _("Smaller sub- and superscript"),
            description = _("Prevent sub- and superscript from affecting line-height."),
            priority = 5, -- so we can override "font_size_all_inherit"
            -- https://friendsofepub.github.io/eBookTricks/
            -- https://github.com/koreader/koreader/issues/3923#issuecomment-386510294
            css = [[
sup { font-size: 50% !important; vertical-align: super !important; }
sub { font-size: 50% !important; vertical-align: middle !important; }
            ]],
            separator = true,
        },
        {
            id = "lineheight_all_inherit";
            title = _("Ignore publisher line heights"),
            description = _("Disable line-height specified in embedded styles, and may allow KOReader's line spacing settings to work on books where they would not."),
            css = [[* { line-height: inherit !important; }]],
        },
        {
            id = "font_family_all_inherit";
            title = _("Ignore publisher font families"),
            description = _("Disable font-family specified in embedded styles."),
            -- we have to use this trick, font-family handling by crengine is a bit complex
            css = [[* { font-family: "NoSuchFont" !important; }]],
        },
        {
            id = "font_size_all_inherit";
            title = _("Ignore publisher font sizes"),
            description = _("Disable font-size specified in embedded styles."),
            css = [[* { font-size: inherit !important; }]],
            separator = true,
        },
    },
    {
        title = _("Miscellaneous"),
        {
            id = "table_row_odd_even";
            title = _("Alternate background color of table rows"),
            css = [[
tr:nth-child(odd)  { background-color: #EEE !important; }
tr:nth-child(even) { background-color: #CCC !important; }
            ]],
        },
        {
            id = "table_force_border";
            title = _("Show borders on all tables"),
            css = [[
table, tcaption, tr, th, td { border: black solid 1px; border-collapse: collapse; }
            ]],
            separator = true,
        },
        {
            id = "image_full_width";
            title = _("Make images full width"),
            description = _("Useful for books containing only images, when they are smaller than your screen. May stretch images in some cases."),
            -- This helped me once with a book. Will mess with aspect ratio
            -- when images have a style="width: NNpx; heigh: NNpx"
            css = [[
img {
   text-align: center !important;
   text-indent: 0px !important;
   display: block !important;
   width: 100% !important;
}
            ]],
        },
    },
    {
        title = _("Workarounds"),
        {
            id = "border_all_none";
            title = _("Remove all borders"),
            description = _("Work around a crengine bug that makes a border drawn when {border: black solid 0px}."),
            -- css = [[* { border-style: none !important; }]],
            -- Better to keep the layout implied by width, just draw them in white
            css = [[* { border-color: white !important; }]],
        },
    },
}

return CssTweaks
