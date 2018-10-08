local Blitbuffer = require("ffi/blitbuffer")
local CreOptions = require("ui/data/creoptions")
local DataStorage = require("datastorage")
local Document = require("document/document")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local ffi = require("ffi")
local C = ffi.C
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
    default_font = "Noto Serif",
    header_font = "Noto Sans",
    fallback_font = "Noto Sans CJK SC",
    default_css = "./data/cr3.css",
    options = CreOptions,
    provider = "crengine",
    provider_name = "Cool Reader Engine",
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
    -- crengine saves caches on disk for faster re-openings, and cleans
    -- the less recently used ones when this limit is reached
    local default_cre_disk_cache_max_size = 64 -- in MB units
    -- crengine various in-memory caches max-sizes are rather small
    -- (2.5 / 4.5 / 1.5 / 1 MB), and we can avoid some bugs if we
    -- increase them. Let's multiply them by 20 (each cache would
    -- grow only when needed, depending on book characteristics).
    -- People who would get out of memory crashes with big books on
    -- older devices can decrease that with setting:
    --   "cre_storage_size_factor"=1    (or 2, or 5)
    local default_cre_storage_size_factor = 20
    cre.initCache(DataStorage:getDataDir() .. "/cache/cr3cache",
        (G_reader_settings:readSetting("cre_disk_cache_max_size") or default_cre_disk_cache_max_size)*1024*1024,
        G_reader_settings:nilOrTrue("cre_compress_cached_data"),
        G_reader_settings:readSetting("cre_storage_size_factor") or default_cre_storage_size_factor)
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
                    logger.err("failed to register crengine font:", err)
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

    -- June 2018: epub.css has been cleaned to be more conforming to HTML specs
    -- and to not include class name based styles (with conditional compatiblity
    -- styles for previously opened documents). It should be usable on all
    -- HTML based documents, except FB2 which has some incompatible specs.
    -- The other css files (htm.css, rtf.css...) have not been updated in the
    -- same way, and are kept as-is for when a previously opened document
    -- requests one of them.
    self.default_css = "./data/epub.css"
    if file_type == "fb2" then
        self.default_css = "./data/fb2.css"
    end

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

    if G_reader_settings:readSetting("cre_header_status_font_size") then
        self._document:setIntProperty("crengine.page.header.font.size",
            G_reader_settings:readSetting("cre_header_status_font_size"))
    end

    -- set fallback font face
    self._document:setStringProperty("crengine.font.fallback.face",
        G_reader_settings:readSetting("fallback_font") or self.fallback_font)

    -- We would have liked to call self._document:loadDocument(self.file)
    -- here, to detect early if file is a supported document, but we
    -- need to delay it till after some crengine settings are set for a
    -- consistent behaviour.

    self.is_open = true
    self.info.has_pages = false
    self:_readMetadata()
    self.info.configurable = true
end

function CreDocument:getLatestDomVersion()
    return cre.getLatestDomVersion()
end

function CreDocument:getOldestDomVersion()
    return 20171225 -- arbitrary day in the past
end

function CreDocument:requestDomVersion(version)
    logger.dbg("CreDocument: requesting DOM version:", version)
    cre.requestDomVersion(version)
end

function CreDocument:loadDocument(full_document)
    if not self._loaded then
        local only_metadata = full_document == false
        logger.dbg("CreDocument: loading document...")
        if self._document:loadDocument(self.file, only_metadata) then
            self._loaded = true
            logger.dbg("CreDocument: loading done.")
        else
            logger.dbg("CreDocument: loading failed.")
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
    logger.dbg("CreDocument: rendering document...")
    self._document:renderDocument()
    if not self.info.has_pages then
        self.info.doc_height = self._document:getFullHeight()
    end
    logger.dbg("CreDocument: rendering done.")
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
    -- no need to render document in order to get cover image
    if not self:loadDocument() then
        return nil -- not recognized by crengine
    end
    local data, size = self._document:getCoverPageImageData()
    if data and size then
        local image = RenderImage:renderImageData(data, size)
        C.free(data) -- free the userdata we got from crengine
        return image
    end
end

function CreDocument:getImageFromPosition(pos, want_frames)
    local data, size = self._document:getImageDataFromPosition(pos.x, pos.y)
    if data and size then
        logger.dbg("CreDocument: got image data from position", data, size)
        local image = RenderImage:renderImageData(data, size, want_frames)
        C.free(data) -- free the userdata we got from crengine
        return image
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

function CreDocument:getScreenBoxesFromPositions(pos0, pos1, get_segments)
    local line_boxes = {}
    if pos0 and pos1 then
        local word_boxes = self._document:getWordBoxesFromPositions(pos0, pos1, get_segments)
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
    -- TODO: self.buffer could be re-used when no page/layout/highlights
    -- change has been made, to avoid having crengine redraw the exact
    -- same buffer.
    -- And it could only change when some other methods from here are called
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

function CreDocument:setFallbackFontFace(new_fallback_font_face)
    if new_fallback_font_face then
        logger.dbg("CreDocument: set fallback font face", new_fallback_font_face)
        self._document:setStringProperty("crengine.font.fallback.face", new_fallback_font_face)
        -- crengine may not accept our fallback font, we need to check
        local set_fallback_font_face = self._document:getStringProperty("crengine.font.fallback.face")
        logger.dbg("CreDocument: crengine fallback font face", set_fallback_font_face)
        if set_fallback_font_face ~= new_fallback_font_face then
            logger.info("CreDocument:", new_fallback_font_face, "is not usable as a fallback font")
            return false
        end
        self.fallback_font = new_fallback_font_face
        return true
    end
end

function CreDocument:setHyphDictionary(new_hyph_dictionary)
    if new_hyph_dictionary then
        logger.dbg("CreDocument: set hyphenation dictionary", new_hyph_dictionary)
        self._document:setStringProperty("crengine.hyphenation.directory", new_hyph_dictionary)
    end
end

function CreDocument:setHyphLeftHyphenMin(value)
    -- default crengine value is 2: reset it if no value provided
    logger.dbg("CreDocument: set hyphenation left hyphen min", value or 2)
    self._document:setIntProperty("crengine.hyphenation.left.hyphen.min", value or 2)
end

function CreDocument:setHyphRightHyphenMin(value)
    logger.dbg("CreDocument: set hyphenation right hyphen min", value or 2)
    self._document:setIntProperty("crengine.hyphenation.right.hyphen.min", value or 2)
end

function CreDocument:setTrustSoftHyphens(toggle)
    logger.dbg("CreDocument: set hyphenation trust soft hyphens", toggle and 1 or 0)
    self._document:setIntProperty("crengine.hyphenation.trust.soft.hyphens", toggle and 1 or 0)
end

function CreDocument:setRenderDPI(value)
    -- set DPI used for scaling css units (with 96, 1 css px = 1 screen px)
    -- it can be different from KOReader screen DPI
    -- it has no relation to the default fontsize (which is already
    -- scaleBySize()'d when provided to crengine)
    logger.dbg("CreDocument: set render dpi", value or 96)
    self._document:setIntProperty("crengine.render.dpi", value or 96)
end

function CreDocument:setRenderScaleFontWithDPI(toggle)
    -- wheter to scale font with DPI, or keep the current size
    logger.dbg("CreDocument: set render scale font with dpi", toggle)
    self._document:setIntProperty("crengine.render.scale.font.with.dpi", toggle)
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

function CreDocument:getGammaLevel()
    return cre.getGammaLevel()
end

function CreDocument:setGammaIndex(index)
    logger.dbg("CreDocument: set gamma index", index)
    cre.setGammaIndex(index)
end

function CreDocument:setFontHinting(mode)
    logger.dbg("CreDocument: set font hinting mode", mode)
    self._document:setIntProperty("font.hinting.mode", mode)
end

function CreDocument:setFontKerning(mode)
    logger.dbg("CreDocument: set font kerning mode", mode)
    self._document:setIntProperty("font.kerning.mode", mode)
end

-- min space condensing percent (how much we can decrease a space width to
-- make text fit on a line) 25...100%
function CreDocument:setSpaceCondensing(value)
    logger.dbg("CreDocument: set space condensing", value)
    self._document:setIntProperty("crengine.style.space.condensing.percent", value)
end

function CreDocument:setStyleSheet(new_css_file, appended_css_content )
    logger.dbg("CreDocument: set style sheet:",
        new_css_file and new_css_file or "no file",
        appended_css_content and "and appended content ("..#appended_css_content.." bytes)" or "(no appended content)")
    self._document:setStyleSheet(new_css_file, appended_css_content)
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

function CreDocument:enableInternalHistory(toggle)
    -- Setting this to 0 unsets crengine internal bookmarks highlighting,
    -- and as a side effect, disable internal history and the need to build
    -- a bookmark at each page turn: this speeds up a lot page turning
    -- and menu opening on big books.
    -- It has to be called late in the document opening process, and setting
    -- it to false needs to be followed by a redraw.
    -- It needs to be temporarily re-enabled on page resize for crengine to
    -- keep track of position in page and restore it after resize.
    logger.dbg("CreDocument: set bookmarks highlight and internal history", toggle)
    self._document:setIntProperty("crengine.highlight.bookmarks", toggle and 2 or 0)
end

function CreDocument:isBuiltDomStale()
    return self._document:isBuiltDomStale()
end

function CreDocument:hasCacheFile()
    return self._document:hasCacheFile()
end

function CreDocument:invalidateCacheFile()
    self._document:invalidateCacheFile()
end

function CreDocument:getCacheFilePath()
    return self._document:getCacheFilePath()
end

function CreDocument:canHaveAlternativeToc()
    return true
end

function CreDocument:isTocAlternativeToc()
    return self._document:isTocAlternativeToc()
end

function CreDocument:buildAlternativeToc()
    self._document:buildAlternativeToc()
end

function CreDocument:register(registry)
    registry:addProvider("azw", "application/vnd.amazon.mobi8-ebook", self, 90)
    registry:addProvider("chm", "application/vnd.ms-htmlhelp", self, 90)
    registry:addProvider("doc", "application/msword", self, 90)
    registry:addProvider("epub", "application/epub+zip", self, 100)
    registry:addProvider("fb2", "application/fb2", self, 90)
    registry:addProvider("fb2.zip", "application/zip", self, 90)
    registry:addProvider("htm", "text/html", self, 100)
    registry:addProvider("html", "text/html", self, 100)
    registry:addProvider("htm.zip", "application/zip", self, 100)
    registry:addProvider("html.zip", "application/zip", self, 100)
    registry:addProvider("log", "text/plain", self)
    registry:addProvider("log.zip", "application/zip", self)
    registry:addProvider("md", "text/plain", self)
    registry:addProvider("md.zip", "application/zip", self)
    registry:addProvider("mobi", "application/x-mobipocket-ebook", self, 90)
    -- Palmpilot Document File
    registry:addProvider("pdb", "application/vnd.palm", self, 90)
    -- Palmpilot Resource File
    registry:addProvider("prc", "application/vnd.palm", self)
    registry:addProvider("tcr", "application/tcr", self)
    registry:addProvider("txt", "text/plain", self, 90)
    registry:addProvider("txt.zip", "application/zip", self, 90)
    registry:addProvider("rtf", "application/rtf", self, 90)
    registry:addProvider("xhtml", "application/xhtml+xml", self, 90)
    registry:addProvider("zip", "application/zip", self, 10)
end

return CreDocument
