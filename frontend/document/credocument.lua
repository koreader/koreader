local Blitbuffer = require("ffi/blitbuffer")
local CreOptions = require("ui/data/creoptions")
local DataStorage = require("datastorage")
local Document = require("document/document")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- engine can be initialized only once, on first document opened
local engine_initialized = false

local CreDocument = Document:new{
    -- this is defined in kpvcrlib/crengine/crengine/include/lvdocview.h
    SCROLL_VIEW_MODE = 0,
    PAGE_VIEW_MODE = 1,

    _document = false,
    _loaded = false,

    line_space_percent = 100,
    default_font = G_reader_settings:readSetting("cre_font") or "Noto Serif",
    header_font = G_reader_settings:readSetting("header_font") or "Noto Sans",
    fallback_font = G_reader_settings:readSetting("fallback_font") or "Noto Sans CJK SC",
    default_css = "./data/cr3.css",
    options = CreOptions,
}

-- NuPogodi, 20.05.12: inspect the zipfile content
function CreDocument:zipContentExt(fname)
    local std_out = io.popen("unzip ".."-qql \""..fname.."\"")
    if std_out then
        for line in std_out:lines() do
            local size, ext = string.match(line, "%s+(%d+)%s+.+%.([^.]+)")
            -- return the extention
            if size and ext then return string.lower(ext) end
        end
    end
end

function CreDocument:cacheInit()
    -- remove legacy cr3cache directory
    if lfs.attributes("./cr3cache", "mode") == "directory" then
        os.execute("rm -r ./cr3cache")
    end
    cre.initCache(DataStorage:getDataDir() .. "/cache/cr3cache", 1024*1024*32)
end

function CreDocument:engineInit()
    if not engine_initialized then
        require "libs/libkoreader-cre"
        -- initialize cache
        self:cacheInit()

        -- initialize hyph dictionaries
        cre.initHyphDict("./data/hyph/")

        -- we need to initialize the CRE font list
        local fonts = Font:getFontList()
        for _k, _v in ipairs(fonts) do
            if not _v:find("/urw/") then
                local ok, err = pcall(cre.registerFont, _v)
                if not ok then
                    logger.err("failed to register crengine font", err)
                end
            end
        end

        engine_initialized = true
    end
end

function CreDocument:init()
    self:updateColorRendering()
    self:engineInit()
    self.configurable:loadDefaults(self.options)

    local file_type = string.lower(string.match(self.file, ".+%.([^.]+)"))
    if file_type == "zip" then
        -- NuPogodi, 20.05.12: read the content of zip-file
        -- and return extention of the 1st file
        file_type = self:zipContentExt(self.file) or "unknown"
    end
    -- these two format use the same css file
    if file_type == "html" then
        file_type = "htm"
    end
    -- if native css-file doesn't exist, one needs to use default cr3.css
    if not io.open("./data/"..file_type..".css") then
        file_type = "cr3"
    end
    self.default_css = "./data/"..file_type..".css"

    -- @TODO check the default view_mode to a global user configurable
    -- variable  22.12 2012 (houqp)
    local ok
    ok, self._document = pcall(cre.newDocView, Screen:getWidth(), Screen:getHeight(),
        DCREREADER_VIEW_MODE == "scroll" and self.SCROLL_VIEW_MODE or self.PAGE_VIEW_MODE
    ) -- this mode must be the same as the default one set as ReaderView.view_mode
    if not ok then
        error(self._document)  -- will contain error message
    end

    -- adjust font sizes according to screen dpi
    self._document:adjustFontSizes(Screen:getDPI())

    -- set fallback font face
    self._document:setStringProperty("crengine.font.fallback.face", self.fallback_font)

    -- We would have liked to call self._document:loadDocument(self.file)
    -- here, to detect early if file is a supported document, but we
    -- need to delay it till after some crengine settings are set for a
    -- consistent behaviour.

    self.is_open = true
    self.info.has_pages = false
    self:_readMetadata()
    self.info.configurable = true
end

function CreDocument:loadDocument()
    if not self._loaded then
        if self._document:loadDocument(self.file) then
            self._loaded = true
        end
    end
    return self._loaded
end

function CreDocument:render()
    -- load document before rendering
    self:loadDocument()
    -- set visible page count in landscape
    if math.max(Screen:getWidth(), Screen:getHeight()) / Screen:getDPI()
        < DCREREADER_TWO_PAGE_THRESHOLD then
        self:setVisiblePageCount(1)
    end
    self._document:renderDocument()
    if not self.info.has_pages then
        self.info.doc_height = self._document:getFullHeight()
    end
end

function CreDocument:close()
    Document.close(self)
    if self.buffer then
        self.buffer:free()
        self.buffer = nil
    end
end

function CreDocument:updateColorRendering()
    Document.updateColorRendering(self) -- will set self.render_color
    -- Delete current buffer, a new one will be created according
    -- to self.render_color
    if self.buffer then
        self.buffer:free()
        self.buffer = nil
    end
end

function CreDocument:getPageCount()
    return self._document:getPages()
end

function CreDocument:getCoverPageImage()
    -- don't need to render document in order to get cover image
    if not self:loadDocument() then
        return nil -- not recognized by crengine
    end
    local data, size = self._document:getCoverPageImageData()
    if data and size then
        local Mupdf = require("ffi/mupdf")
        local ok, image = pcall(Mupdf.renderImage, data, size)
        ffi.C.free(data)
        if ok then
            return image
        end
    end
end

function CreDocument:getImageFromPosition(pos)
    local data, size = self._document:getImageDataFromPosition(pos.x, pos.y)
    if data and size then
        logger.dbg("CreDocument: got image data from position", data, size)
        local Mupdf = require("ffi/mupdf")
        -- wrapped with pcall so we always free(data)
        local ok, image = pcall(Mupdf.renderImage, data, size)
        logger.dbg("Mupdf.renderImage", ok, image)
        if not ok and string.find(image, "could not load image data: unknown image file format") then
            -- in that case, mupdf seems to have already freed data (see mupdf/source/fitz/image.c:494),
            -- as doing outselves ffi.C.free(data) would result in a crash with :
            -- *** Error in `./luajit': double free or corruption (!prev): 0x0000000000e48a40 ***
            logger.warn("Mupdf says 'unknown image file format', assuming mupdf has already freed image data")
        else
            ffi.C.free(data) -- need that explicite clean
        end
        if ok then
            return image
        end
    end
end

function CreDocument:getWordFromPosition(pos)
    local word_box = self._document:getWordFromPosition(pos.x, pos.y)
    logger.dbg("CreDocument: get word box", word_box)
    local text_range = self._document:getTextFromPositions(pos.x, pos.y, pos.x, pos.y)
    logger.dbg("CreDocument: get text range", text_range)
    local wordbox = {
        word = text_range.text == "" and word_box.word or text_range.text,
        page = self._document:getCurrentPage(),
    }
    if word_box.word then
        wordbox.sbox = Geom:new{
            x = word_box.x0, y = word_box.y0,
            w = word_box.x1 - word_box.x0,
            h = word_box.y1 - word_box.y0,
        }
    else
        -- dummy word box
        wordbox.sbox = Geom:new{
            x = pos.x, y = pos.y,
            w = 20, h = 20,
        }
    end
    return wordbox
end

function CreDocument:getTextFromPositions(pos0, pos1)
    local text_range = self._document:getTextFromPositions(pos0.x, pos0.y, pos1.x, pos1.y)
    logger.dbg("CreDocument: get text range", text_range)
    if text_range then
        -- local line_boxes = self:getScreenBoxesFromPositions(text_range.pos0, text_range.pos1)
        return {
            text = text_range.text,
            pos0 = text_range.pos0,
            pos1 = text_range.pos1,
            --sboxes = line_boxes,     -- boxes on screen
        }
    end
end

function CreDocument:getScreenBoxesFromPositions(pos0, pos1)
    local line_boxes = {}
    if pos0 and pos1 then
        local word_boxes = self._document:getWordBoxesFromPositions(pos0, pos1)
        for i = 1, #word_boxes do
            local line_box = word_boxes[i]
            table.insert(line_boxes, Geom:new{
                x = line_box.x0, y = line_box.y0,
                w = line_box.x1 - line_box.x0,
                h = line_box.y1 - line_box.y0,
            })
        end
    end
    return line_boxes
end

function CreDocument:drawCurrentView(target, x, y, rect, pos)
    if self.buffer and (self.buffer.w ~= rect.w or self.buffer.h ~= rect.h) then
        self.buffer:free()
        self.buffer = nil
    end
    if not self.buffer then
        -- Note about color rendering:
        -- If we use TYPE_BBRGB32 (and LVColorDrawBuf drawBuf(..., 32) in cre.cpp),
        -- we get inverted Red and Blue in the blitbuffer (could be that
        -- crengine/src/lvdrawbuf.cpp treats our 32bits not as RGBA).
        -- But it is all fine if we use TYPE_BBRGB16.
        self.buffer = Blitbuffer.new(rect.w, rect.h, self.render_color and Blitbuffer.TYPE_BBRGB16 or nil)
    end
    self._document:drawCurrentPage(self.buffer, self.render_color)
    target:blitFrom(self.buffer, x, y, 0, 0, rect.w, rect.h)
end

function CreDocument:drawCurrentViewByPos(target, x, y, rect, pos)
    self._document:gotoPos(pos)
    self:drawCurrentView(target, x, y, rect)
end

function CreDocument:drawCurrentViewByPage(target, x, y, rect, page)
    self._document:gotoPage(page)
    self:drawCurrentView(target, x, y, rect)
end

function CreDocument:hintPage(pageno, zoom, rotation)
end

function CreDocument:drawPage(target, x, y, rect, pageno, zoom, rotation)
end

function CreDocument:renderPage(pageno, rect, zoom, rotation)
end

function CreDocument:gotoXPointer(xpointer)
    logger.dbg("CreDocument: goto xpointer", xpointer)
    self._document:gotoXPointer(xpointer)
end

function CreDocument:getXPointer()
    return self._document:getXPointer()
end

function CreDocument:isXPointerInDocument(xp)
    return self._document:isXPointerInDocument(xp)
end

function CreDocument:getPosFromXPointer(xp)
    return self._document:getPosFromXPointer(xp)
end

function CreDocument:getPageFromXPointer(xp)
    return self._document:getPageFromXPointer(xp)
end

function CreDocument:getFontFace()
    return self._document:getFontFace()
end

function CreDocument:getCurrentPos()
    return self._document:getCurrentPos()
end

function CreDocument:getPageLinks()
    return self._document:getPageLinks()
end

function CreDocument:getLinkFromPosition(pos)
    return self._document:getLinkFromPosition(pos.x, pos.y)
end

function CreDocument:gotoPos(pos)
    logger.dbg("CreDocument: goto position", pos)
    self._document:gotoPos(pos)
end

function CreDocument:gotoPage(page)
    logger.dbg("CreDocument: goto page", page)
    self._document:gotoPage(page)
end

function CreDocument:gotoLink(link)
    logger.dbg("CreDocument: goto link", link)
    self._document:gotoLink(link)
end

function CreDocument:goBack()
    logger.dbg("CreDocument: go back")
    self._document:goBack()
end

function CreDocument:goForward(link)
    logger.dbg("CreDocument: go forward")
    self._document:goForward()
end

function CreDocument:getCurrentPage()
    return self._document:getCurrentPage()
end

function CreDocument:setFontFace(new_font_face)
    if new_font_face then
        logger.dbg("CreDocument: set font face", new_font_face)
        self._document:setStringProperty("font.face.default", new_font_face)

        -- The following makes FontManager prefer this font in its match
        -- algorithm, with the bias given (applies only to rendering of
        -- elements with css font-family)
        -- See: crengine/src/lvfntman.cpp LVFontDef::CalcMatch():
        -- it will compute a score for each font, where it adds:
        --  + 25600 if standard font family matches (inherit serif sans-serif
        --     cursive fantasy monospace) (note that crengine registers all fonts as
        --     "sans-serif", except if their name is "Times" or "Times New Roman")
        --  + 6400 if they don't and none are monospace (ie:serif vs sans-serif,
        --      prefer a sans-serif to a monospace if looking for a serif)
        --  +256000 if font names match
        -- So, here, we can bump the score of our default font, and we could use:
        --      +1: uses existing real font-family, but use our font for
        --          font-family: serif, sans-serif..., and fonts not found (or
        --          embedded fonts disabled)
        --  +25601: uses existing real font-family, but use our font even
        --          for font-family: monospace
        -- +256001: prefer our font to any existing font-family font
        self._document:setAsPreferredFontWithBias(new_font_face, 1)
    end
end

function CreDocument:setHyphDictionary(new_hyph_dictionary)
    if new_hyph_dictionary then
        logger.dbg("CreDocument: set hyphenation dictionary", new_hyph_dictionary)
        self._document:setStringProperty("crengine.hyphenation.directory", new_hyph_dictionary)
    end
end

function CreDocument:clearSelection()
    logger.dbg("clear selection")
    self._document:clearSelection()
end

function CreDocument:getFontSize()
    return self._document:getFontSize()
end

function CreDocument:setFontSize(new_font_size)
    if new_font_size then
        logger.dbg("CreDocument: set font size", new_font_size)
        self._document:setFontSize(new_font_size)
    end
end

function CreDocument:setViewMode(new_mode)
    if new_mode then
        logger.dbg("CreDocument: set view mode", new_mode)
        if new_mode == "scroll" then
            self._document:setViewMode(self.SCROLL_VIEW_MODE)
        else
            self._document:setViewMode(self.PAGE_VIEW_MODE)
        end
    end
end

function CreDocument:setViewDimen(dimen)
    logger.dbg("CreDocument: set view dimen", dimen)
    self._document:setViewDimen(dimen.w, dimen.h)
end

function CreDocument:setHeaderFont(new_font)
    if new_font then
        logger.dbg("CreDocument: set header font", new_font)
        self._document:setHeaderFont(new_font)
    end
end

function CreDocument:zoomFont(delta)
    logger.dbg("CreDocument: zoom font", delta)
    self._document:zoomFont(delta)
end

function CreDocument:setInterlineSpacePercent(percent)
    logger.dbg("CreDocument: set interline space", percent)
    self._document:setDefaultInterlineSpace(percent)
end

function CreDocument:toggleFontBolder(toggle)
    logger.dbg("CreDocument: toggle font bolder", toggle)
    self._document:setIntProperty("font.face.weight.embolden", toggle)
end

function CreDocument:setGammaIndex(index)
    logger.dbg("CreDocument: set gamma index", index)
    cre.setGammaIndex(index)
end

function CreDocument:setFontHinting(mode)
    logger.dbg("CreDocument: set font hinting mode", mode)
    self._document:setIntProperty("font.hinting.mode", mode)
end

function CreDocument:setStyleSheet(new_css)
    logger.dbg("CreDocument: set style sheet", new_css)
    self._document:setStyleSheet(new_css)
end

function CreDocument:setEmbeddedStyleSheet(toggle)
    -- FIXME: occasional segmentation fault when switching embedded style sheet
    logger.dbg("CreDocument: set embedded style sheet", toggle)
    self._document:setIntProperty("crengine.doc.embedded.styles.enabled", toggle)
end

function CreDocument:setEmbeddedFonts(toggle)
    logger.dbg("CreDocument: set embedded fonts", toggle)
    self._document:setIntProperty("crengine.doc.embedded.fonts.enabled", toggle)
end

function CreDocument:setPageMargins(left, top, right, bottom)
    logger.dbg("CreDocument: set page margins", left, top, right, bottom)
    self._document:setIntProperty("crengine.page.margin.left", left)
    self._document:setIntProperty("crengine.page.margin.top", top)
    self._document:setIntProperty("crengine.page.margin.right", right)
    self._document:setIntProperty("crengine.page.margin.bottom", bottom)
end

function CreDocument:setFloatingPunctuation(enabled)
    -- FIXME: occasional segmentation fault when toggling floating punctuation
    logger.dbg("CreDocument: set floating punctuation", enabled)
    self._document:setIntProperty("crengine.style.floating.punctuation.enabled", enabled)
end

function CreDocument:setTxtPreFormatted(enabled)
    logger.dbg("CreDocument: set txt preformatted", enabled)
    self._document:setIntProperty("crengine.file.txt.preformatted", enabled)
end

function CreDocument:getVisiblePageCount()
    return self._document:getVisiblePageCount()
end

function CreDocument:setVisiblePageCount(new_count)
    logger.dbg("CreDocument: set visible page count", new_count)
    self._document:setVisiblePageCount(new_count)
end

function CreDocument:setBatteryState(state)
    logger.dbg("CreDocument: set battery state", state)
    self._document:setBatteryState(state)
end

function CreDocument:isXPointerInCurrentPage(xp)
    logger.dbg("CreDocument: check xpointer in current page", xp)
    return self._document:isXPointerInCurrentPage(xp)
end

function CreDocument:setStatusLineProp(prop)
    logger.dbg("CreDocument: set status line property", prop)
    self._document:setStringProperty("window.status.line", prop)
end

function CreDocument:findText(pattern, origin, reverse, caseInsensitive)
    logger.dbg("CreDocument: find text", pattern, origin, reverse, caseInsensitive)
    return self._document:findText(
        pattern, origin, reverse, caseInsensitive and 1 or 0)
end

function CreDocument:register(registry)
    registry:addProvider("azw", "application/azw", self)
    registry:addProvider("epub", "application/epub", self)
    registry:addProvider("chm", "application/chm", self)
    registry:addProvider("doc", "application/doc", self)
    registry:addProvider("fb2", "application/fb2", self)
    registry:addProvider("fb2.zip", "application/zip", self)
    registry:addProvider("html", "application/html", self)
    registry:addProvider("html.zip", "application/zip", self)
    registry:addProvider("htm", "application/htm", self)
    registry:addProvider("htm.zip", "application/zip", self)
    registry:addProvider("log", "text/plain", self)
    registry:addProvider("log.zip", "application/zip", self)
    registry:addProvider("md", "text/plain", self)
    registry:addProvider("md.zip", "application/zip", self)
    registry:addProvider("mobi", "application/mobi", self)
    registry:addProvider("pdb", "application/pdb", self)
    registry:addProvider("prc", "application/prc", self)
    registry:addProvider("tcr", "application/tcr", self)
    registry:addProvider("txt", "text/plain", self)
    registry:addProvider("txt.zip", "application/zip", self)
    registry:addProvider("rtf", "application/rtf", self)
end

return CreDocument
