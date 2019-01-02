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
        title = _("Pages"),
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
            separator = true,
        },
        {
            id = "titles_page-break-before_avoid ";
            title = _("Avoid blank page on chapter start"),
            priority = 2, -- so it can override the one put back by publisher_page-break-before_avoid
            css = [[h1, h2, h3 { page-break-before: auto !important; }]],

        },
        {
            id = "docfragment_page-break-before_avoid ";
            title = _("Avoid blank page on chapter end"),
            priority = 2, -- so it can override the one put back by publisher_page-break-before_avoid
            css = [[DocFragment { page-break-before: auto !important; }]],
        },
        {
            id = "publisher_page-breaks_avoid ";
            title = _("Avoid publisher page breaks"),
            description = _("Disable all publisher page breaks, keeping only KOReader's epub.css ones.\nWhen combined with the two previous tweaks, all page-breaks are disabled."),
            css = [[
* { page-break-before: auto !important; page-break-after: auto !important; }
/* put back epub.css page-breaks */
DocFragment { page-break-before: always !important; }
h1, h2, h3 { page-break-before: always !important; page-break-after: avoid !important; }
h4, h5, h6 { page-break-after: avoid !important; }
            ]],
        },
    },
    {
        title = _("Text"),
        {
            title = _("Text alignment"),
            {
                id = "text_align_most_left",
                title = _("Left align most text"),
                description = _("Enforce left alignment of text in common text elements."),
                css = [[body, p, li { text-align: left !important; }]],
                priority = 2, -- so it overrides the justify below
            },
            {
                id = "text_align_all_left",
                title = _("Left align all elements"),
                description = _("Enforce left alignment of text in all elements."),
                css = [[* { text-align: left !important; }]],
                priority = 2, -- so it overrides the justify below
                separator = true,
            },
            {
                id = "text_align_most_justify",
                title = _("Justify most text"),
                description = _("Text justification is the default, but it may be overridden by publisher styles. This will re-enable it for most common text elements."),
                css = [[body, p, li { text-align: justify !important; }]],
            },
            {
                id = "text_align_all_justify",
                title = _("Justify all elements"),
                description = _("Text justification is the default, but it may be overridden by publisher styles. This will re-enable it for all elements, which may lose centering in some of them."),
                css = [[* { text-align: justify !important; }]],
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
sub { font-size: 50% !important; vertical-align: sub !important; }
            ]],
            separator = true,
        },
        {
            id = "hyphenate_all_auto";
            title = _("Allow hyphenation on all text"),
            description = _("Allow hyphenation to happen on all text (except headings), in case the publisher has disabled it."),
            css = [[
* { hyphens: auto !important; }
h1, h2, h3, h4, h5, h6 { hyphens: none !important; }
            ]],
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
        title = _("Paragraphs"),
        {
            id = "paragraph_no_indent";
            title = _("No indentation on first paragraph line"),
            description = _("Do not indent the first line of paragraphs."),
            css = [[p { text-indent: 0 !important; }]],
        },
        {
            id = "paragraph_indent";
            title = _("Indentation on first paragraph line"),
            description = _("Indentation on the first line of a paragraph is the default, but it may be overridden by publisher styles. This will force KOReader's defaults on common elements."),
            css = [[
p { text-indent: 1.2em !important; }
body, h1, h2, h3, h4, h5, h6, div, li, td, th { text-indent: 0 !important; }
            ]],
            separator = true,
        },
        {
            id = "paragraph_whitespace";
            title = _("Spacing between paragraphs"),
            description = _("Add a line of whitespace between paragraphs."),
            css = [[p + p { margin-top: 1em !important; }]],
        },
        {
            id = "paragraph_whitespace_half";
            title = _("Spacing between paragraphs (half)"),
            description = _("Add half a line of whitespace between paragraphs."),
            css = [[p + p { margin-top: .5em !important; }]],
        },
        {
            id = "paragraph_no_whitespace";
            title = _("No spacing between paragraphs"),
            description = _("No whitespace between paragraphs is the default, but it may be overridden by publisher styles. This will re-enable it for paragraphs and list items."),
            css = [[p, li { margin-top: 0 !important; margin-bottom: 0 !important; }]],
        },
    },
    {
        title = _("Tables"),
        {
            id = "table_full_width";
            title = _("Full-width tables"),
            description = _("Make table expand to the full width of the page. (Tables with small content now use only the width needed to display that content. This restores the previous behavior.)"),
            css = [[table { width: 100% !important; }]],
        },
        {
            id = "table_td_width_auto";
            title = _("Ignore publisher table and cell widths"),
            description = _("Ignore table and cells widths specified by the publisher, and let the engine decide the most appropriate widths."),
            css = [[table, td, th { width: auto !important; }]],
        },
        {
            id = "table_margin_left_right_auto";
            title = _("Center small tables"),
            description = _("Horizontally center tables that do not use the full page width."),
            css = [[table { margin-left: auto !important; margin-right: auto !important; }]],
            separator = true,
        },
        {
            id = "td_vertical_align_none";
            title = _("Ignore publisher vertical alignment in tables"),
            -- Using "vertical-align: top" would vertical-align children text nodes to top.
            -- "vertical-align: baseline" has no meaning in table rendering, and is as fine
            css = [[td { vertical-align: baseline !important; }]],
        },
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
    },
    {
        title = _("Links"),
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
        title = _("Images"),
        {
            id = "image_full_width";
            title = _("Full-width images"),
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
        {
            id = "image_valign_middle";
            title = _("Vertically center-align images relative to text"),
            css = [[img { vertical-align: middle; }]],
        },
    },
    {
        title = _("Miscellaneous"),
        {
            title = _("Alternative TOC hints"),
            {
                title = _("About alternative TOC"),
                smaller_font = true,
                info_text = _([[
An alternative table of content can be built with a long-press on the "Table of content" menu item.

It will be built from document headings <H1> to <H6>. Some of these can be ignored with the tweaks available here.
If the document contains no heading, or all are ignored, the alternative TOC will be built from the document fragments, to point to the start of each individual HTML file in the EPUB.

Hints can be set to other non-heading elements, for them to be used as TOC items, in some user style tweaks (as they would be quite book-specific, see last tweak here for some examples).

After applying these tweaks, it is needed to re-build the alternative TOC by long-pressing "Table of content" twice (once to restore the original TOC, once to build again the alternative TOC).]]),
                separator = true,
            },
            {
                id = "alt_toc_ignore_h_all";
                title = _("Ignore all <H1> to <H6>"),
                css = [[h1, h2, h3, h4, h5, h6 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h1";
                title = _("Ignore <H1>"),
                css = [[h1 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h2";
                title = _("Ignore <H2>"),
                css = [[h2 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h3";
                title = _("Ignore <H3>"),
                css = [[h3 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h4";
                title = _("Ignore <H4>"),
                css = [[h4 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h5";
                title = _("Ignore <H5>"),
                css = [[h5 { -cr-hint: toc-ignore; }]],
            },
            {
                id = "alt_toc_ignore_h6";
                title = _("Ignore <H6>"),
                css = [[h6 { -cr-hint: toc-ignore; }]],
                separator = true,
            },
            {
                id = "alt_toc_level_example";
                title = _("Example of book specific TOC hints"),
                description = _([[
If headings or document fragments do not give a usable TOC, you may inspect the HTML and look for elements that contain chapter titles, and set hints to their class names.
This is just an example, that will need to be adapted in a user style tweak.]]),
                css = [[
.book_n    { -cr-hint: toc-level1; }
.part_n    { -cr-hint: toc-level2; }
.chap_tit  { -cr-hint: toc-level3; }
.chap_tit1 { -cr-hint: toc-level3; }
                ]],
            },
        },
        {
            id = "epub_footnote-inpage";
            title = _("Show EPUB footnotes in pages"),
            description = _([[
Show footnotes text at the bottom of pages that contain links to them.
This only works with footnotes that have specific attributes set by the publisher.]]),
            css = [[
/* EPUB attributes: */
*[type~="note"], *[type~="footnote"],
*[type~="rearnote"],
*[role~="doc-note"], *[role~="doc-footnote"],
*[role~="doc-rearnote"],
/* Wikipedia EPUBs footnotes: */
ol.references > li,
/* Classic footnotes class names: */
.footnote, .note, .note1
{
    -cr-hint: footnote-inpage;
    margin-top: 0 !important;
    margin-bottom: 0 !important;
}
/* Wikipedia EPUBs: hide backlinks */
ol.references > li > .noprint { display: none; }
            ]],
        },
        {
            id = "epub_footnote-inpage_smaller";
            title = _("Show smaller EPUB footnotes in pages"),
            description = _([[Decrease font size of footnotes text displayed in pages.]]),
            -- Include the whole content of previous style, so toggling this one is enough
            css = [[
/* EPUB attributes: */
*[type~="note"], *[type~="footnote"],
*[type~="rearnote"],
*[role~="doc-note"], *[role~="doc-footnote"],
*[role~="doc-rearnote"],
/* Wikipedia EPUBs footnotes: */
ol.references > li,
/* Classic footnotes class names: */
.footnote, .note, .note1
{
    -cr-hint: footnote-inpage;
    font-size: 80% !important;
    margin-top: 0 !important;
    margin-bottom: 0 !important;
}
/* Wikipedia EPUBs: hide backlinks */
ol.references > li > .noprint { display: none; }
            ]],
        },
        {
            id = "epub_switch_show_case";
            title = _("Toggle alternative EPUB content"),
            description = _([[
The EPUB3 format allows a
<epub:switch> <epub:case> <epub:default>
construct to provide alternative content to engines that support optional features.
KOReader currently falls back to hiding all <epub:case> content and shows the <epub:default> content (usually an image).
This tweak toggles this behavior, and may show the <epub:case> content as plain text.]]),
            css = [[
switch > case    { display: inline; }
switch > default { display: none; }
            ]],
        },
    },
    -- No current need for workarounds
    -- {
    --     title = _("Workarounds"),
    -- },
}

return CssTweaks
