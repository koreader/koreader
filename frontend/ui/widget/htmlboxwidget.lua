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

-- -1: right to left, 0: mixed, +1: left to right
local function getLineTextDirection(line)
    local word_count = #line
    if word_count <= 1 then
        return 1
    end

    local ltr = true
    local rtl = true
    for i = 2, word_count do
        if line[i].x0 > line[i - 1].x0 then
            rtl = false
        elseif line[i].x0 < line[i - 1].x0 then
            ltr = false
        end
    end
    if ltr and not rtl then
        return 1
    elseif rtl and not ltr then
        return -1
    else
        return 0
    end
end

local function getWordIndices(lines, pos)
    local last_checked_line_index = nil
    for line_index, line in ipairs(lines) do
        if pos.y >= line.y0 then -- check if pos in on or below the line
            if pos.y < line.y1 then -- check if pos is within the line vertically
                local rtl_line = getLineTextDirection(line) < 0
                if pos.x >= line.x0 and pos.x < line.x1 then -- check if pos is within the line horizontally
                    if #line >= 1 then -- if line is not empty then check for exact word hit
                        local word_start_index = 1
                        local word_end_index = #line
                        local step = 1
                        if rtl_line then
                            word_start_index, word_end_index = word_end_index, word_start_index
                            step = -1
                        end

                        local word_x0 = line[word_start_index].x0
                        for word_index = word_start_index, word_end_index, step do
                            local word = line[word_index]
                            if pos.x >= word_x0 and pos.x < word.x1 then
                                return line_index, word_index
                            end

                            -- join the word rectangles horizontally to avoid hit gaps
                            word_x0 = word.x1
                        end
                    end
                elseif pos.x < line.x0 then -- check if pos is before the current line horizontally
                    if rtl_line then
                        return line_index, #line
                    else
                        return line_index, 1
                    end
                elseif pos.x >= line.x1 then -- check if pos after the current line horizontally
                    if rtl_line then
                        -- To match TextBoxWidget's selection behavior this should be "line_index, 1"
                        -- but then the selection will jump between the full row and the visually
                        -- last word when hitting a vertical gap. If we extend the line vertically
                        -- till the next one then selection will be weird around new paragraphs.
                        -- The solution might require getPageText() to add empty lines.
                        return line_index, #line
                    else
                        return line_index, #line
                    end
                end
            end

            last_checked_line_index = line_index
        end
    end

    if last_checked_line_index == nil then
        return 1, 1
    else
        return last_checked_line_index, #lines[last_checked_line_index]
    end
end

local function getSelectedText(lines, start_pos, end_pos)
    local start_line_index, start_word_index = getWordIndices(lines, start_pos)
    local end_line_index, end_word_index = getWordIndices(lines, end_pos)
    if start_line_index == nil or end_line_index == nil then
        return nil, nil
    elseif start_line_index > end_line_index then
        start_line_index, end_line_index = end_line_index, start_line_index
        start_word_index, end_word_index = end_word_index, start_word_index
    elseif start_line_index == end_line_index and start_word_index > end_word_index then
        start_word_index, end_word_index = end_word_index, start_word_index
    end

    local found_start = false
    local words = {}
    local rects = {}
    for line_index = start_line_index, end_line_index do
        local line = lines[line_index]
        local line_last_rect = nil
        local line_text_direction = getLineTextDirection(line)
        for word_index, word in ipairs(line) do
            if type(word) == 'table' then
                if line_index == start_line_index and word_index == start_word_index then
                    found_start = true
                end
                if found_start then
                    table.insert(words, word.word)

                    -- do not try to join word rects in mixed direction lines
                    if line_last_rect == nil or line_text_direction == 0 then
                        local rect = Geom:new{
                            x = word.x0,
                            y = line.y0,
                            w = word.x1 - word.x0,
                            h = line.y1 - line.y0,
                        }
                        table.insert(rects, rect)
                        line_last_rect = rect
                    else
                        if line_text_direction > 0 then -- left to right
                            line_last_rect.w = word.x1 - line_last_rect.x
                        else -- right to left
                            line_last_rect.w = line_last_rect.w + (line_last_rect.x - word.x0)
                            line_last_rect.x = word.x0
                        end
                    end

                    if line_index == end_line_index and word_index == end_word_index then
                        break
                    end
                end
            end
        end
    end

    if found_start then
        return table.concat(words, " "), rects
    else
        return nil, nil
    end
end

local function areTextBoxesEqual(boxes1, text1, boxes2, text2)
    if text1 ~= text2 then
        return false
    end
    if boxes1 and boxes2 then
        if #boxes1 ~= #boxes2 then
            return false
        end
        for i = 1, #boxes1, 1 do
            if boxes1[i] ~= boxes2[i] then
                return false
            end
        end
        return true
    else
        return (boxes1 == nil) == (boxes2 == nil)
    end
end

local HtmlBoxWidget = InputContainer:extend{
    bb = nil,
    dimen = nil,
    dialog = nil, -- parent dialog that will be set dirty
    document = nil,
    page_count = 0,
    page_number = 1,
    page_boxes = nil,
    hold_start_pos = nil,
    hold_end_pos = nil,
    hold_start_time = nil,
    html_link_tapped_callback = nil,

    highlight_text_selection = false, -- if true then the selected text will be highlighted
    highlight_rects = nil,
    highlight_text = nil,
    highlight_clear_and_redraw_action = nil,
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
    self.highlight_lighten_factor = G_reader_settings:readSetting("highlight_lighten_factor", 0.2)
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

function HtmlBoxWidget:setContent(body, css, default_font_size, is_xhtml, no_css_fixes, html_resource_directory)
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
    ok, self.document = pcall(Mupdf.openDocumentFromText, html, is_xhtml and "xhtml" or "html", html_resource_directory)
    if not ok then
        -- self.document contains the error
        logger.warn("HTML loading error:", self.document)

        body = util.htmlToPlainText(body)
        body = util.htmlEscape(body)
        -- Normally \n would be replaced with <br/>. See the previous comment regarding the bug in MuPDF.
        body = body:gsub("\n", "&nbsp;<div></div>")
        html = string.format("<html>%s<body>%s</body></html>", head, body)

        ok, self.document = pcall(Mupdf.openDocumentFromText, html, "html", html_resource_directory)
        if not ok then
            error(self.document)
        end
    end

    self.document:layoutDocument(self.dimen.w, self.dimen.h, default_font_size)

    self.page_count = self.document:getPages()
    self.page_boxes = nil
    self:clearHighlight()
end

--- Use the raw content as given, without any string manipulation to try to improve MuPDF compatibility or rendering.
--- @string body Content to be rendered in a supported format like (X)HTML or SVG.
--- @string magic Used to detect document type, like a file name or mime-type.
--- @number default_font_size Default font size to use for layout, only for some formats like HTML.
--- @string resource_directory Directory to use for resolving relative resource paths.
function HtmlBoxWidget:setRawContent(body, magic, default_font_size, resource_directory)
    local ok
    ok, self.document = pcall(Mupdf.openDocumentFromText, body, magic, resource_directory)
    if not ok then
        logger.warn("Raw content loading error:", self.document)
        return nil, self.document
    end

    self.document:layoutDocument(self.dimen.w, self.dimen.h, default_font_size)

    self.page_count = self.document:getPages()
    self.page_boxes = nil
    self:clearHighlight()
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

    if self.highlight_text_selection and self.highlight_rects then
        for _, rect in ipairs(self.highlight_rects) do
            self.bb:darkenRect(rect.x, rect.y, rect.w, rect.h, self.highlight_lighten_factor)
        end
    end
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
    self:unscheduleClearHighlightAndRedraw()
    self.hold_start_pos = self:getPosFromAbsPos(ges.pos)
    self.hold_end_pos = self.hold_start_pos
    self.highlight_rects = nil
    self.highlight_text = nil

    if not self.hold_start_pos then
        return false -- let event be processed by other widgets
    end

    self.hold_start_time = UIManager:getTime()

    if self:updateHighlight() then
        self:redrawHighlight()
    end

    return true
end

function HtmlBoxWidget:onHoldPanText(_, ges)
    -- We don't highlight the currently selected text, but just let this
    -- event pop up if we are not currently selecting text
    if not self.hold_start_pos then
        return false
    end

    self.hold_end_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }

    if self:updateHighlight() then
        self.hold_start_time = UIManager:getTime()
        self:redrawHighlight()
    end

    return true
end

function HtmlBoxWidget:onHoldReleaseText(callback, ges)
    if not callback then
        return false
    end

    -- check we have seen a HoldStart event
    if not self.hold_start_pos then
        return false
    end

    self.hold_end_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }

    if self:updateHighlight() then
        self:redrawHighlight()
    end

    if not self.highlight_text then
        return false
    end

    local hold_duration = time.now() - self.hold_start_time
    callback(self.highlight_text, hold_duration)

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

function HtmlBoxWidget:setPageNumber(page_number)
    if page_number == self.page_number then
        return
    end
    self.page_number = page_number
    self.page_boxes = nil
    self:clearHighlight()
end

-- Returns true if the highlight has changed.
function HtmlBoxWidget:clearHighlight()
    self.hold_start_pos = nil
    self.hold_end_pos = nil
    return self:updateHighlight()
end

-- Returns true if the highlight has changed.
function HtmlBoxWidget:updateHighlight()
    if self.hold_start_pos and self.hold_end_pos then
        -- getPageText is slow so we only call it when needed, and keep the result.
        if self.page_boxes == nil then
            local page = self.document:openPage(self.page_number)
            self.page_boxes = page:getPageText()

            -- In same cases MuPDF returns a visually single line of text as multiple lines.
            -- Merge such lines to ensure that getSelectedText works properly.
            local line_index = 2
            while line_index <= #self.page_boxes do
                local prev_line = self.page_boxes[line_index - 1]
                local line = self.page_boxes[line_index]
                if line.y0 == prev_line.y0 and line.y1 == prev_line.y1 then
                    if line.x0 < prev_line.x0 then
                        prev_line.x0 = line.x0
                    end
                    if line.x1 > prev_line.x1 then
                        prev_line.x1 = line.x1
                    end
                    for _, word in ipairs(line) do
                        table.insert(prev_line, word)
                    end
                    table.remove(self.page_boxes, line_index)
                else
                    line_index = line_index + 1
                end
            end

            page:close()
        end

        local text, rects = getSelectedText(self.page_boxes, self.hold_start_pos, self.hold_end_pos)
        local changed = not areTextBoxesEqual(self.highlight_rects, self.highlight_text, rects, text)
        if changed then
            self.highlight_rects = rects
            self.highlight_text = text
        end
        return changed
    else
        local changed = self.highlight_rects ~= nil
        self.highlight_rects = nil
        self.highlight_text = nil
        return changed
    end
end

function HtmlBoxWidget:redrawHighlight()
    if self.highlight_text_selection then
        self:freeBb()
        UIManager:setDirty(self.dialog or "all", function()
            return "ui", self.dimen
        end)
    end
end

function HtmlBoxWidget:scheduleClearHighlightAndRedraw()
    if self.highlight_clear_and_redraw_action then
        return
    end

    self.highlight_clear_and_redraw_action = function ()
        self.highlight_clear_and_redraw_action = nil
        if self:clearHighlight() then
            self:redrawHighlight()
        end
    end
    UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), self.highlight_clear_and_redraw_action)
end

function HtmlBoxWidget:unscheduleClearHighlightAndRedraw()
    if self.highlight_clear_and_redraw_action then
        UIManager:unschedule(self.highlight_clear_and_redraw_action)
        self.highlight_clear_and_redraw_action = nil
    end
end

return HtmlBoxWidget
