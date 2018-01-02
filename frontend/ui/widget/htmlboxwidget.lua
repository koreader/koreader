--[[--
HTML widget (without scroll bars).
--]]

local DrawContext = require("ffi/drawcontext")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Mupdf = require("ffi/mupdf")
local TimeVal = require("ui/timeval")

local HtmlBoxWidget = InputContainer:new{
    bb = nil,
    dimen = nil,
    document = nil,
    page_count = 0,
    page_number = 1,
    hold_start_pos = nil,
    hold_start_tv = nil,
}

function HtmlBoxWidget:setContent(body, css, default_font_size)
    -- fz_set_user_css is tied to the context instead of the document so to easily support multiple
    -- HTML dictionaries with different CSS, we embed the stylesheet into the HTML instead of using
    -- that function.
    local html = "<html>"
    if css then
        html = html .. "<head><style>" .. css .. "</style></head>"
    end
    html = html .. "<body>" .. body .. "</body></html>"

    local ok
    ok, self.document = pcall(Mupdf.openDocumentFromText, html, "html")
    if not ok then
        error(self.document) -- will contain error message
    end

    self.document:layoutDocument(self.dimen.w, self.dimen.h, default_font_size)

    self.page_count = self.document:getPages()
end

function HtmlBoxWidget:_render()
    if self.bb then
        return
    end

    local page = self.document:openPage(self.page_number)
    local dc = DrawContext.new()
    self.bb = page:draw_new(dc, self.dimen.w, self.dimen.h, 0, 0)
    page:close()
end

function HtmlBoxWidget:getSize()
    return self.dimen
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
    self:freeBb()

    self.document:close()
    self.document = nil
end

function HtmlBoxWidget:onCloseWidget()
    -- free when UIManager:close() was called
    self:free()
end

function HtmlBoxWidget:onHoldStartText(_, ges)
    self.hold_start_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }

    self.hold_start_tv = TimeVal.now()

    return true
end

function HtmlBoxWidget:getSelectedText(lines, start_pos, end_pos)
    local found_start = false
    local words = {}

    for _, line in pairs(lines) do
        for _, w in pairs(line) do
            if type(w) == 'table' then
                if (not found_start) and
                    (start_pos.x >= w.x0 and start_pos.x < w.x1 and start_pos.y >= w.y0 and start_pos.y < w.y1) then
                    found_start = true
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
    local end_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }

    self.hold_start_pos = nil

    -- check start and end coordinates are actually inside our area
    if start_pos.x < 0 or end_pos.x < 0 or
        start_pos.x >= self.dimen.w or end_pos.x >= self.dimen.w or
        start_pos.y < 0 or end_pos.y < 0 or
        start_pos.y >= self.dimen.h or end_pos.y >= self.dimen.h then
        return false
    end

    local hold_duration = TimeVal.now() - self.hold_start_tv
    hold_duration = hold_duration.sec + (hold_duration.usec/1000000)

    local page = self.document:openPage(self.page_number)
    local lines = page:getPageText()
    page:close()

    local words = self:getSelectedText(lines, start_pos, end_pos)
    local selected_text = table.concat(words, " ")
    callback(selected_text, hold_duration)

    return true
end

return HtmlBoxWidget
