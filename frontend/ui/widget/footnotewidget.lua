local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template
local time = require("ui/time")

-- Note: we can't use < or > in comments in the CSS, or MuPDF complains with:
--   error: css syntax error: unterminated comment.
-- So, HTML tags in comments are written uppercase (eg: <li> => LI)

-- Independent string for @page, so we can T() it individually,
-- without needing to escape % in DEFAULT_CSS
local PAGE_CSS = [[
@page {
    margin: %1 %2 %3 %4;
    font-family: '%5';
}
%6
%7
]]

-- Make default MuPDF styles (source/html/html-layout.c) a bit
-- more similar to our epub.css ones, and more condensed to fit
-- in a small bottom panel
local DEFAULT_CSS = [[
body {
    margin: 0;                  /* MuPDF: margin: 1em */
    padding: 0;
    line-height: 1.3;           /* MuPDF defaults to 1.2 */
    text-align: justify;
}
/* We keep left and right margin the same so it also displays as expected in RTL */
h1, h2, h3, h4, h5, h6 { margin: 0; } /* MuPDF: margin: XXem 0 , vary with level */
blockquote { margin: 0 1em; }   /* MuPDF: margin: 1em 40px */
p   { margin: 0; }              /* MuPDF: margin: 1em 0 */
ol  { margin: 0; }              /* MuPDF: margin: 1em 0; padding: 0 0 0 30pt */
ul  { margin: 0; }              /* MuPDF: margin: 1em 0; padding: 0 0 0 30pt */
dl  { margin: 0; }              /* MuPDF: margin: 1em 0 */
dd  { margin: 0 1em; }          /* MuPDF: margin: 0 0 0 40px */
pre { margin: 0.5em 0; }        /* MuPDF: margin: 1em 0 */
a   { color: black; }           /* MuPDF: color: #06C; */
/* MuPDF has no support for text-decoration, so we can't underline links,
 * which is fine as we don't really need to provide link support */

/* MuPDF draws the bullet for a standalone LI outside the margin.
 * Avoid it being displayed if the first node is a LI (in
 * Wikipedia EPUBs, each footnote is a LI */
body > li { list-style-type: none; }

/* MuPDF always aligns the last line to the left when text-align: justify,
 * which is wrong with RTL. So cancel justification on RTL elements: they
 * will be correctly aligned to the right */
*[dir=rtl] { text-align: initial; }

/* Remove any (possibly multiple) backlinks in Wikipedia EPUBs footnotes */
.noprint { display: none; }

/* Let MuPDF know about crengine internal block elements,
 * so it doesn't render them inline */
autoBoxing, floatBox, tabularBox { display: block; }

/* Style some FB2 tags not known to MuPDF */
strike, strikethrough { text-decoration: line-through; }
underline   { text-decoration: underline; }
emphasis    { font-style: italic; }
small       { font-size: 80%; }
big         { font-size: 130%; }
empty-line  { display: block; padding: 0.5em; }
image       { display: block; padding: 0.4em; border: 0.1em solid black; width: 0; }
date        { display: block; font-style: italic; }
epigraph    { display: block; font-style: italic; }
poem        { display: block; }
stanza      { display: block; font-style: italic; }
v           { display: block; text-align: left; hyphenate: none; }
text-author { display: block; font-weight: bold; font-style: italic; }

/* Attempt to display FB2 footnotes as expected (as crengine does, putting
 * the footnote number on the same line as the first paragraph via its
 * support of "display: run-in" and a possibly added autoBoxing element) */
body > section > autoBoxing > *,
body > section > autoBoxing > title > *,
body > section > title,
body > section > title > p,
body > section > p {
    display: inline;
}
body > section > autoBoxing + p,
body > section > p + p {
    display: block;
}
body > section > autoBoxing > title,
body > section > title {
    font-weight: bold;
}
]]

-- Add this if needed for debugging:
-- @page { background-color: #cccccc; }
-- body { background-color: #eeeeee; }

-- Widget to display footnote HTML content
local FootnoteWidget = InputContainer:extend{
    html = nil,
    css = nil,
    -- font_face can't really be overridden, it needs to be known by MuPDF
    font_face = "Noto Sans",
    -- For the doc_* values, we expect to be provided with the real
    -- (already scaled) sizes in screen pixels
    doc_font_size = Screen:scaleBySize(18),
    doc_font_name = nil,
    doc_margins = { -- const
        left = Screen:scaleBySize(20),
        right = Screen:scaleBySize(20),
        top = Screen:scaleBySize(10),
        bottom = Screen:scaleBySize(10),
    },
    follow_callback = nil,
    on_tap_close_callback = nil,
    close_callback = nil,
    dialog = nil,
    covers_footer = true,
}

function FootnoteWidget:init()
    -- Set widget size
    self.width = Screen:getWidth()
    self.height = math.floor(Screen:getHeight() * 1/3) -- will be decreased when content is smaller

    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }

        local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate")
        if not hold_pan_rate then
            hold_pan_rate = Screen.low_pan_rate and 5.0 or 30.0
        end

        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                }
            },
            SwipeFollow = {
                GestureRange:new{
                    ges = "swipe",
                    range = range,
                }
            },
            HoldStartText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new{
                    ges = "hold_pan",
                    range = range,
                    rate = hold_pan_rate,
                },
            },
            HoldReleaseText = {
                GestureRange:new{
                    ges = "hold_release",
                    range = range,
                },
                -- callback function when HoldReleaseText is handled as args
                args = function(text, hold_duration)
                    if self.dialog then
                        local dict_close_callback = function()
                            self.htmlwidget.htmlbox_widget:scheduleClearHighlightAndRedraw()
                        end

                        local lookup_target = hold_duration < time.s(3) and "LookupWord" or "LookupWikipedia"
                        self.dialog:handleEvent(
                            Event:new(lookup_target, text, nil, nil, nil, nil, dict_close_callback)
                        )
                    end
                end
            },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            Follow = { { "Press" } },
        }
    end

    -- Workaround bugs in MuPDF:
    -- There is something with its handling of <BR>:
    --   <div>abc<br/>def</div> : 2 lines, no space in between
    --   <div>abc<br anyattr="anyvalue"/>def</div> : 3 lines, empty line in between
    -- Remove any attribute, let a <br/> be a plain <br/>
    self.html = self.html:gsub([[<br[^>]*>]], [[<br/>]])
    -- Elements with a id= attribute get a line above them (by some internal MuPDF
    -- code, possibly generate_anchor() in html-layout.c).
    -- Working around it with the following does not work: *[id] {margin-top: -1em;}
    -- So, just rename the id= attribute, as we don't follow links in this popup.
    self.html = self.html:gsub([[(<[^>]* )[iI][dD]=]], [[%1disabledID=]])

    -- We may use a font size a bit smaller than the document one (because
    -- footnotes are usually smaller, and because NotoSans is a bit on the
    -- larger size when compared to other fonts at the same size)
    local font_size = G_reader_settings:readSetting("footnote_popup_absolute_font_size")
    if font_size then
        font_size = Screen:scaleBySize(font_size)
    else
        font_size = self.doc_font_size + (G_reader_settings:readSetting("footnote_popup_relative_font_size") or -2)
    end

    local font_css = ""
    if G_reader_settings:isTrue("footnote_popup_use_book_font") then
        local cre = require("document/credocument"):engineInit()
        -- Note: we can't provide any base weight (as supported by crengine), as MuPDF
        -- will use the bold font for anything with a weight > 400. We can only use the
        -- font as-is, without its natural weight tweaked.
        local seen_font_path = {}
        for i=1, 4 do
            local bold = i >= 3
            local italic = i == 2 or i ==4
            -- We assume the font is not from a collection, and ignore the index.
            local font_path = cre.getFontFaceFilenameAndFaceIndex(self.doc_font_name, bold, italic)
            -- crengine returns the regular filename when requesting a bold that
            -- it has synthesized; but MuPDF would consider it as real bold and
            -- would use it as-is: by not providing the fake bold font file path,
            -- we let MuPDF itself synthesize the bold (and also italic if none
            -- provided). So, keep track of what's been seen and used.
            if font_path and not seen_font_path[font_path] then
                seen_font_path[font_path] = true
                font_css = font_css .. T("\n@font-face { font-family: 'KOReaderFootnoteFont'; src: url('%1')%2%3}",
                            font_path,
                            bold and "; font-weight: bold" or "",
                            italic and "; font-style: italic" or "")
            end
        end
        if font_css ~= "" then
            -- If not using our standard font, override "line-height:1.3" (which is fine
            -- with Noto Sans) to use something smaller (looks like MuPDF's default is 1.2
            -- and we can't make it use the font natural line height...)
            font_css = font_css .. "\nbody { font-family: 'KOReaderFootnoteFont'; line-height: 1.2 !important; }\n"
        end
    end

    -- We want to display the footnote text with the same margins as
    -- the document, but keep the scrollbar in the right margin, so
    -- both small footnotes (without scrollbar) and longer ones (with
    -- scrollbar) have their text aligned with the document text.
    -- MuPDF, when rendering some footnotes, may put list item
    -- bullets in its own left margin. To get a chance to have them
    -- shown, we let MuPDF handle our left margin.
    local html_left_margin = self.doc_margins.left .. "px"
    local html_right_margin = "0"
    if BD.mirroredUILayout() then
        html_left_margin, html_right_margin = html_right_margin, html_left_margin
    end

    local css = T(PAGE_CSS, "0", html_right_margin, "0", html_left_margin, -- top right bottom left
                    self.font_face, font_css, DEFAULT_CSS)
    if self.css then -- add any provided css
        css = css .. "\n" .. self.css
    end
    -- require("logger").dbg("CSS:", css)
    -- require("logger").dbg("HTML:", self.html)

    -- Scrollbar on the right: the document may have quite large margins,
    -- and we don't want a scrollbar that large.
    -- Ensute a not too large scrollbar, and bring it closer to the screen
    -- edge, leaving the remaining available room between it and the text.
    local item_width = math.min(math.ceil(self.doc_margins.right * 2/5), Screen:scaleBySize(10))
    local scroll_bar_width = item_width
    local padding_right = item_width
    local text_scroll_span = self.doc_margins.right - scroll_bar_width - padding_right
    if text_scroll_span < padding_right then
        -- With small doc margins, space between text and scrollbar may get
        -- too small: switch it with right padding
        text_scroll_span, padding_right = padding_right, text_scroll_span
    end
    local htmlwidget_width = self.width - padding_right

    -- Top and bottom padding: we'd rather not use document margins:
    -- they can be large, which makes sense at screen edges, but
    -- would be too large for our top padding. Also, MuPDF will often
    -- let some blank area at bottom with its line layout and page
    -- breaking algorithms, which will visually add to the bottom padding.
    local padding_top = Size.padding.large
    local padding_bottom = Size.padding.large
    local htmlwidget_height = self.height - padding_top - padding_bottom

    -- We always get balanced XHTML from crengine for HTML snippets, so we
    -- pass is_xhtml=true to avoid side effects from MuPDF's HTML5 parser.
    self.htmlwidget = ScrollHtmlWidget:new{
        html_body = self.html,
        is_xhtml = true,
        css = css,
        default_font_size = font_size,
        width = htmlwidget_width,
        height = htmlwidget_height,
        scroll_bar_width = scroll_bar_width,
        text_scroll_span = text_scroll_span,
        dialog = self.dialog,
        highlight_text_selection = true,
    }

    -- We only want a top border, so use a LineWidget for that
    local top_border_size = Size.line.thick
    local vgroup = VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{
                w = self.width,
                h = top_border_size,
            }
        },
        VerticalSpan:new{ width = padding_top },
        HorizontalGroup:new{
            self.htmlwidget,
            HorizontalSpan:new{ width = padding_right },
        },
        VerticalSpan:new{ width = padding_bottom },
    }

    -- If htmlwidget contains only one page (small footnote content),
    -- display only the valuable area: push the blank area down the screen
    -- (we can do that because no scroll bar will be displayed)
    local single_page_height = self.htmlwidget:getSinglePageHeight() -- nil if multi-pages
    if single_page_height then
        local added_bottom_pad = 0
        -- See if needed:
        -- Add a bit to bottom padding, as getSinglePageHeight() cut can be rough
        -- added_bottom_pad = math.floor(font_size * 0.2)
        local reduced_height = single_page_height + top_border_size + padding_top + padding_bottom + added_bottom_pad
        vgroup = CenterContainer:new{
            dimen = Geom:new{
                h = reduced_height,
                w = self.width,
            },
            ignore = "height",
            vgroup,
        }
        self.height = reduced_height -- for close_callback
    end

    -- Needed only to set a white background
    self.container = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        vgroup,
    }

    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        self.container
    }
end

function FootnoteWidget:onShow()
    UIManager:setDirty(self.dialog, function()
        return "ui", self.container.dimen
    end)
end

function FootnoteWidget:onCloseWidget()
    UIManager:setDirty(self.dialog, function()
        return "partial", self.container.dimen
    end)
end

function FootnoteWidget:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback(self.height)
    end
    return true
end

function FootnoteWidget:onFollow()
    if self.follow_callback then
        if self.close_callback then
            self.close_callback(self.height)
        end
        return self.follow_callback()
    end
end

function FootnoteWidget:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.container.dimen) then
        UIManager:close(self)
        -- Allow ReaderLink to check if our dismiss tap
        -- was itself on another footnote, and display
        -- it. This avoids having to tap 2 times to
        -- see another footnote.
        if self.on_tap_close_callback then
            self.on_tap_close_callback(arg, ges, self.height)
        elseif self.close_callback then
            self.close_callback(self.height)
        end
        return true
    end
    return false
end

function FootnoteWidget:onSwipeFollow(arg, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        if self.follow_callback then
            if self.close_callback then
                self.close_callback(self.height)
            end
            return self.follow_callback()
        end
    elseif direction == "south" or direction == "east" then
        UIManager:close(self)
        -- We can close with swipe down. If footnote is scrollable,
        -- this event will be eaten by ScrollHtmlWidget, and it will
        -- work only when started outside the footnote.
        -- Also allow closing with swipe east (like we do to go back
        -- from link)
        if self.close_callback then
            self.close_callback(self.height)
        end
        return true
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
    end
    return false
end

return FootnoteWidget
