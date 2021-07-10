local Blitbuffer = require("ffi/blitbuffer")
local CanvasContext = require("document/canvascontext")
local DataStorage = require("datastorage")
local Document = require("document/document")
local FontList = require("fontlist")
local Geom = require("ui/geometry")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local TimeVal = require("ui/timeval")
local buffer = require("string.buffer")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local lru = require("ffi/lru")

-- engine can be initialized only once, on first document opened
local engine_initialized = false

local CreDocument = Document:new{
    -- this is defined in kpvcrlib/crengine/crengine/include/lvdocview.h
    SCROLL_VIEW_MODE = 0,
    PAGE_VIEW_MODE = 1,

    _document = false,
    _loaded = false,
    _view_mode = nil,
    _smooth_scaling = false,
    _nightmode_images = true,

    line_space_percent = 100,
    default_font = "Noto Serif",
    header_font = "Noto Sans",

    -- Reasons for the fallback font ordering:
    -- - Noto Sans CJK SC before FreeSans/Serif, as it has nice and larger
    --   symbol glyphs for Wikipedia EPUB headings than both Free fonts)
    -- - FreeSerif after most, has it has good coverage but smaller glyphs
    --   (and most other fonts are better looking)
    -- - FreeSans covers areas that FreeSerif do not, and is usually
    --   fine along other fonts (even serif fonts)
    -- - Noto Serif & Sans at the end, just in case, and to have consistent
    --   (and larger than FreeSerif) '?' glyphs for codepoints not found
    --   in any fallback font. Also, we don't know if the user is using
    --   a serif or a sans main font, so choosing to have one of these early
    --   might not be the best decision (and moving them before FreeSans would
    --   require one to set FreeSans as fallback to get its nicer glyphes, which
    --   would override Noto Sans CJK good symbol glyphs with smaller ones
    --   (Noto Sans & Serif do not have these symbol glyphs).
    fallback_fonts = {
        "Noto Sans CJK SC",
        "Noto Naskh Arabic",
        "Noto Sans Devanagari UI",
        "FreeSans",
        "FreeSerif",
        "Noto Serif",
        "Noto Sans",
    },

    default_css = "./data/cr3.css",
    provider = "crengine",
    provider_name = "Cool Reader Engine",

    hide_nonlinear_flows = false,
    flows = {},
    page_in_flow = {},
    last_linear_page = nil,
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
    -- (2.5 / 4.5 / 4.5 / 1 MB), and we can avoid some bugs if we
    -- increase them. Let's multiply them by 40 (each cache would
    -- grow only when needed, depending on book characteristics).
    -- People who would get out of memory crashes with big books on
    -- older devices can decrease that with setting:
    --   "cre_storage_size_factor"=1    (or 2, or 5)
    local default_cre_storage_size_factor = 40
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
        local fonts = FontList:getFontList()
        for _k, _v in ipairs(fonts) do
            if not _v:find("/urw/") and not _v:find("/nerdfonts/symbols.ttf") then
                local ok, err = pcall(cre.registerFont, _v)
                if not ok then
                    logger.err("failed to register crengine font:", err)
                end
            end
        end
        -- Make sure registered fonts have a proper entry at weight 400 and 700 when
        -- possible, to avoid having synthesized fonts for these normal and bold weights.
        -- This allows restoring a bit of the previous behaviour of crengine when it
        -- wasn't handling font styles, and associated for each typeface one single
        -- font to regular (400) and one to bold (700).
        -- It should ensure we use real fonts (and not synthesized ones) for normal text
        -- and bold text with the font_base_weight setting set to its default value of 0 (=400).
        cre.regularizeRegisteredFontsWeights(true) -- true to print what modifications were made

        engine_initialized = true
    end
end

function CreDocument:init()
    self:updateColorRendering()
    self:engineInit()

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
    if file_type == "fb2" or file_type == "fb3" then
        self.default_css = "./data/fb2.css"
    end

    -- This mode must be the same as the default one set as ReaderView.view_mode
    self._view_mode = DCREREADER_VIEW_MODE == "scroll" and self.SCROLL_VIEW_MODE or self.PAGE_VIEW_MODE

    local ok
    ok, self._document = pcall(cre.newDocView, CanvasContext:getWidth(), CanvasContext:getHeight(), self._view_mode)
    if not ok then
        error(self._document)  -- will contain error message
    end

    -- We would have liked to call self._document:loadDocument(self.file)
    -- here, to detect early if file is a supported document, but we
    -- need to delay it till after some crengine settings are set for a
    -- consistent behaviour.

    self.is_open = true
    self.info.has_pages = false
    self:_readMetadata()
    self.info.configurable = true

    -- Setup crengine library calls caching
    self:setupCallCache()
end

function CreDocument:getDomVersionWithNormalizedXPointers()
    return cre.getDomVersionWithNormalizedXPointers()
end

function CreDocument:getLatestDomVersion()
    return cre.getLatestDomVersion()
end

function CreDocument:getOldestDomVersion()
    return 20171225 -- arbitrary day in the past
end

function CreDocument:requestDomVersion(version)
    logger.dbg("CreDocument: requesting DOM version:", version)
    self._document:setIntProperty("crengine.render.requested_dom_version", version)
end

function CreDocument:getDocumentFormat()
    return self._document:getDocumentFormat()
end

function CreDocument:setupDefaultView()
    if self.loaded then
        -- Don't apply defaults if the document has already been loaded
        -- as this must be done before calling loadDocument()
        return
    end
    -- have crengine load defaults from cr3.ini
    self._document:readDefaults()
    logger.dbg("CreDocument: applied cr3.ini default settings.")

    -- Disable crengine image scaling options (we prefer scaling them via crengine.render.dpi)
    self._document:setIntProperty("crengine.image.scaling.zoomin.block.mode", 0)
    self._document:setIntProperty("crengine.image.scaling.zoomin.block.scale", 1)
    self._document:setIntProperty("crengine.image.scaling.zoomin.inline.mode", 0)
    self._document:setIntProperty("crengine.image.scaling.zoomin.inline.scale", 1)
    self._document:setIntProperty("crengine.image.scaling.zoomout.block.mode", 0)
    self._document:setIntProperty("crengine.image.scaling.zoomout.block.scale", 1)
    self._document:setIntProperty("crengine.image.scaling.zoomout.inline.mode", 0)
    self._document:setIntProperty("crengine.image.scaling.zoomout.inline.scale", 1)

    -- If switching to two pages on view, we want it to behave like two columns
    -- and each view to be a single page number (instead of the default of two).
    -- This ensures that page number and count are consistent between top and
    -- bottom status bars, that SkimTo -1/+1 don't do nothing every other tap,
    -- and that reading statistics do not see half of the pages never read.
    self._document:setIntProperty("window.pages.two.visible.as.one.page.number", 1)

    -- set fallback font faces (this was formerly done in :init(), but it
    -- affects crengine calcGlobalSettingsHash() and would invalidate the
    -- cache from the main currently being read document when we just
    -- loadDocument(only_metadata) another document to get its metadata
    -- or cover image, eg. from History hold menu).
    self:setupFallbackFontFaces()

    -- adjust font sizes according to dpi set in canvas context
    self._document:adjustFontSizes(CanvasContext:getDPI())

    -- set top status bar font size
    if G_reader_settings:has("cre_header_status_font_size") then
        self._document:setIntProperty("crengine.page.header.font.size",
            G_reader_settings:readSetting("cre_header_status_font_size"))
    end

    -- One can set these to change from white background
    if G_reader_settings:has("cre_background_color") then
        self:setBackgroundColor(G_reader_settings:readSetting("cre_background_color"))
    end
    if G_reader_settings:has("cre_background_image") then
        self:setBackgroundImage(G_reader_settings:readSetting("cre_background_image"))
    end
end

function CreDocument:loadDocument(full_document)
    if not self._loaded then
        local only_metadata = full_document == false
        logger.dbg("CreDocument: loading document...")
        if only_metadata then
            -- Setting a default font before loading document
            -- actually do prevent some crashes
            self:setFontFace(self.default_font)
        end
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
    -- This is now configurable and done by ReaderRolling:
    -- -- set visible page count in landscape
    -- if math.max(CanvasContext:getWidth(), CanvasContext:getHeight()) / CanvasContext:getDPI()
    --     < DCREREADER_TWO_PAGE_THRESHOLD then
    --     self:setVisiblePageCount(1)
    -- end
    logger.dbg("CreDocument: rendering document...")
    self._document:renderDocument()
    self.info.doc_height = self._document:getFullHeight()
    self.been_rendered = true
    logger.dbg("CreDocument: rendering done.")
end

function CreDocument:getDocumentRenderingHash()
    if self.been_rendered then
        return self._document:getDocumentRenderingHash()
    end
    return 0
end

function CreDocument:_readMetadata()
    Document._readMetadata(self) -- will grab/update self.info.number_of_pages
    if self.been_rendered then
        -- getFullHeight() would crash if the document is not
        -- yet rendered
        self.info.doc_height = self._document:getFullHeight()
    end
    return true
end

function CreDocument:close()
    -- Let Document do the refcount check, and tell us if we actually need to tear down the instance.
    if Document.close(self) then
        -- Yup, final Document instance, we can safely destroy internal data.
        -- (Document already took care of our self._document userdata).
        if self.buffer then
            self.buffer:free()
            self.buffer = nil
        end

        -- Only exists if the call cache is enabled
        if self._callCacheDestroy then
            self._callCacheDestroy()
        end
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

function CreDocument:setHideNonlinearFlows(hide_nonlinear_flows)
    if hide_nonlinear_flows ~= self.hide_nonlinear_flows then
        self.hide_nonlinear_flows = hide_nonlinear_flows
        self._document:setIntProperty("crengine.doc.nonlinear.pagebreak.force", self.hide_nonlinear_flows and 1 or 0)
    end
end

function CreDocument:getPageCount(internal)
    return self._document:getPages(internal)
end

-- Whether the document has any non-linear flow to care about
function CreDocument:hasNonLinearFlows()
    return self._document:hasNonLinearFlows()
end

-- Whether non-linear flows (if any) will be hidden
function CreDocument:hasHiddenFlows()
    return self.flows[1] ~= nil
end

-- Get the next/prev page number, skipping non-linear flows,
-- i.e. the next/prev page that is either in the current
-- flow or in the linear flow (flow 0)
-- If "page" is 0, these give the initial and final linear pages
function CreDocument:getNextPage(page)
    if self:hasHiddenFlows() then
        if page < 0 or page >= self:getPageCount() then
            return 0
        elseif page == 0 then
            return self:getFirstPageInFlow(0)
        end
        local flow = self:getPageFlow(page)
        local start_page = page + 1
        local end_page = self:getLastLinearPage()
        local test_page = start_page
        -- max to ensure at least one iteration
        -- (in case the current flow goes after all linear pages)
        while test_page <= math.max(end_page, start_page) do
            local test_page_flow = self:getPageFlow(test_page)
            if test_page_flow == flow or test_page_flow == 0 then
                -- same flow as current, or linear flow, this is a "good" page
                return test_page
            elseif test_page_flow > 0 then
                -- some other non-linear flow, skip all pages in this flow
                test_page = test_page + self:getTotalPagesInFlow(test_page_flow)
            else
                -- went beyond the last page
                break
            end
        end
        return 0
    else
        return Document.getNextPage(self, page)
    end
end

function CreDocument:getPrevPage(page)
    if self:hasHiddenFlows() then
        if page < 0 or page > self:getPageCount() then
            return 0
        elseif page == 0 then
            return self:getLastLinearPage()
        end
        local flow = self:getPageFlow(page)
        local start_page = page - 1
        local end_page = self:getFirstPageInFlow(0)
        local test_page = start_page
        -- min to ensure at least one iteration
        -- (in case the current flow goes before all linear pages)
        while test_page >= math.min(end_page, start_page) do
            local test_page_flow = self:getPageFlow(test_page)
            if test_page_flow == flow or test_page_flow == 0 then
                -- same flow as current, or linear flow, this is a "good" page
                return test_page
            elseif test_page_flow > 0 then
                -- some other non-linear flow, skip all pages in this flow
                test_page = self:getFirstPageInFlow(test_page_flow) - 1
            else
                -- went beyond the first page
                break
            end
        end
        return 0
    else
        return Document.getPrevPage(self, page)
    end
end

function CreDocument:getPageFlow(page)
    -- Only report non-linear pages if "hide_nonlinear_flows" is enabled, and in 1-page mode,
    -- otherwise all pages are linear (flow 0)
    if self.hide_nonlinear_flows and self._view_mode == self.PAGE_VIEW_MODE and self:getVisiblePageCount() == 1 then
        return self._document:getPageFlow(page)
    else
        return 0
    end
end

function CreDocument:getLastLinearPage()
    return self.last_linear_page
end

function CreDocument:getFirstPageInFlow(flow)
    return self.flows[flow][1]
end

function CreDocument:getTotalPagesInFlow(flow)
    return self.flows[flow][2]
end

function CreDocument:getPageNumberInFlow(page)
    if self:hasHiddenFlows() then
        return self.page_in_flow[page]
    else
        return page
    end
end

function CreDocument:cacheFlows()
    -- Build the cache tables "flows" and "page_in_flow", if there are
    -- any non-linear flows in the source document. Also set the value
    -- of "last_linear_page", to possibly speed up counting in documents
    -- with many non-linear pages at the end.
    -- flows[i] contains {ini, num}, where ini is the first page in flow i,
    --          and num is the total number of pages in the flow.
    -- page_in_flow[i] contains the number of page i with its flow.
    --
    -- So, flows[0][1] is the first page in the linear flow,
    -- and page_in_flow[flows[0][1]] must be 1, because it is the first
    self.flows = {}
    self.page_in_flow = {}
    if self:hasNonLinearFlows() and self.hide_nonlinear_flows then
        for i=1,self:getPageCount() do
            local flow = self:getPageFlow(i)
            if self.flows[flow] ~= nil then
                self.flows[flow][2] = self.flows[flow][2]+1
            else
                self.flows[flow] = {i, 1}
            end
            self.page_in_flow[i] = self.flows[flow][2]
            if flow == 0 then
                self.last_linear_page = i
            end
        end
    else
        self.last_linear_page = self:getPageCount()
        self.flows[0] = {1, self.last_linear_page}
    end
end

function CreDocument:getTotalPagesLeft(page)
    if self:hasHiddenFlows() then
        local pages_left
        local last_linear = self:getLastLinearPage()
        if page > last_linear then
            -- If beyond the last linear page, count only the pages in the current flow
            local flow = self:getPageFlow(page)
            pages_left = self:getTotalPagesInFlow(flow) - self:getPageNumberInFlow(page)
        else
            -- Otherwise, count all pages until the last linear,
            -- except the flows that start (and end) between
            -- the current page and the last linear
            pages_left = last_linear - page
            for flow, tab in ipairs(self.flows) do
                -- tab[1] is the initial page of the flow
                -- tab[2] is the total number of pages in the flow
                if tab[1] > last_linear then
                     break
                end
                -- strict >, to make sure we include pages in the current flow
                if tab[1] > page then
                     pages_left = pages_left - tab[2]
                end
            end
        end
        return pages_left
    else
        return Document.getTotalPagesLeft(self, page)
    end
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
    local wordbox = {
        page = self._document:getCurrentPage(),
    }
    -- We use getTextFromPositions() which is more accurate.
    -- In case some stuff is missing, we could fallback to use
    -- the less accurate getWordFromPosition().
    -- But it looks like getTextFromPositions() is just fine, and
    -- when it fails, it's because there's no word at position.
    -- So, we'll return nil below in case not all is found
    local word_found = false
    local box_found = false

    local text_range = self._document:getTextFromPositions(pos.x, pos.y, pos.x, pos.y)
    logger.dbg("CreDocument: get text range", text_range)
    if text_range then
        if text_range.text and text_range.text ~= "" then
            wordbox.word = text_range.text
            word_found = true
        end
        if text_range.pos0 and text_range.pos1 then
            -- get segments from these pos, to build the overall box
            local word_boxes = self._document:getWordBoxesFromPositions(text_range.pos0, text_range.pos1, true)
            if #word_boxes > 0 then
                local overall_box
                for i = 1, #word_boxes do
                    local line_box = word_boxes[i]
                    if not overall_box then
                        overall_box = line_box
                    else
                        if line_box.x0 < overall_box.x0 then overall_box.x0 = line_box.x0 end
                        if line_box.y0 < overall_box.y0 then overall_box.y0 = line_box.y0 end
                        if line_box.x1 > overall_box.x1 then overall_box.x1 = line_box.x1 end
                        if line_box.y1 > overall_box.y1 then overall_box.y1 = line_box.y1 end
                    end
                end
                wordbox.sbox = Geom:new{
                    x = overall_box.x0,
                    y = overall_box.y0,
                    w = overall_box.x1 - overall_box.x0,
                    h = overall_box.y1 - overall_box.y0,
                }
                box_found = true
            end
        end
        -- add xpointers if any, might be useful for across pages highlighting
        wordbox.pos0 = text_range.pos0
        wordbox.pos1 = text_range.pos1
    end

    -- Fully trust getTextFromPositions()
    if word_found and box_found then
        return wordbox
    else
        return nil
    end

    -- If we ever want to fallback to getWordFromPositions()
    --[[
    local word = self._document:getWordFromPosition(pos.x, pos.y)
    logger.warn("CreDocument: get word box", word)
    if not word_found then
        wordbox.word = word.word
    end
    if not box_found then
        if word.word then
            wordbox.sbox = Geom:new{
                x = word.x0,
                y = word.y0,
                w = word.x1 - word.x0,
                h = word.y1 - word.y0,
            }
        else
            -- dummy box
            wordbox.sbox = Geom:new{
                x = pos.x, y = pos.y,
                w = 20, h = 20,
            }
        end
    end
    return wordbox
    ]]--
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

function CreDocument:compareXPointers(xp1, xp2)
    -- Returns 1 if XPointers are ordered (if xp2 is after xp1), -1 if not, 0 if same
    return self._document:compareXPointers(xp1, xp2)
end

function CreDocument:getNextVisibleWordStart(xp)
    return self._document:getNextVisibleWordStart(xp)
end

function CreDocument:getNextVisibleWordEnd(xp)
    return self._document:getNextVisibleWordEnd(xp)
end

function CreDocument:getPrevVisibleWordStart(xp)
    return self._document:getPrevVisibleWordStart(xp)
end

function CreDocument:getPrevVisibleWordEnd(xp)
    return self._document:getPrevVisibleWordEnd(xp)
end

function CreDocument:getPrevVisibleChar(xp)
    return self._document:getPrevVisibleChar(xp)
end

function CreDocument:getNextVisibleChar(xp)
    return self._document:getNextVisibleChar(xp)
end

function CreDocument:drawCurrentView(target, x, y, rect, pos)
    if self.buffer and (self.buffer.w ~= rect.w or self.buffer.h ~= rect.h) then
        self.buffer:free()
        self.buffer = nil
    end
    if not self.buffer then
        -- Note about color rendering:
        -- We use TYPE_BBRGB32 (and LVColorDrawBuf drawBuf(..., 32) in cre.cpp),
        -- to match the screen's BB type, allowing us to take shortcuts when blitting.
        self.buffer = Blitbuffer.new(rect.w, rect.h, self.render_color and Blitbuffer.TYPE_BBRGB32 or nil)
    end
    --- @todo self.buffer could be re-used when no page/layout/highlights
    -- change has been made, to avoid having crengine redraw the exact
    -- same buffer. And it could only change when some other methods
    -- from here are called

    -- If in night mode, we ask crengine to invert all images, so they
    -- get displayed in their original colors when the whole screen
    -- is inverted by night mode
    -- We also honor the current smooth scaling setting,
    -- as well as the global SW dithering setting.

    --local start_tv = TimeVal:now()
    self._drawn_images_count, self._drawn_images_surface_ratio =
        self._document:drawCurrentPage(self.buffer, self.render_color, Screen.night_mode and self._nightmode_images, self._smooth_scaling, Screen.sw_dithering)
    --local end_tv = TimeVal:now()
    --print(string.format("CreDocument:drawCurrentView: Rendering took %9.3f ms", (end_tv - start_tv):tomsecs()))

    --start_tv = TimeVal:now()
    target:blitFrom(self.buffer, x, y, 0, 0, rect.w, rect.h)
    --end_tv = TimeVal:now()
    --print(string.format("CreDocument:drawCurrentView: Blitting took  %9.3f ms", (end_tv - start_tv):tomsecs()))
end

function CreDocument:drawCurrentViewByPos(target, x, y, rect, pos)
    self._document:gotoPos(pos)
    self:drawCurrentView(target, x, y, rect)
end

function CreDocument:drawCurrentViewByPage(target, x, y, rect, page)
    if not self.no_page_sync then
        -- Avoid syncing page when this flag is set, when selecting text
        -- across pages in 2-page mode and flipping half the screen
        -- (currently only set by ReaderHighlight:onHoldPan())
        -- self._document:gotoPage(page)
        -- This allows this method to not be cached by cre call cache
        self:gotoPage(page)
    end
    self:drawCurrentView(target, x, y, rect)
end

function CreDocument:hintPage(pageno, zoom, rotation)
end

function CreDocument:drawPage(target, x, y, rect, pageno, zoom, rotation)
end

function CreDocument:renderPage(pageno, rect, zoom, rotation)
end

function CreDocument:getPageMargins()
    return self._document:getPageMargins()
end

function CreDocument:getHeaderHeight()
    return self._document:getHeaderHeight()
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

function CreDocument:getPageOffsetX(page)
    return self._document:getPageOffsetX(page)
end

function CreDocument:getScreenPositionFromXPointer(xp)
    -- We do not ensure xp is in the current page: we may return
    -- a negative screen_y, which could be useful in some contexts
    local doc_margins = self:getPageMargins()
    local doc_y, doc_x = self:getPosFromXPointer(xp)
    local top_y = self:getCurrentPos()
    local screen_y = doc_y - top_y
    local screen_x = doc_x + doc_margins["left"]
    if self._view_mode == self.PAGE_VIEW_MODE then
        if self:getVisiblePageCount() > 1 then
            -- Correct coordinates if on the 2nd page in 2-pages mode
            -- getPageStartY() and getPageOffsetX() expects internal page numbers
            local next_page = self:getCurrentPage(true) + 1
            if next_page <= self:getPageCount(true) then
                local next_top_y = self._document:getPageStartY(next_page)
                if doc_y >= next_top_y then
                    screen_y = doc_y - next_top_y
                    screen_x = screen_x + self._document:getPageOffsetX(next_page)
                end
            end
        end
        screen_y = screen_y + doc_margins["top"] + self:getHeaderHeight()
    end
    -- Just as getPosFromXPointer() does, we return y first and x second,
    -- as callers most often just need the y
    return screen_y, screen_x
end

function CreDocument:getFontFace()
    return self._document:getFontFace()
end

function CreDocument:getCurrentPos()
    return self._document:getCurrentPos()
end

function CreDocument:getPageLinks(internal_links_only)
    return self._document:getPageLinks(internal_links_only)
end

function CreDocument:getLinkFromPosition(pos)
    return self._document:getLinkFromPosition(pos.x, pos.y)
end

function CreDocument:isLinkToFootnote(source_xpointer, target_xpointer, flags, max_text_size)
    return self._document:isLinkToFootnote(source_xpointer, target_xpointer, flags, max_text_size)
end

function CreDocument:highlightXPointer(xp)
    -- with xp=nil, clears previous highlight(s)
    return self._document:highlightXPointer(xp)
end

function CreDocument:getDocumentFileContent(filepath)
    if filepath then
        return self._document:getDocumentFileContent(filepath)
    end
end

function CreDocument:getTextFromXPointer(xp)
    if xp then
        return self._document:getTextFromXPointer(xp)
    end
end

function CreDocument:getTextFromXPointers(pos0, pos1)
    return self._document:getTextFromXPointers(pos0, pos1)
end

function CreDocument:getHTMLFromXPointer(xp, flags, from_final_parent)
    if xp then
        return self._document:getHTMLFromXPointer(xp, flags, from_final_parent)
    end
end

function CreDocument:getHTMLFromXPointers(xp0, xp1, flags, from_root_node)
    if xp0 and xp1 then
        return self._document:getHTMLFromXPointers(xp0, xp1, flags, from_root_node)
    end
end

function CreDocument:getNormalizedXPointer(xp)
    -- Returns false when xpointer is not found in the DOM.
    -- When requested DOM version >= getDomVersionWithNormalizedXPointers,
    -- should return xp unmodified when found.
    return self._document:getNormalizedXPointer(xp)
end

function CreDocument:gotoPos(pos)
    logger.dbg("CreDocument: goto position", pos)
    self._document:gotoPos(pos)
end

function CreDocument:gotoPage(page, internal)
    logger.dbg("CreDocument: goto page", page, "flow", self:getPageFlow(page))
    self._document:gotoPage(page, internal)
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

function CreDocument:getCurrentPage(internal)
    return self._document:getCurrentPage(internal)
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
        -- +1 +128x5 +256x5: we want our main font, even if it has no italic
        -- nor bold variant (eg FreeSerif), to win over all other fonts that
        -- have an italic or bold variant:
        --   italic_match = 5 * (256 for real italic, or 128 for fake italic
        --   weight_match = 5 * (256 - weight_diff * 256 / 800)
        -- so give our font a bias enough to win over real italic or bold fonts
        -- (all others params (size, family, name), used for computing the match
        -- score, have a factor of 100 or 1000 vs the 5 used for italic & weight,
        -- so it shouldn't hurt much).
        -- Note that this is mostly necessary when forcing a not found name,
        -- as we do in the Ignore font-family style tweak.
        self._document:setAsPreferredFontWithBias(new_font_face, 1 + 128*5 + 256*5)
    end
end

function CreDocument:setupFallbackFontFaces()
    local fallbacks = {}
    local seen_fonts = {}
    local user_fallback = G_reader_settings:readSetting("fallback_font")
    if user_fallback then
        table.insert(fallbacks, user_fallback)
        seen_fonts[user_fallback] = true
    end
    for _, font_name in pairs(self.fallback_fonts) do
        if not seen_fonts[font_name] then
            table.insert(fallbacks, font_name)
            seen_fonts[font_name] = true
        end
    end
    if G_reader_settings:isFalse("additional_fallback_fonts") then
        -- Keep the first fallback font (user set or first from self.fallback_fonts),
        -- as crengine won't reset its current set when provided with an empty string
        for i=#fallbacks, 2, -1 do
            table.remove(fallbacks, i)
        end
    end
    -- We use '|' as the delimiter (which is less likely to be found in font
    -- names than ',' or ';', without the need to have to use quotes.
    local s_fallbacks = table.concat(fallbacks, "|")
    logger.dbg("CreDocument: set fallback font faces:", s_fallbacks)
    self._document:setStringProperty("crengine.font.fallback.faces", s_fallbacks)
end

-- To use the new crengine language typography facilities (hyphenation, line breaking,
-- OpenType fonts locl letter forms...)
function CreDocument:setTextMainLang(lang)
    if lang then
        logger.dbg("CreDocument: set textlang main lang", lang)
        self._document:setStringProperty("crengine.textlang.main.lang", lang)
    end
end

function CreDocument:setTextEmbeddedLangs(toggle)
    logger.dbg("CreDocument: set textlang embedded langs", toggle)
    self._document:setStringProperty("crengine.textlang.embedded.langs.enabled", toggle and 1 or 0)
end

function CreDocument:setTextHyphenation(toggle)
    logger.dbg("CreDocument: set textlang hyphenation enabled", toggle)
    self._document:setStringProperty("crengine.textlang.hyphenation.enabled", toggle and 1 or 0)
end

function CreDocument:setTextHyphenationSoftHyphensOnly(toggle)
    logger.dbg("CreDocument: set textlang hyphenation soft hyphens only", toggle)
    self._document:setStringProperty("crengine.textlang.hyphenation.soft.hyphens.only", toggle and 1 or 0)
end

function CreDocument:setTextHyphenationForceAlgorithmic(toggle)
    logger.dbg("CreDocument: set textlang hyphenation force algorithmic", toggle)
    self._document:setStringProperty("crengine.textlang.hyphenation.force.algorithmic", toggle and 1 or 0)
end

function CreDocument:getTextMainLangDefaultHyphDictionary()
    local main_lang_tag, main_lang_active_hyph_dict, loaded_lang_infos = cre.getTextLangStatus() -- luacheck: no unused
    return loaded_lang_infos[main_lang_tag] and loaded_lang_infos[main_lang_tag].hyph_dict_name
end

-- To use the old crengine hyphenation manager (only one global hyphenation method)
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
            self._view_mode = self.SCROLL_VIEW_MODE
        else
            self._view_mode = self.PAGE_VIEW_MODE
        end
        self._document:setViewMode(self._view_mode)
        if self.hide_nonlinear_flows then
            self:cacheFlows()
        end
    end
end

function CreDocument:setViewDimen(dimen)
    logger.dbg("CreDocument: set view dimen", dimen)
    self._document:setViewDimen(dimen.w, dimen.h)
end

function CreDocument:setHeaderProgressMarks(pages, ticks)
    self._document:setHeaderProgressMarks(pages, ticks)
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

function CreDocument:setFontBaseWeight(weight)
    -- In frontend, we use: 0, 1, -0.5, a delta from the regular weight of 400.
    -- crengine expects for these: 400, 500, 350
    local cre_weight = math.floor(400 + weight*100)
    logger.dbg("CreDocument: set font base weight", weight, "=", cre_weight)
    self._document:setIntProperty("font.face.base.weight", cre_weight)
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

function CreDocument:setWordSpacing(values)
    -- values should be a table of 2 numbers (e.g.: { 90, 75 })
    -- - space width scale percent (hard scale the width of each space char in
    --   all fonts - 100 to use the normal font space glyph width unchanged).
    -- - min space condensing percent (how much we can additionally decrease
    --   a space width to make text fit on a line).
    logger.dbg("CreDocument: set space width scale", values[1])
    self._document:setIntProperty("crengine.style.space.width.scale.percent", values[1])
    logger.dbg("CreDocument: set space condensing", values[2])
    self._document:setIntProperty("crengine.style.space.condensing.percent", values[2])
end

function CreDocument:setWordExpansion(value)
    logger.dbg("CreDocument: set word expansion", value)
    self._document:setIntProperty("crengine.style.max.added.letter.spacing.percent", value or 0)
end

function CreDocument:setStyleSheet(new_css_file, appended_css_content )
    logger.dbg("CreDocument: set style sheet:",
        new_css_file and new_css_file or "no file",
        appended_css_content and "and appended content ("..#appended_css_content.." bytes)" or "(no appended content)")
    self._document:setStyleSheet(new_css_file, appended_css_content)
end

function CreDocument:setEmbeddedStyleSheet(toggle)
    --- @fixme occasional segmentation fault when switching embedded style sheet
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

function CreDocument:setBlockRenderingFlags(flags)
    logger.dbg("CreDocument: set block rendering flags", string.format("0x%x", flags))
    self._document:setIntProperty("crengine.render.block.rendering.flags", flags)
end

function CreDocument:setImageScaling(toggle)
    logger.dbg("CreDocument: set smooth scaling", toggle)
    self._smooth_scaling = toggle
end

function CreDocument:setNightmodeImages(toggle)
    logger.dbg("CreDocument: set nightmode images", toggle)
    self._nightmode_images = toggle
end

function CreDocument:setFloatingPunctuation(enabled)
    --- @fixme occasional segmentation fault when toggling floating punctuation
    logger.dbg("CreDocument: set floating punctuation", enabled)
    self._document:setIntProperty("crengine.style.floating.punctuation.enabled", enabled)
end

function CreDocument:setTxtPreFormatted(enabled)
    logger.dbg("CreDocument: set txt preformatted", enabled)
    self._document:setIntProperty("crengine.file.txt.preformatted", enabled)
end

-- get crengine internal visible page count (to be used when doing specific
-- screen position handling)
function CreDocument:getVisiblePageCount()
    return self._document:getVisiblePageCount()
end

function CreDocument:setVisiblePageCount(new_count)
    logger.dbg("CreDocument: set visible page count", new_count)
    self._document:setVisiblePageCount(new_count, false)
end

-- get visible page number count (to be used when only interested in page numbers)
function CreDocument:getVisiblePageNumberCount()
    return self._document:getVisiblePageNumberCount()
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

function CreDocument:setBackgroundColor(bgcolor) -- use nil to set to white
    logger.dbg("CreDocument: set background color", bgcolor)
    self._document:setBackgroundColor(bgcolor)
end

function CreDocument:setBackgroundImage(img_path) -- use nil to unset
    logger.dbg("CreDocument: set background image", img_path)
    self._document:setBackgroundImage(img_path)
end

function CreDocument:checkRegex(pattern)
    logger.dbg("CreDocument: check regex ", pattern)
    return self._document:checkRegex(pattern)
end

function CreDocument:getAndClearRegexSearchError()
    local retval = self._document:getAndClearRegexSearchError()
    logger.dbg("CreDocument: getAndClearRegexSearchError", retval)
    return retval
end

function CreDocument:findText(pattern, origin, reverse, caseInsensitive, page, regex, max_hits)
    logger.dbg("CreDocument: find text", pattern, origin, reverse, caseInsensitive, regex, max_hits)
    return self._document:findText(
        pattern, origin, reverse, caseInsensitive and 1 or 0, regex and 1 or 0, max_hits or 200)
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

function CreDocument:setCallback(func)
    return self._document:setCallback(func)
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

function CreDocument:getStatistics()
    return self._document:getStatistics()
end

function CreDocument:getUnknownEntities()
    return self._document:getUnknownEntities()
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

function CreDocument:hasPageMap()
    return self._document:hasPageMap()
end

function CreDocument:getPageMap()
    return self._document:getPageMap()
end

function CreDocument:getPageMapSource()
    return self._document:getPageMapSource()
end

function CreDocument:getPageMapCurrentPageLabel()
    return self._document:getPageMapCurrentPageLabel()
end

function CreDocument:getPageMapFirstPageLabel()
    return self._document:getPageMapFirstPageLabel()
end

function CreDocument:getPageMapLastPageLabel()
    return self._document:getPageMapLastPageLabel()
end

function CreDocument:getPageMapXPointerPageLabel(xp)
    return self._document:getPageMapXPointerPageLabel(xp)
end

function CreDocument:getPageMapVisiblePageLabels()
    return self._document:getPageMapVisiblePageLabels()
end

function CreDocument:register(registry)
    registry:addProvider("azw", "application/vnd.amazon.mobi8-ebook", self, 90)
    registry:addProvider("azw", "application/x-mobi8-ebook", self, 90) -- Alternative mimetype for OPDS.
    registry:addProvider("chm", "application/vnd.ms-htmlhelp", self, 90)
    registry:addProvider("doc", "application/msword", self, 90)
    registry:addProvider("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", self, 90)
    registry:addProvider("epub", "application/epub+zip", self, 100)
    registry:addProvider("epub3", "application/epub+zip", self, 100)
    registry:addProvider("fb2", "application/fb2", self, 90)
    registry:addProvider("fb2", "text/fb2+xml", self, 90) -- Alternative mimetype for OPDS.
    registry:addProvider("fb2.zip", "application/zip", self, 90)
    registry:addProvider("fb2.zip", "application/fb2+zip", self, 90) -- Alternative mimetype for OPDS.
    registry:addProvider("fb3", "application/fb3", self, 90)
    registry:addProvider("htm", "text/html", self, 100)
    registry:addProvider("html", "text/html", self, 100)
    registry:addProvider("htm.zip", "application/zip", self, 100)
    registry:addProvider("html.zip", "application/zip", self, 100)
    registry:addProvider("log", "text/plain", self)
    registry:addProvider("log.zip", "application/zip", self)
    registry:addProvider("md", "text/plain", self)
    registry:addProvider("md.zip", "application/zip", self)
    registry:addProvider("mobi", "application/x-mobipocket-ebook", self, 90)
    registry:addProvider("odt", "application/vnd.oasis.opendocument.text ", self, 90)
    -- Palmpilot Document File
    registry:addProvider("pdb", "application/vnd.palm", self, 90)
    -- Palmpilot Resource File
    registry:addProvider("prc", "application/vnd.palm", self)
    registry:addProvider("tcr", "application/tcr", self)
    registry:addProvider("txt", "text/plain", self, 90)
    registry:addProvider("txt.zip", "application/zip", self, 90)
    registry:addProvider("rtf", "application/rtf", self, 90)
    registry:addProvider("xhtml", "application/xhtml+xml", self, 100)
    registry:addProvider("xml", "application/xml", self, 90)
    registry:addProvider("zip", "application/zip", self, 10)
    -- Scripts that we allow running in the FM (c.f., Device:canExecuteScript)
    registry:addProvider("sh", "application/x-shellscript", self, 90)
    registry:addProvider("py", "text/x-python", self, 90)
end

-- no-op that will be wrapped by setupCallCache
function CreDocument:resetCallCache() end

-- no-op that will be wrapped by setupCallCache
function CreDocument:resetBufferCache() end

-- Optimise usage of some of the above methods by caching their results,
-- either globally, or per page/pos for those whose result may depend on
-- current page number or y-position.
function CreDocument:setupCallCache()
    if not G_reader_settings:nilOrTrue("use_cre_call_cache") then
        logger.dbg("CreDocument: not using cre call cache")
        return
    end
    logger.dbg("CreDocument: using cre call cache")
    local do_stats = G_reader_settings:isTrue("use_cre_call_cache_log_stats")
    -- Tune these when debugging
    local do_stats_include_not_cached = false
    local do_log = false

    -- Beware below for luacheck warnings "shadowing upvalue argument 'self'":
    -- the 'self' we got and use here, and the one we may get implicitely
    -- as first parameter of the methods we define or redefine, are actually
    -- the same, but luacheck doesn't know that and would logically complain.
    -- So, we define our helpers (self._callCache*) as functions and not methods:
    -- no 'self' as first argument, use 'self.' and not 'self:' when calling them.

    -- reset full cache
    self._callCacheReset = function()
        -- "Global" cache, a simple key, value store for *this* document
        self._global_call_cache = {}
        -- "Tags" cache, an LRU cache of per-tag simple key, value stores. 10 slots.
        if self._tag_list_call_cache then
            self._tag_list_call_cache:clear()
        else
            self._tag_list_call_cache = lru.new(10, nil, false)
        end
        -- i.e., the only thing that follows any sort of LRU eviction logic is the *list* of tag caches.
        -- Each individual cache itself is just a simple key, value store (i.e., a hash map).
        -- Points to said per-tag cache for the current tag.
        self._tag_call_cache = nil
        -- Stores the key for said current tag
        self._current_call_cache_tag = nil
    end
    self._callCacheDestroy = function()
        --- @note: Explicitly destroying the references to the caches is apparently necessary to get their content collected by the GC...
        ---        c.f., https://github.com/koreader/koreader/pull/7634#discussion_r627820424
        self._global_call_cache = nil
        self._tag_list_call_cache = nil
        self._tag_call_cache = nil
        self._current_call_cache_tag = nil
    end
    -- global cache
    self._callCacheGet = function(key)
        return self._global_call_cache[key]
    end
    self._callCacheSet = function(key, value)
        self._global_call_cache[key] = value
    end

    -- current tag (page, pos) sub-cache
    self._callCacheSetCurrentTag = function(tag)
        -- If it already exists, return it and make it the MRU
        self._tag_call_cache = self._tag_list_call_cache:get(tag)
        if not self._tag_call_cache then
            -- Otherwise, create it and insert it in the list cache, evicting the LRU tag cache if necessary.
            self._tag_call_cache = {}
            self._tag_list_call_cache:set(tag, self._tag_call_cache)
        end
        self._current_call_cache_tag = tag
    end
    self._callCacheGetCurrentTag = function(tag)
        return self._current_call_cache_tag
    end
    -- per current tag cache
    self._callCacheTagGet = function(key)
        if self._tag_call_cache then
            return self._tag_call_cache[key]
        end
    end
    self._callCacheTagSet = function(key, value)
        if self._tag_call_cache then
            self._tag_call_cache[key] = value
        end
    end
    self._callCacheReset()

    local no_op = function() end
    local addStatMiss = no_op
    local addStatHit = no_op
    local dumpStats = no_op
    local now = no_op
    if do_stats then
        -- cache statistics
        self._call_cache_stats = {}
        now = function()
            return TimeVal:now()
        end
        addStatMiss = function(name, starttime, not_cached)
            local duration = TimeVal:getDuration(starttime)
            if not self._call_cache_stats[name] then
                self._call_cache_stats[name] = {0, 0.0, 1, duration, not_cached}
            else
                local stat = self._call_cache_stats[name]
                stat[3] = stat[3] + 1
                stat[4] = stat[4] + duration
            end
        end
        addStatHit = function(name, starttime)
            local duration = TimeVal:getDuration(starttime)
            if not self._call_cache_stats[name] then
                self._call_cache_stats[name] = {1, duration, 0, 0.0}
            else
                local stat = self._call_cache_stats[name]
                stat[1] = stat[1] + 1
                stat[2] = stat[2] + duration
            end
        end
        dumpStats = function()
            logger.info("cre call cache statistics:\n" .. self.getCallCacheStatistics())
        end
        -- Make this one non-local, in case we want to have it shown via a menu item
        self.getCallCacheStatistics = function()
            local util = require("util")
            local res = {}
            table.insert(res, "CRE call cache content:")
            table.insert(res, string.format("     all: %d items", util.tableSize(self._global_call_cache) + self._tag_list_call_cache:used_slots()))
            table.insert(res, string.format("  global: %d items", util.tableSize(self._global_call_cache)))
            table.insert(res, string.format("    tags: %d items", self._tag_list_call_cache:used_slots()))
            for tag, tag_cache in self._tag_list_call_cache:pairs() do
                table.insert(res, string.format("          '%s': %d items", tag,
                        util.tableSize(tag_cache)))
            end
            local hit_keys = {}
            local nohit_keys = {}
            local notcached_keys = {}
            for k, v in pairs(self._call_cache_stats) do
                if self._call_cache_stats[k][1] > 0 then
                    table.insert(hit_keys, k)
                else
                    if #v > 4 then
                        table.insert(notcached_keys, k)
                    else
                        table.insert(nohit_keys, k)
                    end
                end
            end
            table.sort(hit_keys)
            table.sort(nohit_keys)
            table.sort(notcached_keys)
            table.insert(res, "CRE call cache hits statistics:")
            local total_duration = 0
            local total_duration_saved = 0
            for _, k in ipairs(hit_keys) do
                local hits, hits_duration, misses, missed_duration = unpack(self._call_cache_stats[k])
                local total = hits + misses
                local pct_hit = 100.0 * hits / total
                local duration_avoided = 1.0 * hits * missed_duration / misses
                local duration_added_s = ""
                if hits_duration >= 0.001 then
                    duration_added_s = string.format(" (-%.3fs)", hits_duration)
                end
                local pct_duration_avoided = 100.0 * duration_avoided / (missed_duration + hits_duration + duration_avoided)
                table.insert(res, string.format("    %s: %d/%d hits (%d%%) %.3fs%s saved, %.3fs used (%d%% saved)", k, hits, total,
                        pct_hit, duration_avoided, duration_added_s, missed_duration, pct_duration_avoided))
                total_duration = total_duration + missed_duration + hits_duration
                total_duration_saved = total_duration_saved + duration_avoided - hits_duration
            end
            table.insert(res, "  By call times (hits | misses):")
            for _, k in ipairs(hit_keys) do
                local hits, hits_duration, misses, missed_duration = unpack(self._call_cache_stats[k])
                table.insert(res, string.format("    %s: (%d) %.3f ms | %.3f ms (%d)", k, hits, 1000*hits_duration/hits, 1000*missed_duration/misses, misses))
            end
            table.insert(res, "  No hit for:")
            for _, k in ipairs(nohit_keys) do
                local hits, hits_duration, misses, missed_duration = unpack(self._call_cache_stats[k]) -- luacheck: no unused
                table.insert(res, string.format("    %s: %d misses %.3fs",
                        k, misses, missed_duration))
                total_duration = total_duration + missed_duration + hits_duration
            end
            if #notcached_keys > 0 then
                table.insert(res, "  No cache for:")
                for _, k in ipairs(notcached_keys) do
                    local hits, hits_duration, misses, missed_duration = unpack(self._call_cache_stats[k]) -- luacheck: no unused
                    table.insert(res, string.format("    %s: %d calls %.3fs",
                            k, misses, missed_duration))
                    total_duration = total_duration + missed_duration + hits_duration
                end
            end
            local pct_duration_saved = 100.0 * total_duration_saved / (total_duration + total_duration_saved)
            table.insert(res, string.format("  cpu time used: %.3fs, saved: %.3fs (%d%% saved)", total_duration, total_duration_saved, pct_duration_saved))
            return table.concat(res, "\n")
        end
    end

    -- Tweak CreDocument functions for cache interaction
    -- No need to tweak metatable and play with __index, we just put
    -- in self wrapped copies of the original CreDocument functions.
    for name, func in pairs(CreDocument) do
        if type(func) == "function" then
            -- Various type of wrap
            local no_wrap = false -- luacheck: no unused
            local add_reset = false
            local add_buffer_trash = false
            local cache_by_tag = false
            local cache_global = false
            local set_tag = nil
            local set_arg = nil
            local set_arg2 = nil
            local is_cached = false

            -- Assume all set* may change rendering
            if name == "setBatteryState" then no_wrap = true -- except this one
            elseif name:sub(1,3) == "set" then add_reset = true
            elseif name:sub(1,6) == "toggle" then add_reset = true
            elseif name:sub(1,6) == "update" then add_reset = true
            elseif name:sub(1,6) == "enable" then add_reset = true
            elseif name == "zoomFont" then add_reset = true -- not used by koreader
            elseif name == "resetCallCache" then add_reset = true
            elseif name == "cacheFlows" then add_reset = true

            -- These may have crengine do native highlight or unhighlight
            -- (we could keep the original buffer and use a scratch buffer while
            -- these are used, but not worth bothering)
            elseif name == "clearSelection" then add_buffer_trash = true
            elseif name == "highlightXPointer" then add_buffer_trash = true
            elseif name == "getWordFromPosition" then add_buffer_trash = true
            elseif name == "getTextFromPositions" then add_buffer_trash = true
            elseif name == "findText" then add_buffer_trash = true
            elseif name == "resetBufferCache" then add_buffer_trash = true

            -- These may change page/pos
            elseif name == "gotoPage" then set_tag = "page" ; set_arg = 2 ; set_arg2 = 3
            elseif name == "gotoPos" then set_tag = "pos" ; set_arg = 2
            elseif name == "drawCurrentViewByPos" then set_tag = "pos" ; set_arg = 6
            -- elseif name == "drawCurrentViewByPage" then set_tag = "page" ; set_arg = 6
            -- drawCurrentViewByPage() has some tweaks when browsing half-pages for
            -- text selection in two-pages mode: no need to wrap it, as it uses
            -- internally 2 other functions that are themselves wrapped

            -- gotoXPointer() is for cre internal fixup, we always use gotoPage/Pos
            -- (goBack, goForward, gotoLink are not used)

            -- For some, we prefer no cache (if they cost nothing, return some huge
            -- data that we'd rather not cache, are called with many different args,
            -- or we'd rather have up to date crengine state)
            elseif name == "getCurrentPage" then no_wrap = true
            elseif name == "getCurrentPos" then no_wrap = true
            elseif name == "getVisiblePageCount" then no_wrap = true
            elseif name == "getVisiblePageNumberCount" then no_wrap = true
            elseif name == "getCoverPageImage" then no_wrap = true
            elseif name == "getDocumentFileContent" then no_wrap = true
            elseif name == "getHTMLFromXPointer" then no_wrap = true
            elseif name == "getHTMLFromXPointers" then no_wrap = true
            elseif name == "getImageFromPosition" then no_wrap = true
            elseif name == "getTextFromXPointer" then no_wrap = true
            elseif name == "getTextFromXPointers" then no_wrap = true
            elseif name == "getPageOffsetX" then no_wrap = true
            elseif name == "getNextVisibleWordStart" then no_wrap = true
            elseif name == "getNextVisibleWordEnd" then no_wrap = true
            elseif name == "getPrevVisibleWordStart" then no_wrap = true
            elseif name == "getPrevVisibleWordEnd" then no_wrap = true
            elseif name == "getPrevVisibleChar" then no_wrap = true
            elseif name == "getNextVisibleChar" then no_wrap = true
            elseif name == "getCacheFilePath" then no_wrap = true
            elseif name == "getStatistics" then no_wrap = true
            elseif name == "getNormalizedXPointer" then no_wrap = true
            elseif name == "getNextPage" then no_wrap = true
            elseif name == "getPrevPage" then no_wrap = true
            elseif name == "getPageFlow" then no_wrap = true
            elseif name == "getPageNumberInFlow" then no_wrap = true
            elseif name == "getTotalPagesLeft" then no_wrap = true

            -- Some get* have different results by page/pos
            elseif name == "getLinkFromPosition" then cache_by_tag = true
            elseif name == "getPageLinks" then cache_by_tag = true
            elseif name == "getScreenBoxesFromPositions" then cache_by_tag = true
            elseif name == "getScreenPositionFromXPointer" then cache_by_tag = true
            elseif name == "getXPointer" then cache_by_tag = true
            elseif name == "isXPointerInCurrentPage" then cache_by_tag = true
            elseif name == "getPageMapCurrentPageLabel" then cache_by_tag = true
            elseif name == "getPageMapVisiblePageLabels" then cache_by_tag = true

            -- Assume all remaining get* can have their results
            -- cached globally by function arguments
            elseif name:sub(1,3) == "get" then cache_global = true

            -- All others don't need to be wrapped
            end

            if add_reset then
                self[name] = function(...)
                    -- logger.dbg("callCache:", name, "called with", select(2,...))
                    if do_log then logger.dbg("callCache:", name, "reseting cache") end
                    self._callCacheReset()
                    return func(...)
                end
            elseif add_buffer_trash then
                self[name] = function(...)
                    if do_log then logger.dbg("callCache:", name, "reseting buffer") end
                    self._callCacheSet("current_buffer_tag", nil)
                    return func(...)
                end
            elseif set_tag then
                self[name] = function(...)
                    if do_log then logger.dbg("callCache:", name, "setting tag") end
                    local val = select(set_arg, ...)
                    if set_arg2 then
                        local val2 = select(set_arg2, ...)
                        if val2 ~= nil then
                            val = val .. tostring(val2)
                        end
                    end
                    self._callCacheSetCurrentTag(set_tag .. val)
                    return func(...)
                end
            elseif cache_by_tag then
                is_cached = true
                self[name] = function(...)
                    local starttime = now()
                    local cache_key = name .. buffer.encode({select(2, ...)})
                    local results = self._callCacheTagGet(cache_key)
                    if results then
                        if do_log then logger.dbg("callCache:", name, "cache hit:", cache_key) end
                        addStatHit(name, starttime)
                        -- We might want to return a deep-copy of results, in case callers
                        -- play at modifying values. But it looks like none currently do.
                        -- So, better to keep calling code not modifying returned results.
                        return unpack(results)
                    else
                        if do_log then logger.dbg("callCache:", name, "cache miss:", cache_key) end
                        results = { func(...) }
                        self._callCacheTagSet(cache_key, results)
                        addStatMiss(name, starttime)
                        return unpack(results)
                    end
                end
            elseif cache_global then
                is_cached = true
                self[name] = function(...)
                    local starttime = now()
                    local cache_key = name .. buffer.encode({select(2, ...)})
                    local results = self._callCacheGet(cache_key)
                    if results then
                        if do_log then logger.dbg("callCache:", name, "cache hit:", cache_key) end
                        addStatHit(name, starttime)
                        -- See comment above
                        return unpack(results)
                    else
                        if do_log then logger.dbg("callCache:", name, "cache miss:", cache_key) end
                        results = { func(...) }
                        self._callCacheSet(cache_key, results)
                        addStatMiss(name, starttime)
                        return unpack(results)
                    end
                end
            end
            if do_stats_include_not_cached and not is_cached then
                local func2 = self[name] -- might already be wrapped
                self[name] = function(...)
                    local starttime = now()
                    local results = { func2(...) }
                    addStatMiss(name, starttime, true) -- not_cached = true
                    return unpack(results)
                end
            end
        end
    end
    -- We override a bit more specifically the one responsible for drawing page
    self.drawCurrentView = function(_self, target, x, y, rect, pos)
        local do_draw = false
        local current_tag = _self._callCacheGetCurrentTag()
        local current_buffer_tag = _self._callCacheGet("current_buffer_tag")
        if _self.buffer and (_self.buffer.w ~= rect.w or _self.buffer.h ~= rect.h) then
            do_draw = true
        elseif not _self.buffer then
            do_draw = true
        elseif not current_buffer_tag then
            do_draw = true
        elseif current_buffer_tag ~= current_tag then
            do_draw = true
        end
        local starttime = now()
        if do_draw then
            if do_log then logger.dbg("callCache: ########## drawCurrentView: full draw") end
            CreDocument.drawCurrentView(_self, target, x, y, rect, pos)
            addStatMiss("drawCurrentView", starttime)
            _self._callCacheSet("current_buffer_tag", current_tag)
        else
            if do_log then logger.dbg("callCache: ---------- drawCurrentView: light draw") end
            target:blitFrom(_self.buffer, x, y, 0, 0, rect.w, rect.h)
            addStatHit("drawCurrentView", starttime)
        end
    end
    -- Dump statistics on close
    if do_stats then
        self.close = function(_self)
            dumpStats()
            CreDocument.close(_self)
        end
    end
end

return CreDocument
