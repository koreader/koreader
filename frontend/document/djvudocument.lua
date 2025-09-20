local Blitbuffer = require("ffi/blitbuffer")
local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")

local DjvuDocument = Document:extend{
    _document = false,
    -- libdjvulibre manages its own additional cache, default value is hard written in c module.
    is_djvu = true,
    djvulibre_cache_size = nil,
    dc_null = DrawContext.new(),
    koptinterface = nil,
    color_bb_type = Blitbuffer.TYPE_BBRGB24,
    provider = "djvulibre",
    provider_name = "DjVu Libre",
}

-- check DjVu magic string to validate
local function validDjvuFile(filename)
    local f = io.open(filename, "r")
    if not f then return false end
    local magic = f:read(8)
    f:close()
    if not magic or magic ~= "AT&TFORM" then return false end
    return true
end

function DjvuDocument:init()
    local djvu = require("libs/libkoreader-djvu")
    self.koptinterface = require("document/koptinterface")
    self.koptinterface:setDefaultConfigurable(self.configurable)
    if not validDjvuFile(self.file) then
        error("Not a valid DjVu file")
    end

    local ok
    ok, self._document = pcall(djvu.openDocument, self.file, self.render_color, self.djvulibre_cache_size)
    if not ok then
        error(self._document)  -- will contain error message
    end
    self:updateColorRendering()
    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = true
    self.render_mode = 0
    self:_readMetadata()
end

function DjvuDocument:updateColorRendering()
    Document.updateColorRendering(self) -- will set self.render_color
    if self._document then
        self._document:setColorRendering(self.render_color)
    end
end

function DjvuDocument:comparePositions(pos1, pos2)
    return self.koptinterface:comparePositions(self, pos1, pos2)
end

-- Performance is better pre-allocated than as table.sort(tbl, function() … end).
local function compareByX(a, b) return a.x0 < b.x0 end
local function compareByYThenX(a, b)
    if a.y0 - b.y0 == 0 then return a.x0 < b.x0 end
    return a.y0 < b.y0
end

--- Recursively collect valid word leaves under node.
local function collectWords(node, words)
    if node.word then
        words[#words + 1] = node
        return words
    end
    for i = 1, #node do
        collectWords(node[i], words)
    end
    return words
end

--- X-only sort that tries to avoid sorting when already ordered.
local function sortWordsByX(words)
    local n = #words
    if n < 2 then return end
    local prev = words[1].x0
    for i = 2, n do
        local x = words[i].x0
        if prev > x then
            table.sort(words, compareByX)
            return
        end
        prev = x
    end
end

--- Collect only direct word children (no recursion).
local function collectDirectWords(node, words)
    for i = 1, #node do
        local child = node[i]
        if child.word then
            words[#words + 1] = child
        end
    end
    return words
end

local function hasDirectWordChildren(node)
    for i = 1, #node do
        if node[i].word then return true end
    end
    return false
end

local function groupWordsIntoLines(words)
    if #words == 0 then return {} end
    -- Sort by y (top to bottom), then x (left to right)
    table.sort(words, compareByYThenX)
    -- Estimate a dynamic threshold based on word heights
    local sum_h = 0
    for i = 1, #words do sum_h = sum_h + math.floor((words[i].y1 - words[i].y0) + 0.5) end
    local avg_h = sum_h / #words
    local threshold = math.max(2, math.floor(avg_h * 0.5 + 0.5))
    local lines = {}
    local current = { words[1] }
    local current_y = (words[1].y0 + words[1].y1) / 2
    for i = 2, #words do
        local w = words[i]
        local wy = (w.y0 + w.y1) / 2
        if math.abs(wy - current_y) <= threshold then
            current[#current + 1] = w
            -- refine line y by incremental average to be robust to slight drifts
            current_y = current_y + (wy - current_y) / #current
        else
            lines[#lines + 1] = current
            current = { w }
            current_y = wy
        end
    end
    lines[#lines + 1] = current
    return lines
end

local function computeBboxFromWords(words)
    local w0 = words[1]
    local minx, miny, maxx, maxy = w0.x0, w0.y0, w0.x1, w0.y1
    for i = 2, #words do
        local w = words[i]
        local x0, y0, x1, y1 = w.x0, w.y0, w.x1, w.y1
        if x0 < minx then minx = x0 end
        if y0 < miny then miny = y0 end
        if x1 > maxx then maxx = x1 end
        if y1 > maxy then maxy = y1 end
    end
    return minx, miny, maxx, maxy
end

local function setLineBbox(line_tbl)
    local x0, y0, x1, y1 = computeBboxFromWords(line_tbl)
    line_tbl.x0, line_tbl.y0, line_tbl.x1, line_tbl.y1 = x0, y0, x1, y1
end

function DjvuDocument:getPageTextBoxes(pageno)
    local page_text = self._document:getPageText(pageno)
    -- DjVu text layers can be nested (page -> columns -> regions -> paragraphs -> lines -> words).
    -- Flatten them into an array of lines, each an array of word boxes { x0, y0, x1, y1, word }.
    local lines = {}

    local function walk(node)
        -- "For instance, the page level component might only specify a page level string, or might only provide a list of lines, or might provide a full hierarchy down to the individual characters."
        if node.line then
            local words = collectWords(node, {})
            if #words > 0 then
                sortWordsByX(words)
                setLineBbox(words)
                lines[#lines + 1] = words
            end
            return
        -- If a container directly holds words but isn't a line, split them into multiple lines.
        elseif hasDirectWordChildren(node) then
            -- Only handle direct words here to avoid double-processing nested structures.
            local words = collectDirectWords(node, {})
            if #words > 0 then
                local groups = groupWordsIntoLines(words)
                for i = 1, #groups do
                    setLineBbox(groups[i])
                    lines[#lines + 1] = groups[i]
                end
            end
            -- Continue walking non-word children to handle nested containers.
            for i = 1, #node do
                local child = node[i]
                if type(child) == "table" and not child.word then
                    walk(child)
                end
            end
            return
        end
        for i = 1, #node do
            local child = node[i]
            if child then walk(child) end
        end
    end
    walk(page_text)
    -- Use explicit line zones if now present.
    if #lines > 0 then
        return lines
    end
    -- No explicit line nodes: group all words heuristically by y.
    local all_words = collectWords(page_text, {})
    local grouped = groupWordsIntoLines(all_words)
    for i = 1, #grouped do setLineBbox(grouped[i]) end
    return grouped
end

function DjvuDocument:getTextBoxes(pageno)
    return self.koptinterface:getTextBoxes(self, pageno)
end

function DjvuDocument:getPanelFromPage(pageno, pos)
    return self.koptinterface:getPanelFromPage(self, pageno, pos)
end

function DjvuDocument:getWordFromPosition(spos)
    return self.koptinterface:getWordFromPosition(self, spos)
end

function DjvuDocument:getTextFromPositions(spos0, spos1)
    return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function DjvuDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
    return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function DjvuDocument:nativeToPageRectTransform(pageno, rect)
    return self.koptinterface:nativeToPageRectTransform(self, pageno, rect)
end

function DjvuDocument:getSelectedWordContext(word, nb_words, pos)
    return self.koptinterface:getSelectedWordContext(word, nb_words, pos)
end

function DjvuDocument:getOCRWord(pageno, wbox)
    return self.koptinterface:getOCRWord(self, pageno, wbox)
end

function DjvuDocument:getOCRText(pageno, tboxes)
    return self.koptinterface:getOCRText(self, pageno, tboxes)
end

function DjvuDocument:getPageBlock(pageno, x, y)
    return self.koptinterface:getPageBlock(self, pageno, x, y)
end

function DjvuDocument:getUsedBBox(pageno)
    -- djvu does not support usedbbox, so fake it.
    local used = {}
    local native_dim = self:getNativePageDimensions(pageno)
    used.x0, used.y0, used.x1, used.y1 = 0, 0, native_dim.w, native_dim.h
    return used
end

function DjvuDocument:clipPagePNGFile(pos0, pos1, pboxes, drawer, filename)
    return self.koptinterface:clipPagePNGFile(self, pos0, pos1, pboxes, drawer, filename)
end

function DjvuDocument:clipPagePNGString(pos0, pos1, pboxes, drawer)
    return self.koptinterface:clipPagePNGString(self, pos0, pos1, pboxes, drawer)
end

function DjvuDocument:getPageBBox(pageno)
    return self.koptinterface:getPageBBox(self, pageno)
end

function DjvuDocument:getPageDimensions(pageno, zoom, rotation)
    return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
end

function DjvuDocument:getCoverPageImage()
    return self.koptinterface:getCoverPageImage(self)
end

function DjvuDocument:findText(pattern, origin, reverse, case_insensitive, page)
    return self.koptinterface:findText(self, pattern, origin, reverse, case_insensitive, page)
end

function DjvuDocument:findAllText(pattern, case_insensitive, nb_context_words, max_hits)
    return self.koptinterface:findAllText(self, pattern, case_insensitive, nb_context_words, max_hits)
end

function DjvuDocument:renderPage(pageno, rect, zoom, rotation, gamma, hinting)
    return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, hinting)
end

function DjvuDocument:hintPage(pageno, zoom, rotation, gamma)
    return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma)
end

function DjvuDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma)
    return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma)
end

function DjvuDocument:register(registry)
    registry:addProvider("djvu", "image/vnd.djvu", self, 100)
    registry:addProvider("djvu", "application/djvu", self, 100) -- Alternative mimetype for OPDS.
    registry:addProvider("djvu", "image/x-djvu", self, 100) -- Alternative mimetype for OPDS.
    registry:addProvider("djv", "image/vnd.djvu", self, 100)
end

return DjvuDocument
