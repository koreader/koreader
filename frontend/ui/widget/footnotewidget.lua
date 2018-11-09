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

-- If we wanted to use the default font set for the book,
-- we'd need to add a few functions to crengine and cre.cpp
-- to get the font files paths (for each font, regular, italic,
-- bold...) so we can pass them to MuPDF with:
--   @font-face {
--       font-family: 'KOReader Footnote Font';
--       src: url("%1");
--   }
--   @font-face {
--       font-family: 'KOReader Footnote Font';
--       src: url("%2");
--       font-style: italic;
--   }
--   body {
--       font-family: 'KOReader Footnote Font';
--   }
-- But it looks quite fine if we use "Noto Sans": the difference in font look
-- (Sans, vs probably Serif in the book) will help noticing this is a KOReader
-- UI element, and somehow justify the difference in looks.

-- Note: we can't use < or > in comments in the CSS, or MuPDF complains with:
--   error: css syntax error: unterminated comment.
-- So, HTML tags in comments are written upppercase (eg: <li> => LI)

-- Independent string for @page, so we can T() it individually,
-- without needing to escape % in DEFAULT_CSS
local PAGE_CSS = [[
@page {
    margin: %1 %2 %3 %4;
    font-family: '%5';
}
%6
]]

-- Make default MuPDF styles (source/html/html-layout.c) a bit
-- more similar to our epub.css ones, and more condensed to fit
-- in a small bottom pannel
local DEFAULT_CSS = [[
body {
    margin: 0;                  /* MuPDF: margin: 1em */
    padding: 0;
    line-height: 1.3;
    text-align: justify;
}
h1, h2, h3, h4, h5, h6 { margin: 0; } /* MuPDF: margin: XXem 0 , vary with level */
blockquote { margin: 0 3em }    /* MuPDF: margin: 1em 40px */
p   { margin: 0; }              /* MuPDF: margin: 1em 0 */
ol  { margin: 0.5em 0; }        /* MuPDF: margin: 1em 0; padding: 0 0 0 30pt */
ul  { margin: 0.5em 0; }        /* MuPDF: margin: 1em 0; padding: 0 0 0 30pt */
dl  { margin: 0.5em; }          /* MuPDF: margin: 1em 0 */
dd  { margin-left: 1.3em; }     /* MuPDF: margin: 0 0 0 40px */
pre { margin: 0.5em 0; }        /* MuPDF: margin: 1em 0 */
a   { color: black; }           /* MuPDF: color: #06C; */
/* MuPDF has no support for text-decoration, so we can't underline links,
 * which is fine as we don't really need to provide link support */

/* MuPDF draws the bullet for a standalone LI outside the margin.
 * Avoid it being displayed if the first node is a LI (in
 * Wikipedia EPUBs, each footnote is a LI */
body > li { list-style-type: none; }

/* Remove any (possibly multiple) backlinks in Wikipedia EPUBs footnotes */
.noprint { display: none; }
]]

-- Add this if needed for debugging:
-- @page { background-color: #cccccc; }
-- body { background-color: #eeeeee; }

-- Widget to display footnote HTML content
local FootnoteWidget = InputContainer:new{
    html = nil,
    css = nil,
    -- font_face can't really be overriden, it needs to be known by MuPDF
    font_face = "Noto Sans",
    -- For the doc_* values, we expect to be provided with the real
    -- (already scaled) sizes in screen pixels
    doc_font_size = Screen:scaleBySize(18),
    doc_margins = {
        left = Screen:scaleBySize(20),
        right = Screen:scaleBySize(20),
        top = Screen:scaleBySize(10),
        bottom = Screen:scaleBySize(10),
    },
    follow_callback = nil,
    on_tap_close_callback = nil,
    close_callback = nil,
    dialog = nil,
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
                    ges = "hold",
                    range = range,
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
                        local lookup_target = hold_duration < 3.0 and "LookupWord" or "LookupWikipedia"
                        self.dialog:handleEvent(
                            Event:new(lookup_target, text)
                        )
                    end
                end
            },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "cancel" }
        }
    end

    -- Workaround bugs in MuPDF:
    -- There is something with its handling of <BR>:
    --   <div>abc<br/>def</div> : 2 lines, no space in between
    --   <div>abc<br anyattr="anyvalue"/>def</div> : 3 lines, empty line in between
    -- Remove any attribute, let a <br/> be a plain <br/>
    self.html = self.html:gsub([[<br[^>]*>]], [[<br/>]])

    -- We may use a font size a bit smaller than the document one (because
    -- footnotes are usually smaller, and because NotoSans is a bit on the
    -- larger size when compared to other fonts at the same size)
    local font_size = self.doc_font_size - 2

    -- We want to display the footnote text with the same margins as
    -- the document, but keep the scrollbar in the right margin, so
    -- both small footnotes (without scrollbar) and longer ones (with
    -- scrollbar) have their text aligned with the document text.
    -- MuPDF, when rendering some footnotes, may put list item
    -- bullets in its own left margin. To get a chance to have them
    -- shown, we let MuPDF handle our left margin.
    local html_left_margin = self.doc_margins.left .. "px"
    local css = T(PAGE_CSS, "0", "0", "0", html_left_margin, -- top right bottom left
                    self.font_face, DEFAULT_CSS)
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

    self.htmlwidget = ScrollHtmlWidget:new{
        html_body = self.html,
        css = css,
        default_font_size = font_size,
        width = htmlwidget_width,
        height = htmlwidget_height,
        scroll_bar_width = scroll_bar_width,
        text_scroll_span = text_scroll_span,
        dialog = self.dialog,
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
        -- added_bottom_pad = font_size * 0.2
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
    return true
end

function FootnoteWidget:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.container.dimen) then
        self:onClose()
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
    if ges.direction == "west" then
        if self.follow_callback then
            if self.close_callback then
                self.close_callback(self.height)
            end
            return self.follow_callback()
        end
    elseif ges.direction == "south" or ges.direction == "east" then
        -- We can close with swipe down. If footnote is scrollable,
        -- this event will be eaten by ScrollHtmlWidget, and it will
        -- work only when started outside the footnote.
        -- Also allow closing with swipe east (like we do to go back
        -- from link)
        if self.close_callback then
            self.close_callback(self.height)
        end
        self:onClose()
        return true
    elseif ges.direction == "north" then
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
