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
local C_ = _.pgettext

-- Default globally enabled style tweaks, for new installations
local DEFAULT_GLOBAL_STYLE_TWEAKS = {}
-- Display in-page per-specs footnotes for EPUB and FB2:
DEFAULT_GLOBAL_STYLE_TWEAKS["footnote-inpage_epub_smaller"] = true
DEFAULT_GLOBAL_STYLE_TWEAKS["footnote-inpage_fb2"] = true

local CssTweaks = {
    DEFAULT_GLOBAL_STYLE_TWEAKS = DEFAULT_GLOBAL_STYLE_TWEAKS,
    {
        title = C_("Style tweaks category", "Pages"),
        {
            id = "margin_body_0";
            title = _("Ignore publisher page margins"),
            description = _("Force page margins to be 0, and may allow KOReader's margin settings to work on books where they would not."),
            css = [[body { margin: 0 !important; }]],
        },
        {
            title = _("Ignore margin and padding"),
            {
                id = "margin_horizontal_all_0";
                title = _("Ignore horizontal margins"),
                priority = 2,
                css = [[* { margin-left: 0 !important; margin-right: 0 !important; }]],
            },
            {
                id = "margin_vertical_all_0";
                title = _("Ignore vertical margins"),
                priority = 2,
                css = [[* { margin-top: 0 !important; margin-bottom: 0 !important; }]],
                separator = true,
            },
            {
                id = "padding_horizontal_all_0";
                title = _("Ignore horizontal padding"),
                priority = 2,
                css = [[* { padding-left: 0 !important; padding-right: 0 !important; }]],
            },
            {
                id = "padding_vertical_all_0";
                title = _("Ignore vertical padding"),
                priority = 2,
                css = [[* { padding-top: 0 !important; padding-bottom: 0 !important; }]],
            },
            separator = true,
        },
        {
            title = _("Page breaks and blank pages"),
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
h1 { -cr-only-if: -epub-document; page-break-before: always !important; }
h2, h3 { -cr-only-if: legacy -epub-document; page-break-before: always !important; }
h1, h2, h3, h4, h5, h6 { page-break-after: avoid !important; }
                ]],
                separator = true,
            },
            {
                title = _("New page on headings"),
                {
                    id = "h1_page-break-before_always";
                    title = _("New page on <H1>"),
                    css = [[h1 { page-break-before: always !important; }]],
                },
                {
                    id = "h2_page-break-before_always";
                    title = _("New page on <H2>"),
                    css = [[
h2 { page-break-before: always !important; }
h1 + h2 { page-break-before: avoid !important; }
                    ]],
                },
                {
                    id = "h3_page-break-before_always";
                    title = _("New page on <H3>"),
                    css = [[
h3 { page-break-before: always !important; }
h1 + h3, h2 + h3 { page-break-before: avoid !important; }
                    ]],
                },
                {
                    id = "h4_page-break-before_always";
                    title = _("New page on <H4>"),
                    css = [[
h4 { page-break-before: always !important; }
h1 + h4, h2 + h4, h3 + h4 { page-break-before: avoid !important; }
                    ]],
                },
                {
                    id = "h5_page-break-before_always";
                    title = _("New page on <H5>"),
                    css = [[
h5 { page-break-before: always !important; }
h1 + h5, h2 + h5, h3 + h5, h4 + h5 { page-break-before: avoid !important; }
                    ]],
                },
                {
                    id = "h6_page-break-before_always";
                    title = _("New page on <H6>"),
                    css = [[
h6 { page-break-before: always !important; }
h1 + h6, h2 + h6, h3 + h6, h4 + h6, h5 + h6 { page-break-before: avoid !important; }
                    ]],
                },
            },
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
                description = _("Text justification is the default, but it may be overridden by publisher styles. This will force justification on all elements, some of which may not be centered as expected."),
                css = [[* { text-align: justify !important; }]],
                separator = true,
            },
            {
                id = "headings_align_center",
                title = _("Center headings"),
                css = [[h1, h2, h3, h4, h5, h6 { text-align: center !important; }]],
                priority = 4, -- so it overrides the ones above
            },
        },
        {
            title = _("Text direction"),
            {
                title = _("About text direction"),
                info_text = _([[
Languages like Arabic or Hebrew use right-to-left writing systems (Right-To-Left or RTL). This doesn't only affect text layout, but also list item bullets and numbers, which have to be put on the right side of the page, as well as tables, where the cells are laid out from right to left.

Usually, the publisher will have set the appropriate tags to enable RTL rendering. But if these are missing, or if you're reading plain text documents, you may want to manually enable RTL with these tweaks.
Note that in the absence of such specifications, KOReader will try to detect the language of each paragraph to set the appropriate rendering per paragraph.

You may also want to enable, in the top menu → Gear → Navigation →, Invert page turn taps and swipes.]]),
                separator = true,
            },
            {
                id = "body_direction_rtl",
                title = _("Document direction RTL"),
                css = [[body { direction: rtl !important; }]],
                priority = 2, -- so it overrides the LTR one below
            },
            {
                id = "text_align_most_right",
                title = _("Right align most text"),
                description = _("Enforce right alignment of text in common text elements."),
                -- Includes H1..H6 as this is probably most useful for RTL readers
                css = [[body, p, li, h1, h2, h3, h4, h5, h6 { text-align: right !important; }]],
                priority = 3, -- so it overrides the ones from Text alignment
            },
            {
                id = "text_align_all_right",
                title = _("Right align all elements"),
                description = _("Enforce right alignment of text in all elements."),
                css = [[* { text-align: right !important; }]],
                priority = 3, -- so it overrides the ones from Text alignment
                separator = true,
            },
            {
                id = "body_direction_ltr",
                title = _("Document direction LTR"),
                css = [[body { direction: ltr !important; }]],
            },
            separator = true,
        },
        {
            title = _("Widows and orphans"),
            {
                title = _("About widow and orphan lines"),
                info_text = _([[
Widows and orphans are lines at the beginning or end of a paragraph, which are left dangling at the top or bottom of a page, separated from the rest of the paragraph.
The first line of a paragraph alone at the bottom of a page is called an orphan line.
The last line of a paragraph alone at the top of a page is called a widow line.

Some people (and publishers) don't like widows and orphans, and can avoid them with CSS rules.
To avoid widows and orphans, some lines have to be pushed to the next page to accompany what would otherwise be widows and orphans. This may leave some blank space at the bottom of the previous page, which might be more disturbing to others.

The default is to allow widows and orphans.
These tweaks allow you to change this behavior, and to override publisher rules.]]),
                separator = true,
            },
            -- To avoid duplicating these 2 tweaks into 2 others for ignoring publisher rules,
            -- we apply the rules to BODY without !important (so they can still be overriden
            -- by publisher rules applied to BODY), and to DocFragment with !important (so
            -- that with "* {widows/orphans: inherit !important}", all elements will inherit
            -- from the DocFragment rules.
            -- This trick will work with EPUB, but not with single file HTML.
            {
                id = "widows_orphans_avoid";
                title = _("Avoid widows and orphans"),
                description = _("Avoid widow and orphan lines, allowing for some possible blank space at the bottom of pages."),
                css = [[
body { orphans: 2; widows: 2; }
DocFragment {
    orphans: 2 !important;
    widows:  2 !important;
}
                ]],
                priority = 2, -- so it overrides the * inherit below for DocFragment
            },
            {
                id = "widows_avoid_orphans_allow";
                title = _("Avoid widows but allow orphans"),
                description = _([[
Avoid widow lines, but allow orphan lines, allowing for some possible blank space at the bottom of pages.
Allowing orphans avoids ambiguous blank space at the bottom of a page, which could otherwise be confused with real spacing between paragraphs.]]),
                css = [[
body { orphans: 1; widows: 2; }
DocFragment {
    orphans: 1 !important;
    widows:  2 !important;
}
                ]],
                priority = 2, -- so it overrides the * inherit below for DocFragment
                separator = true,
            },
            {
                id = "widows_orphans_all_inherit";
                title = _("Ignore publisher orphan and widow rules"),
                description = _("Disable orphan and widow rules specified in embedded styles."),
                css = [[
* {
    orphans: inherit !important;
    widows:  inherit !important;
}
                ]],
            },
        },
        {
            title = _("Hyphenation, ligatures, ruby"),
            {
                id = "hyphenate_all_auto";
                title = _("Allow hyphenation on all text"),
                description = _("Allow hyphenation on all text (except headings), in case the publisher has disabled it."),
                css = [[
* { hyphens: auto !important; }
h1, h2, h3, h4, h5, h6 { hyphens: none !important; }
                ]],
            },
            {
                id = "ligature_all_no_common_ligature";
                title = _("Disable common ligatures"),
                description = _("Disable common ligatures, which are enabled by default in 'best' kerning mode."),
                -- We don't use !important, as this would stop other font-variant properties
                -- from being applied
                css = [[
* { font-variant: no-common-ligatures; }
                ]],
                separator = true,
            },
            {
                id = "ruby_inline";
                title = _("Render <ruby> content inline"),
                description = _("Disable handling of <ruby> tags and render them inline."),
                css = [[
ruby { display: inline !important; }
                ]],
            },
            separator = true,
        },
        {
            title = _("Fonts and line heights"),
            {
                id = "font_family_all_inherit";
                title = _("Ignore publisher font families"),
                description = _("Disable font-family specified in embedded styles."),
                css = [[* { font-family: inherit !important; }]],
            },
            {
                id = "font_size_all_inherit";
                title = _("Ignore publisher font sizes"),
                description = _("Disable font-size specified in embedded styles."),
                css = [[* { font-size: inherit !important; }]],
                separator = true,
            },
            {
                id = "lineheight_all_inherit";
                title = _("Ignore publisher line heights"),
                description = _("Disable line-height specified in embedded styles, and may allow KOReader's line spacing settings to work on books where they would not."),
                css = [[* { line-height: inherit !important; }]],
            },
            {
                id = "lineheight_all_normal_strut_confined";
                title = _("Enforce steady line heights"),
                description = _("Prevent inline content like sub- and superscript from changing their paragraph line height."),
                -- strut-confined is among the few cr-hints that are inherited
                css = [[body { -cr-hint: strut-confined; }]],
                separator = true,
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
            },
        },
    },
    {
        title = _("Paragraphs"),
        {
            id = "paragraph_web_browser_style";
            title = _("Generic web browser paragraph style"),
            description = _([[
Display paragraphs as browsers do, in full-block style without indentation or justification, discarding KOReader's book paragraph style.
This might be needed with some documents that expect this style as the default, and only use CSS when it needs to diverge from this default.]]),
            priority = -1,
            css = [[
p {
    text-align: start;
    text-indent: 0;
    margin-top: 1em;
    margin-bottom: 1em;
}
            ]],
            separator = true,
        },
        {
            title = _("Paragraph first-line indentation"),
            {
                id = "paragraph_no_indent";
                title = _("No indentation on first paragraph line"),
                description = _("Do not indent the first line of paragraphs."),
                css = [[p { text-indent: 0 !important; }]],
                separator = true,
            },
            {
                id = "paragraph_indent";
                title = _("Indentation on first paragraph line"),
                description = _("Indentation on the first line of a paragraph is the default, but it may be overridden by publisher styles. This will force KOReader's defaults on common elements."),
                css = [[
p { text-indent: 1.2em !important; }
body, h1, h2, h3, h4, h5, h6, div, li, td, th { text-indent: 0 !important; }
                ]],
            },
            {
                id = "paragraph_first_no_indent";
                title = _("No indentation on first paragraph"),
                description = _("Do not indent the first line of the first paragraph of its container. This might be needed to correctly display drop caps, while still having indentation on following paragraphs."),
                priority = 2, -- so it can override 'paragraph_indent'
                css = [[p:first-child { text-indent: 0 !important; }]],
            },
            {
                id = "paragraph_following_no_indent";
                title = _("No indentation on following paragraphs"),
                description = _("Do not indent the first line of following paragraphs, but leave the first paragraph of its container untouched."),
                priority = 2, -- so it can override 'paragraph_indent'
                css = [[p + p { text-indent: 0 !important; }]],
            },
        },
        {
            title = _("Spacing between paragraphs"),
            {
                id = "paragraph_whitespace";
                title = _("Spacing between paragraphs"),
                description = _("Add a line of whitespace between paragraphs."),
                priority = 5, -- Override "Ignore margins and paddings" below
                css = [[p + p { margin-top: 1em !important; }]],
            },
            {
                id = "paragraph_whitespace_half";
                title = _("Spacing between paragraphs (half)"),
                description = _("Add half a line of whitespace between paragraphs."),
                priority = 5,
                css = [[p + p { margin-top: .5em !important; }]],
            },
            {
                id = "paragraph_no_whitespace";
                title = _("No spacing between paragraphs"),
                description = _("No whitespace between paragraphs is the default, but it may be overridden by publisher styles. This will re-enable it for paragraphs and list items."),
                priority = 5,
                css = [[p, li { margin-top: 0 !important; margin-bottom: 0 !important; }]],
                separator = true,
            },
            {
                id = "paragraph_no_vertical_padding";
                title = _("Ignore vertical paragraph padding"),
                priority = 3, -- Override "Pages > Ignore margin and padding"
                css = [[p, li { padding-top: 0 !important; padding-bottom: 0 !important; }]],
            },
        },
        {
            title = _("Horizontal paragraph margins"),
            {
                id = "paragraph_no_horizontal_margin";
                title = _("Ignore horizontal paragraph margins"),
                priority = 3, -- Override "Pages > Ignore margin and padding"
                css = [[p, li { margin-left: 0 !important; margin-right: 0 !important; }]],
            },
            {
                id = "paragraph_no_horizontal_padding";
                title = _("Ignore horizontal paragraph padding"),
                priority = 3,
                css = [[p, li { padding-left: 0 !important; padding-right: 0 !important; }]],
            },
            separator = true,
        },
        {
            title = _("List items"),
            {
                id = "ul_li_type_disc";
                title = _("Force bullets with unordered lists"),
                css = [[ul > li { list-style-type: disc !important; }]],
            },
            {
                id = "ol_li_type_decimal";
                title = _("Force decimal numbers with ordered lists"),
                css = [[ol > li { list-style-type: decimal !important; }]],
            },
        },
    },
    {
        title = _("Tables"),
        {
            id = "table_full_width";
            title = _("Full-width tables"),
            description = _("Make table expand to the full width of the page. (Tables with small content now use only the width needed to display that content. This restores the previous behavior.)"),
            css = [[table { width: 100% !important; }]],
            priority = 2, -- Override next one
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
            priority = 3, -- Override "Pages > Ignore margin and padding"
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
        },
    },
    {
        title = _("Links"),
        {
            id = "a_black";
            title = _("Links always black"),
            css = [[a, a * { color: black !important; }]],
        },
        {
            id = "a_blue";
            title = _("Links always blue"),
            css = [[a, a * { color: blue !important; }]],
            separator = true,
        },
        {
            id = "a_bold";
            title = _("Links always bold"),
            css = [[a, a * { font-weight: bold !important; }]],
        },
        {
            id = "a_not_bold";
            title = _("Links never bold"),
            css = [[a, a * { font-weight: normal !important; }]],
            separator = true,
        },
        {
            id = "a_italic";
            title = _("Links always italic"),
            css = [[a, a * { font-style: italic !important; }]],
        },
        {
            id = "a_not_italic";
            title = _("Links never italic"),
            css = [[a, a * { font-style: normal !important; }]],
            separator = true,
        },
        {
            id = "a_underline";
            title = _("Links always underlined"),
            css = [[a[href], a[href] * { text-decoration: underline !important; }]],
            -- Have it apply only on real links with a href=, not on anchors
        },
        {
            id = "a_not_underline";
            title = _("Links never underlined"),
            css = [[a, a * { text-decoration: none !important; }]],
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
            title = _("Alternative ToC hints"),
            {
                title = _("About alternative ToC"),
                info_text = _([[
An alternative table of contents can be built via a dedicated option in the "Settings" menu below the "Table of contents" menu entry.

The ToC will be built from document headings <H1> to <H6>. Some of these can be ignored with the tweaks available here.
If the document contains no headings, or all are ignored, the alternative ToC will be built from document fragments and will point to the start of each individual HTML file in the EPUB.

Hints can be set to other non-heading elements in a user style tweak, so they can be used as ToC items. Since this would be quite book-specific, please see the final tweak for some examples.

After applying these tweaks, the alternative ToC needs to be rebuilt by toggling it twice in its menu: once to restore the original ToC, and once to build the alternative ToC again.]]),
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
                title = _("Example of book specific ToC hints"),
                description = _([[
If headings or document fragments do not result in a usable ToC, you can inspect the HTML and look for elements that contain chapter titles. Then you can set hints to their class names.
This is just an example, that will need to be adapted into a user style tweak.]]),
                css = [[
.book_n    { -cr-hint: toc-level1; }
.part_n    { -cr-hint: toc-level2; }
.chap_tit  { -cr-hint: toc-level3; }
.chap_tit1 { -cr-hint: toc-level3; }
                ]],
            },
        },
        {
            title = _("In-page footnotes"),
            {
                title = _("In-page FB2 footnotes"),
                {
                    id = "footnote-inpage_fb2";
                    title = _("In-page FB2 footnotes"),
                    description = _([[
Show FB2 footnote text at the bottom of pages that contain links to them.]]),
                    -- Restrict this to FB2 documents, even if we won't probably
                    -- match in any other kind of document
                    -- (Last selector avoids title bottom margin from collapsing
                    -- into the first footnote by substituting it with padding.)
                    css = [[
body[name="notes"] section {
    -cr-only-if: fb2-document;
        -cr-hint: footnote-inpage;
        margin: 0 !important;
}
body[name="notes"] > section {
    -cr-only-if: fb2-document;
        font-size: 0.75rem;
}
body[name="notes"] > title {
    -cr-only-if: fb2-document;
        margin-bottom: 0;
        padding-bottom: 0.5em;
}
                    ]],
                },
                {
                    id = "footnote-inpage_fb2_comments";
                    title = _("In-page FB2 endnotes"),
                    description = _([[
Show FB2 endnote text at the bottom of pages that contain links to them.]]),
                    css = [[
body[name="comments"] section {
    -cr-only-if: fb2-document;
        -cr-hint: footnote-inpage;
        margin: 0 !important;
}
body[name="comments"] > section {
    -cr-only-if: fb2-document;
        font-size: 0.85rem;
}
body[name="comments"] > title {
    -cr-only-if: fb2-document;
        margin-bottom: 0;
        padding-bottom: 0.5em;
}
                    ]],
                    separator = true,
                },
                {
                    id = "fb2_footnotes_regular_font_size";
                    title = _("Keep regular font size"),
                    description = _([[
FB2 footnotes and endnotes get a smaller font size when displayed in-page. This allows them to be shown with the normal font size.]]),
                    css = [[
body[name="notes"] > section,
body[name="comments"] > section
{
    -cr-only-if: fb2-document;
        font-size: 1rem !important;
}
                    ]],
                },
                separator = true,
            },
            {
                id = "footnote-inpage_epub";
                title = _("In-page EPUB footnotes"),
                description = _([[
Show EPUB footnote text at the bottom of pages that contain links to them.
This only works with footnotes that have specific attributes set by the publisher.]]),
                -- Restrict this to non-FB2 documents, as FB2 can have <a type="note">
                css = [[
*[type~="note"],
*[type~="footnote"],
*[type~="rearnote"],
*[role~="doc-note"],
*[role~="doc-footnote"],
*[role~="doc-rearnote"]
{
    -cr-only-if: -fb2-document;
        -cr-hint: footnote-inpage;
        margin: 0 !important;
}
                ]],
            },
            {
                id = "footnote-inpage_epub_smaller";
                title = _("In-page EPUB footnotes (smaller)"),
                description = _([[
Show EPUB footnote text at the bottom of pages that contain links to them.
This only works with footnotes that have specific attributes set by the publisher.]]),
                -- Restrict this to non-FB2 documents, as FB2 can have <a type="note">
                -- and we don't want to have them smaller
                css = [[
*[type~="note"],
*[type~="footnote"],
*[type~="rearnote"],
*[role~="doc-note"],
*[role~="doc-footnote"],
*[role~="doc-rearnote"]
{
    -cr-only-if: -fb2-document;
        -cr-hint: footnote-inpage;
        margin: 0 !important;
        font-size: 0.8rem !important;
}
                ]],
                separator = true,
            },
            {
                id = "footnote-inpage_wikipedia";
                title = _("In-page Wikipedia footnotes"),
                description = _([[Show footnotes at the bottom of pages in Wikipedia EPUBs.]]),
                css = [[
ol.references > li {
    -cr-hint: footnote-inpage;
    margin: 0 !important;
}
/* hide backlinks */
ol.references > li > .noprint { display: none; }
ol.references > li > .mw-cite-backlink { display: none; }
                ]],
            },
            {
                id = "footnote-inpage_wikipedia_smaller";
                title = _("In-page Wikipedia footnotes (smaller)"),
                description = _([[Show footnotes at the bottom of pages in Wikipedia EPUBs.]]),
                css = [[
ol.references > li {
    -cr-hint: footnote-inpage;
    margin: 0 !important;
    font-size: 0.8rem !important;
}
/* hide backlinks */
ol.references > li > .noprint { display: none; }
ol.references > li > .mw-cite-backlink { display: none; }
                ]],
                separator = true,
            },
            -- We can add other classic classnames to the 2 following
            -- tweaks (except when named 'calibreN', as the N number is
            -- usually random across books).
            {
                id = "footnote-inpage_classic_classnames";
                title = _("In-page classic classname footnotes"),
                description = _([[
Show footnotes with classic classnames at the bottom of pages.
This tweak can be duplicated as a user style tweak when books contain footnotes wrapped with other class names.]]),
                css = [[
.footnote, .footnotes, .fn,
.note, .note1, .note2, .note3,
.ntb, .ntb-txt, .ntb-txt-j,
.voetnoten
{
    -cr-hint: footnote-inpage;
    margin: 0 !important;
}
                ]],
            },
            {
                id = "footnote-inpage_classic_classnames_smaller";
                title = _("In-page classic classname footnotes (smaller)"),
                description = _([[
Show footnotes with classic classnames at the bottom of pages.
This tweak can be duplicated as a user style tweak when books contain footnotes wrapped with other class names.]]),
                css = [[
.footnote, .footnotes, .fn,
.note, .note1, .note2, .note3,
.ntb, .ntb-txt, .ntb-txt-j,
.voetnoten
{
    -cr-hint: footnote-inpage;
    margin: 0 !important;
    font-size: 0.8rem !important;
}
                ]],
            },
        },
        {
            id = "no_pseudo_element_before_after";
            title = _("Disable before/after pseudo elements"),
            description = _([[Disable generated text from ::before and ::after pseudo elements, usually used to add cosmetic text around some content.]]),
            css = [[
*::before { display: none !important; }
*::after  { display: none !important; }
            ]],
        },
        {
            id = "pure_black_and_white";
            title = _("Pure black and white"),
            description = _([[Enforce black text and borders, and remove backgrounds.]]),
            css = [[
* {
    color: black !important;
    border-color: black !important;
    background-color: transparent !important;
    background-image: !important;
}
            ]], -- (This last empty background-image: works for cancelling any previous one
        },
    },
    -- No current need for workarounds
    -- {
    --     title = _("Workarounds"),
    -- },
}

return CssTweaks
