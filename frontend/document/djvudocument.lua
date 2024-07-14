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

function DjvuDocument:getPageTextBoxes(pageno)
    return self._document:getPageText(pageno)
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
