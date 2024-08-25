--[[--
HTML widget (without scroll bars).
--]]

local Device = require("device")
local DrawContext = require("ffi/drawcontext")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Mupdf = require("ffi/mupdf")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")
local util  = require("util")

local HtmlBoxWidget = InputContainer:extend{
    bb = nil,
    dimen = nil,
    document = nil,
    page_count = 0,
    page_number = 1,
    hold_start_pos = nil,
    hold_start_time = nil,
    html_link_tapped_callback = nil,
}

function HtmlBoxWidget:init()
    if Device:isTouchDevice() then
        self.ges_events.TapText = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        }
    end
end

-- These are generic "fixes" to MuPDF HTML stylesheet:
-- - MuPDF doesn't set some elements as being display:block, and would
--   consider them inline, and would badly handle <BR/> inside them.
--   Note: this is a generic issue with <BR/> inside inline elements, see:
--   https://github.com/koreader/koreader/issues/12258#issuecomment-2267629234
local mupdf_css_fixes = [[
article, aside, button, canvas, datalist, details, dialog, dir, fieldset, figcaption,
figure, footer, form, frame, frameset, header, hgroup, iframe, legend, listing,
main, map, marquee, multicol, nav, noembed, noframes, noscript, optgroup, output,
plaintext, search, select, summary, template, textarea, video, xmp {
  display: block;
}
]]

function HtmlBoxWidget:setContent(body, css, default_font_size, is_xhtml, no_css_fixes)
    -- fz_set_user_css is tied to the context instead of the document so to easily support multiple
    -- HTML dictionaries with different CSS, we embed the stylesheet into the HTML instead of using
    -- that function.
    local head = ""
    if css or not no_css_fixes then
        head = string.format("<head><style>\n%s\n%s</style></head>", mupdf_css_fixes, css or "")
    end
    local html = string.format("<html>%s<body>%s</body></html>", head, body)

    -- For some reason in MuPDF <br/> always creates both a line break and an empty line, so we have to
    -- simulate the normal <br/> behavior.
    -- https://bugs.ghostscript.com/show_bug.cgi?id=698351
    html = html:gsub("%<br ?/?%>", "&nbsp;<div></div>")

    -- We can provide some "magic"/"mimetype" to Mupdf.openDocumentFromText():
    -- - "html" will get MuPDF to use its bundled gumbo-parser to parse HTML5 according to the specs.
    -- - "xhtml" will get MuPDF to use its own XML parser, and if it fails, to switch to gumbo-parser.
    -- When we know the body is balanced XHTML, it's safer to use "xhtml" to avoid the HTML5
    -- rules to trigger (ie. <title><p>123</p></title>, which is valid in FB2 snippets, parsed
    -- as title>p, while gumbo-parse would consider "<p>123</p>" as being plain text).
    local ok
    ok, self.document = pcall(Mupdf.openDocumentFromText, html, is_xhtml and "xhtml" or "html")
    if not ok then
        -- self.document contains the error
        logger.warn("HTML loading error:", self.document)

        body = util.htmlToPlainText(body)
        body = util.htmlEscape(body)
        -- Normally \n would be replaced with <br/>. See the previous comment regarding the bug in MuPDF.
        body = body:gsub("\n", "&nbsp;<div></div>")
        html = string.format("<html>%s<body>%s</body></html>", head, body)

        ok, self.document = pcall(Mupdf.openDocumentFromText, html, "html")
        if not ok then
            error(self.document)
        end
    end

    self.document:layoutDocument(self.dimen.w, self.dimen.h, default_font_size)

    self.page_count = self.document:getPages()
end

function HtmlBoxWidget:_render()
    if self.bb then
        return
    end
    local page = self.document:openPage(self.page_number)
    self.document:setColorRendering(Screen:isColorEnabled())
    local dc = DrawContext.new()
    self.bb = page:draw_new(dc, self.dimen.w, self.dimen.h, 0, 0)
    page:close()
end

function HtmlBoxWidget:getSize()
    return self.dimen
end

function HtmlBoxWidget:getSinglePageHeight()
    if self.page_count == 1 then
        local page = self.document:openPage(1)
        local x0, y0, x1, y1 = page:getUsedBBox() -- luacheck: no unused
        page:close()
        return math.ceil(y1) -- no content after y1
    end
end

function HtmlBoxWidget:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    self:_render()

    local size = self:getSize()

    bb:blitFrom(self.bb, x, y, 0, 0, size.w, size.h)
end

function HtmlBoxWidget:freeBb()
    if self.bb and self.bb.free then
        self.bb:free()
    end

    self.bb = nil
end

-- This will normally be called by our WidgetContainer:free()
-- But it SHOULD explicitly be called if we are getting replaced
-- (ie: in some other widget's update()), to not leak memory with
-- BlitBuffer zombies
function HtmlBoxWidget:free()
    --print("HtmlBoxWidget:free on", self)
    self:freeBb()

    if self.document then
        self.document:close()
        self.document = nil
    end
end

function HtmlBoxWidget:onCloseWidget()
    -- free when UIManager:close() was called
    self:free()
end

function HtmlBoxWidget:getPosFromAbsPos(abs_pos)
    local pos = Geom:new{
        x = abs_pos.x - self.dimen.x,
        y = abs_pos.y - self.dimen.y,
    }

    -- check if the coordinates are actually inside our area
    if pos.x < 0 or pos.x >= self.dimen.w or pos.y < 0 or pos.y >= self.dimen.h then
        return nil
    end

    return pos
end

function HtmlBoxWidget:onHoldStartText(_, ges)
    self.hold_start_pos = self:getPosFromAbsPos(ges.pos)

    if not self.hold_start_pos then
        return false -- let event be processed by other widgets
    end

    self.hold_start_time = UIManager:getTime()

    return true
end

function HtmlBoxWidget:onHoldPan(_, ges)
    -- We don't highlight the currently selected text, but just let this
    -- event pop up if we are not currently selecting text
    if not self.hold_start_pos then
        return false
    end
    return true
end

function HtmlBoxWidget:getSelectedText(lines, start_pos, end_pos)
    local found_start = false
    local words = {}

    for _, line in ipairs(lines) do
        for _, w in ipairs(line) do
            if type(w) == 'table' then
                if not found_start then
                    if start_pos.x >= w.x0 and start_pos.x < w.x1 and start_pos.y >= w.y0 and start_pos.y < w.y1 then
                        found_start = true
                    elseif end_pos.x >= w.x0 and end_pos.x < w.x1 and end_pos.y >= w.y0 and end_pos.y < w.y1 then
                        -- We found end_pos before start_pos, switch them
                        found_start = true
                        start_pos, end_pos = end_pos, start_pos
                    end
                end

                if found_start then
                    table.insert(words, w.word)

                    -- Found the end.
                    if end_pos.x >= w.x0 and end_pos.x < w.x1 and end_pos.y >= w.y0 and end_pos.y < w.y1 then
                        return words
                    end
                end
            end
        end
    end

    return words
end

function HtmlBoxWidget:onHoldReleaseText(callback, ges)
    if not callback then
        return false
    end

    -- check we have seen a HoldStart event
    if not self.hold_start_pos then
        return false
    end

    local start_pos = self.hold_start_pos
    self.hold_start_pos = nil

    local end_pos = self:getPosFromAbsPos(ges.pos)
    if not end_pos then
        return false
    end

    local hold_duration = time.now() - self.hold_start_time

    local page = self.document:openPage(self.page_number)
    local lines = page:getPageText()
    page:close()

    local words = self:getSelectedText(lines, start_pos, end_pos)
    local selected_text = table.concat(words, " ")
    callback(selected_text, hold_duration)

    return true
end

function HtmlBoxWidget:getLinkByPosition(pos)
    local page = self.document:openPage(self.page_number)
    local links = page:getPageLinks()
    page:close()

    for _, link in ipairs(links) do
        if pos.x >= link.x0 and pos.x < link.x1 and pos.y >= link.y0 and pos.y < link.y1 then
            return link
        end
    end
end

function HtmlBoxWidget:onTapText(arg, ges)
    if G_reader_settings:isFalse("tap_to_follow_links") then
        return
    end

    if self.html_link_tapped_callback then
        local pos = self:getPosFromAbsPos(ges.pos)
        if pos then
            local link = self:getLinkByPosition(pos)
            if link then
                self.html_link_tapped_callback(link)
                return true
            end
        end
    end
end

return HtmlBoxWidget
