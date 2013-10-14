require "dbg"
require "cache"
require "ui/geometry"
require "ui/device"
require "ui/screen"
require "ui/reader/readerconfig"

KoptInterface = {
	tessocr_data = "data",
	ocr_lang = "eng",
	ocr_type = 3, -- default 0, for more accuracy use 3
	last_context_size = nil,
	default_context_size = 1024*1024,
	screen_dpi = Screen:getDPI(),
}

ContextCacheItem = CacheItem:new{}

function ContextCacheItem:onFree()
	if self.kctx.free then
		DEBUG("free koptcontext", self.kctx)
		self.kctx:free()
	end
end

OCREngine = CacheItem:new{}

function OCREngine:onFree()
	if self.ocrengine.freeOCR then
		DEBUG("free OCREngine", self.ocrengine)
		self.ocrengine:freeOCR()
	end
end

function KoptInterface:waitForContext(kc)
	-- if koptcontext is being processed in background thread
	-- the isPreCache will return 1.
	while kc and kc:isPreCache() == 1 do
		DEBUG("waiting for background rendering")
		util.usleep(100000)
	end
	return kc
end

--[[
get reflow context
--]]
function KoptInterface:createContext(doc, pageno, bbox)
	-- Now koptcontext keeps track of its dst bitmap reflowed by libk2pdfopt.
	-- So there is no need to check background context when creating new context.
	local kc = KOPTContext.new()
	local screen_size = Screen:getSize()
	local lang = doc.configurable.doc_language
	if lang == "chi_sim" or lang == "chi_tra" or 
		lang == "jpn" or lang == "kor" then
		kc:setCJKChar()
	end
	kc:setLanguage(lang)
	kc:setTrim(doc.configurable.trim_page)
	kc:setWrap(doc.configurable.text_wrap)
	kc:setIndent(doc.configurable.detect_indent)
	kc:setRotate(doc.configurable.screen_rotation)
	kc:setColumns(doc.configurable.max_columns)
	kc:setDeviceDim(screen_size.w, screen_size.h)
	kc:setDeviceDPI(self.screen_dpi)
	kc:setStraighten(doc.configurable.auto_straighten)
	kc:setJustification(doc.configurable.justification)
	kc:setZoom(doc.configurable.font_size)
	kc:setMargin(doc.configurable.page_margin)
	kc:setQuality(doc.configurable.quality)
	kc:setContrast(doc.configurable.contrast)
	kc:setDefectSize(doc.configurable.defect_size)
	kc:setLineSpacing(doc.configurable.line_spacing)
	kc:setWordSpacing(doc.configurable.word_spacing)
	if bbox then kc:setBBox(bbox.x0, bbox.y0, bbox.x1, bbox.y1) end
	if Dbg.is_on then kc:setDebug() end
	return kc
end

function KoptInterface:getContextHash(doc, pageno, bbox)
	local screen_size = Screen:getSize()
	local screen_size_hash = screen_size.w.."|"..screen_size.h
	local bbox_hash = bbox.x0.."|"..bbox.y0.."|"..bbox.x1.."|"..bbox.y1
	return doc.file.."|"..pageno.."|"..doc.configurable:hash("|").."|"..bbox_hash.."|"..screen_size_hash
end

function KoptInterface:getPageBBox(doc, pageno)
	if doc.configurable.text_wrap ~= 1 and doc.configurable.trim_page == 1 then
		-- auto bbox finding
		return self:getAutoBBox(doc, pageno)
	elseif doc.configurable.text_wrap ~= 1 and doc.configurable.trim_page == 2 then
		-- semi-auto bbox finding
		return self:getSemiAutoBBox(doc, pageno)
	else
		-- get saved manual bbox
		return Document.getPageBBox(doc, pageno)
	end
end

--[[
auto detect bbox
--]]
function KoptInterface:getAutoBBox(doc, pageno)	
	local native_size = Document.getNativePageDimensions(doc, pageno)
	local bbox = {
		x0 = 0, y0 = 0,
		x1 = native_size.w,
		y1 = native_size.h,
	}
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "autobbox|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local page = doc._document:openPage(pageno)
		local kc = self:createContext(doc, pageno, bbox)
		--DEBUGBT()
		--DEBUG("getAutoBBox:native page size", native_size)
		local x0, y0, x1, y1 = page:getAutoBBox(kc)
		local w, h = native_size.w, native_size.h
		if (x1 - x0)/w > 0.1 or (y1 - y0)/h > 0.1 then
			bbox.x0, bbox.y0, bbox.x1, bbox.y1 = x0, y0, x1, y1
			--DEBUG("getAutoBBox:auto detected bbox", bbox)
		else
			bbox = Document.getPageBBox(doc, pageno)
			--DEBUG("getAutoBBox:use manual bbox", bbox)
		end
		Cache:insert(hash, CacheItem:new{ autobbox = bbox })
		page:close()
		kc:free()
		return bbox
	else
		return cached.autobbox
	end
end

--[[
detect bbox within user restricted bbox
--]]
function KoptInterface:getSemiAutoBBox(doc, pageno)
	-- use manual bbox
	local bbox = Document.getPageBBox(doc, pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "semiautobbox|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local page = doc._document:openPage(pageno)
		local kc = self:createContext(doc, pageno, bbox)
		local auto_bbox = {}
		auto_bbox.x0, auto_bbox.y0, auto_bbox.x1, auto_bbox.y1 = page:getAutoBBox(kc)
		auto_bbox.x0 = auto_bbox.x0 + bbox.x0
		auto_bbox.y0 = auto_bbox.y0 + bbox.y0
		auto_bbox.x1 = auto_bbox.x1 + bbox.x0
		auto_bbox.y1 = auto_bbox.y1 + bbox.y0
		DEBUG("Semi-auto detected bbox", auto_bbox)
		page:close()
		Cache:insert(hash, CacheItem:new{ semiautobbox = auto_bbox })
		kc:free()
		return auto_bbox
	else
		return cached.semiautobbox
	end
end

--[[
get cached koptcontext for centain page. if context doesn't exist in cache make
new context and reflow the src page immediatly, or wait background thread for
reflowed context.
--]]
function KoptInterface:getCachedContext(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	if not cached then
		-- If kctx is not cached, create one and get reflowed bmp in foreground.
		local kc = self:createContext(doc, pageno, bbox)
		local page = doc._document:openPage(pageno)
		-- reflow page
		--local secs, usecs = util.gettime()
		page:reflow(kc, 0)
		page:close()
		--local nsecs, nusecs = util.gettime()
		--local dur = nsecs - secs + (nusecs - usecs) / 1000000
		--DEBUG("Reflow duration:", dur)
		--self:logReflowDuration(pageno, dur)
		local fullwidth, fullheight = kc:getPageDim()
		DEBUG("reflowed page", pageno, "fullwidth:", fullwidth, "fullheight:", fullheight)
		self.last_context_size = fullwidth * fullheight + 128 -- estimation
		Cache:insert(kctx_hash, ContextCacheItem:new{
			size = self.last_context_size,
			kctx = kc
		})
		return kc
	else
		-- wait for background thread
		local kc = self:waitForContext(cached.kctx)
		local fullwidth, fullheight = kc:getPageDim()
		self.last_context_size = fullwidth * fullheight + 128 -- estimation
		return kc
	end
end

--[[
get page dimensions
--]]
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
	if doc.configurable.text_wrap == 1 then
		return self:getRFPageDimensions(doc, pageno, zoom, rotation)
	else
		return Document.getPageDimensions(doc, pageno, zoom, rotation)
	end
end

--[[
get reflowed page dimensions
--]]
function KoptInterface:getRFPageDimensions(doc, pageno, zoom, rotation)
	local kc = self:getCachedContext(doc, pageno)
	local fullwidth, fullheight = kc:getPageDim()
	return Geom:new{ w = fullwidth, h = fullheight }
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, gamma, render_mode)
	--DEBUG("log memory usage at renderPage")
	--self:logMemoryUsage(pageno)
	if doc.configurable.text_wrap == 1 then
		return self:renderreflowedPage(doc, pageno, rect, zoom, rotation, render_mode)
	else
		return Document.renderPage(doc, pageno, rect, zoom, rotation, gamma, render_mode)
	end
end

--[[
inherited from common document interface
render reflowed page into tile cache.
--]] 
function KoptInterface:renderreflowedPage(doc, pageno, rect, zoom, rotation, render_mode)
	doc.render_mode = render_mode
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local renderpg_hash = "renderpg|"..context_hash

	local cached = Cache:check(renderpg_hash)
	if not cached then
		-- do the real reflowing if kctx is not been cached yet
		local kc = self:getCachedContext(doc, pageno)
		local fullwidth, fullheight = kc:getPageDim()
		if not Cache:willAccept(fullwidth * fullheight / 2) then
			-- whole page won't fit into cache
			error("aborting, since we don't have enough cache for this page")
		end
		local page = doc._document:openPage(pageno)
		-- prepare cache item with contained blitbuffer
		local tile = TileCacheItem:new{
			size = fullwidth * fullheight / 2 + 64, -- estimation
			excerpt = Geom:new{ w = fullwidth, h = fullheight },
			pageno = pageno,
			bb = Blitbuffer.new(fullwidth, fullheight)
		}
		page:rfdraw(kc, tile.bb)
		page:close()
		Cache:insert(renderpg_hash, tile)
		return tile
	else
		return cached
	end
end

function KoptInterface:hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
	if doc.configurable.text_wrap == 1 then
		self:hintReflowedPage(doc, pageno, zoom, rotation, gamma, render_mode)
	else
		Document.hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
	end
end

--[[
inherited from common document interface render reflowed page into cache in
background thread. this method returns immediatly leaving the precache flag on
in context. subsequent usage of this context should wait for the precache flag
off by calling self:waitForContext(kctx)
--]]
function KoptInterface:hintReflowedPage(doc, pageno, zoom, rotation, gamma, render_mode)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	if not cached then
		local kc = self:createContext(doc, pageno, bbox)
		local page = doc._document:openPage(pageno)
		DEBUG("hinting page", pageno, "in background")
		-- reflow will return immediately and running in background thread
		kc:setPreCache()
		page:reflow(kc, 0)
		page:close()
		Cache:insert(kctx_hash, ContextCacheItem:new{
			size = self.last_context_size or self.default_context_size,
			kctx = kc,
		})
	end
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	if doc.configurable.text_wrap == 1 then
		self:drawReflowedPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	else
		Document.drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	end
end

--[[
inherited from common document interface
draw cached tile pixels into target blitbuffer.
--]]
function KoptInterface:drawReflowedPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	--DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y,
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end

--[[
extract text boxes in a PDF/Djvu page
returned boxes are in native page coordinates zoomed at 1.0
--]]
function KoptInterface:getTextBoxes(doc, pageno)
	local text = doc:getPageTextBoxes(pageno)
	if text and #text > 1 then
		return text
	-- if we have no text in original page then we will reuse native word boxes
	-- in reflow mode and find text boxes from scratch in non-reflow mode
	else
		if doc.configurable.text_wrap == 1 then
			return self:getNativeTextBoxes(doc, pageno)
			--return self:getTextBoxesFromScratch(doc, pageno)
		else
			return self:getTextBoxesFromScratch(doc, pageno)
		end
	end
end

--[[
get text boxes in reflowed page via rectmaps in koptcontext
--]]
function KoptInterface:getReflowedTextBoxes(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "rfpgboxes|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local kctx_hash = "kctx|"..context_hash
		local cached = Cache:check(kctx_hash)
		if cached then
			local kc = self:waitForContext(cached.kctx)
			--kc:setDebug()
			local fullwidth, fullheight = kc:getPageDim()
			local boxes = kc:getReflowedWordBoxes(0, 0, fullwidth, fullheight)
			Cache:insert(hash, CacheItem:new{ rfpgboxes = boxes })
			return boxes
		end
	else
		return cached.rfpgboxes
	end
end

--[[
get text boxes in native page via rectmaps in koptcontext
--]]
function KoptInterface:getNativeTextBoxes(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "nativepgboxes|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local kctx_hash = "kctx|"..context_hash
		local cached = Cache:check(kctx_hash)
		if cached then
			local kc = self:waitForContext(cached.kctx)
			--kc:setDebug()
			local fullwidth, fullheight = kc:getPageDim()
			local boxes = kc:getNativeWordBoxes(0, 0, fullwidth, fullheight)
			Cache:insert(hash, CacheItem:new{ nativepgboxes = boxes })
			return boxes
		end
	else
		return cached.nativepgboxes
	end
end

--[[
get text boxes in native page via optical method, 
i.e. OCR pre-processing in Tesseract and Leptonica.
--]]
function KoptInterface:getTextBoxesFromScratch(doc, pageno)
	local hash = "pgboxes|"..doc.file.."|"..pageno
	local cached = Cache:check(hash)
	if not cached then
		local page_size = Document.getNativePageDimensions(doc, pageno)
		local bbox = {
			x0 = 0, y0 = 0,
			x1 = page_size.w,
			y1 = page_size.h,
		}
		local kc = self:createContext(doc, pageno, bbox)
		kc:setZoom(1.0)
		local page = doc._document:openPage(pageno)
		page:getPagePix(kc)
		local boxes = kc:getNativeWordBoxes(0, 0, page_size.w, page_size.h)
		Cache:insert(hash, CacheItem:new{ pgboxes = boxes })
		page:close()
		kc:free()
		return boxes
	else
		return cached.pgboxes
	end
end

--[[
OCR word inside the rect area of the page
rect should be in native page coordinates
--]]
function KoptInterface:getOCRWord(doc, pageno, rect)
	local ocrengine = "ocrengine"
	if not Cache:check(ocrengine) then
		local dummy = KOPTContext.new()
		Cache:insert(ocrengine, OCREngine:new{ ocrengine = dummy })
	end
	self.ocr_lang = doc.configurable.doc_language
	local hash = "ocrword|"..doc.file.."|"..pageno..rect.x..rect.y..rect.w..rect.h
	local cached = Cache:check(hash)
	if not cached then
		local bbox = {
			x0 = rect.x,
			y0 = rect.y,
			x1 = rect.x + rect.w,
			y1 = rect.y + rect.h,
		}
		local kc = self:createContext(doc, pageno, bbox)
		--kc:setZoom(30/rect.h)
		kc:setZoom(1.0)
		local page = doc._document:openPage(pageno)
		page:getPagePix(kc)
		local word_w, word_h = kc:getPageDim()
		local ok, word = pcall(
			kc.getTOCRWord, kc,
			0, 0, word_w, word_h,
			self.tessocr_data, self.ocr_lang, self.ocr_type, 0, 1)
		Cache:insert(hash, CacheItem:new{ ocrword = word })
		page:close()
		kc:free()
		return word
	else
		return cached.ocrword
	end
end

--[[
get index of nearest word box around pos
--]]
local function getWordBoxIndices(boxes, pos)
	local function inside_box(box)
		local x, y = pos.x, pos.y
		if box.x0 <= x and box.y0 <= y and box.x1 >= x and box.y1 >= y then
			return true
		end
		return false
	end
	local function box_distance(i, j)
		local wb = boxes[i][j]
		if inside_box(wb) then
			return 0
		else
			local x0, y0 = pos.x, pos.y
			local x1, y1 = (wb.x0 + wb.x1) / 2, (wb.y0 + wb.y1) / 2
			return (x0 - x1)*(x0 - x1) + (y0 - y1)*(y0 - y1)
		end
	end

	local m, n = 1, 1
	for i = 1, #boxes do
		for j = 1, #boxes[i] do
			if box_distance(i, j) < box_distance(m, n) then
				m, n = i, j
			end
		end
	end
	return m, n
end

--[[
get word and word box around pos
--]]
function KoptInterface:getWordFromBoxes(boxes, pos)
	local i, j = getWordBoxIndices(boxes, pos)
	local lb = boxes[i]
	local wb = boxes[i][j]
	if lb and wb then
		local box = Geom:new{
			x = wb.x0, y = lb.y0, 
			w = wb.x1 - wb.x0,
			h = lb.y1 - lb.y0,
		}
		return {
			word = wb.word,
			box = box,
		}
	end
end

--[[
get text and text boxes between pos0 and pos1
--]]
function KoptInterface:getTextFromBoxes(boxes, pos0, pos1)
    local line_text = ""
    local line_boxes = {}
    local i_start, j_start = getWordBoxIndices(boxes, pos0)
    local i_stop, j_stop = getWordBoxIndices(boxes, pos1)
    if i_start == i_stop and j_start > j_stop or i_start > i_stop then
    	i_start, i_stop = i_stop, i_start
    	j_start, j_stop = j_stop, j_start
    end
    for i = i_start, i_stop do
    	if i_start == i_stop and #boxes[i] == 0 then break end
    	-- insert line words
    	local j0 = i > i_start and 1 or j_start
    	local j1 = i < i_stop and #boxes[i] or j_stop
    	for j = j0, j1 do
    		local word = boxes[i][j].word
    		if word then
    			-- if last character of this word is an ascii char then append a space
    			local space = (word:match("[%z\194-\244][\128-\191]*$") or j == j1)
    						   and "" or " "
    			line_text = line_text..word..space
    		end
    	end
    	-- insert line box
    	local lb = boxes[i]
    	if i > i_start and i < i_stop then
    		local line_box = Geom:new{
				x = lb.x0, y = lb.y0, 
				w = lb.x1 - lb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i == i_start and i < i_stop then
    		local wb = boxes[i][j_start]
    		local line_box = Geom:new{
				x = wb.x0, y = lb.y0, 
				w = lb.x1 - wb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i > i_start and i == i_stop then
    		local wb = boxes[i][j_stop]
    		local line_box = Geom:new{
				x = lb.x0, y = lb.y0, 
				w = wb.x1 - lb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i == i_start and i == i_stop then
    		local wb_start = boxes[i][j_start]
    		local wb_stop = boxes[i][j_stop]
    		local line_box = Geom:new{
				x = wb_start.x0, y = lb.y0, 
				w = wb_stop.x1 - wb_start.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	end
    end
    return {
    	text = line_text,
    	boxes = line_boxes,
    }
end

--[[
get word and word box from doc position
]]--
function KoptInterface:getWordFromPosition(doc, pos)
	local text_boxes = self:getTextBoxes(doc, pos.page)
	if text_boxes then
		if doc.configurable.text_wrap == 1 then
			return self:getWordFromReflowPosition(doc, text_boxes, pos)
		else
			return self:getWordFromNativePosition(doc, text_boxes, pos)
		end
	end
end

--[[
get word and word box from position in reflowed page
]]--
function KoptInterface:getWordFromReflowPosition(doc, boxes, pos)
	local pageno = pos.page
	local reflowed_page_boxes = self:getReflowedTextBoxes(doc, pageno)
	local reflowed_word_box = self:getWordFromBoxes(reflowed_page_boxes, pos)
	local reflowed_pos = reflowed_word_box.box:center()
	local native_pos = self:reflowToNativePosTransform(doc, pageno, reflowed_pos)
	local native_word_box = self:getWordFromBoxes(boxes, native_pos)
	local word_box = {
		word = native_word_box.word,
		pbox = native_word_box.box,   -- box on page
		sbox = reflowed_word_box.box, -- box on screen
		pos = native_pos,
	}
	return word_box
end

--[[
get word and word box from position in native page
]]--
function KoptInterface:getWordFromNativePosition(doc, boxes, pos)
	local native_word_box = self:getWordFromBoxes(boxes, pos)
	local word_box = {
		word = native_word_box.word,
		pbox = native_word_box.box,   -- box on page
		sbox = native_word_box.box,   -- box on screen
		pos = pos,
	}
	return word_box
end

--[[
transform position in native page to reflowed page
]]--
function KoptInterface:nativeToReflowPosTransform(doc, pageno, pos)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	local kc = self:waitForContext(cached.kctx)
	--kc:setDebug()
	--DEBUG("transform native pos", pos)
	local rpos = {}
	rpos.x, rpos.y = kc:nativeToReflowPosTransform(pos.x, pos.y)
	--DEBUG("transformed reflowed pos", rpos)
	return rpos
end

--[[
transform position in reflowed page to native page
]]--
function KoptInterface:reflowToNativePosTransform(doc, pageno, pos)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	local kc = self:waitForContext(cached.kctx)
	--kc:setDebug()
	--DEBUG("transform reflowed pos", pos)
	local npos = {}
	npos.x, npos.y = kc:reflowToNativePosTransform(pos.x, pos.y)
	--DEBUG("transformed native pos", npos)
	return npos
end

--[[
get text and text boxes from screen positions
--]]
function KoptInterface:getTextFromPositions(doc, pos0, pos1)
	local text_boxes = self:getTextBoxes(doc, pos0.page)
	if text_boxes then
		if doc.configurable.text_wrap == 1 then
			return self:getTextFromReflowPositions(doc, text_boxes, pos0, pos1)
		else
			return self:getTextFromNativePositions(doc, text_boxes, pos0, pos1)
		end
	end
end

--[[
get text and text boxes from screen positions for reflowed page
]]--
function KoptInterface:getTextFromReflowPositions(doc, native_boxes, pos0, pos1)
	local pageno = pos0.page
	local reflowed_page_boxes = self:getReflowedTextBoxes(doc, pageno)
	local reflowed_box0 = self:getWordFromBoxes(reflowed_page_boxes, pos0)
	local reflowed_pos0 = reflowed_box0.box:center()
	local native_pos0 = self:reflowToNativePosTransform(doc, pageno, reflowed_pos0)
	
	local reflowed_box1 = self:getWordFromBoxes(reflowed_page_boxes, pos1)
	local reflowed_pos1 = reflowed_box1.box:center()
	local native_pos1 = self:reflowToNativePosTransform(doc, pageno, reflowed_pos1)
	
	local reflowed_text_boxes = self:getTextFromBoxes(reflowed_page_boxes, pos0, pos1)
	local native_text_boxes = self:getTextFromBoxes(native_boxes, pos0, pos1)
	local text_boxes = {
		text = native_text_boxes.text,
		pboxes = native_text_boxes.boxes,   -- boxes on page
		sboxes = reflowed_text_boxes.boxes, -- boxes on screen
		pos0 = native_pos0,
		pos1 = native_pos1
	}
	return text_boxes
end

--[[
get text and text boxes from screen positions for native page
]]--
function KoptInterface:getTextFromNativePositions(doc, native_boxes, pos0, pos1)
	local native_text_boxes = self:getTextFromBoxes(native_boxes, pos0, pos1)
	local text_boxes = {
		word = native_text_boxes.text,
		pboxes = native_text_boxes.boxes,   -- boxes on page
		sboxes = native_text_boxes.boxes,   -- boxes on screen
		pos0 = pos0,
		pos1 = pos1,
	}
	return text_boxes
end

--[[
get text boxes from page positions
--]]
function KoptInterface:getPageBoxesFromPositions(doc, pageno, ppos0, ppos1)
	if not ppos0 or not ppos1 then return end
	if doc.configurable.text_wrap == 1 then
		local spos0 = self:nativeToReflowPosTransform(doc, pageno, ppos0)
		local spos1 = self:nativeToReflowPosTransform(doc, pageno, ppos1)
		local page_boxes = self:getReflowedTextBoxes(doc, pageno)
		local text_boxes = self:getTextFromBoxes(page_boxes, spos0, spos1)
		return text_boxes.boxes
	else
		local page_boxes = self:getTextBoxes(doc, pageno)
		local text_boxes = self:getTextFromBoxes(page_boxes, ppos0, ppos1)
		return text_boxes.boxes
	end
end

--[[
helper functions
--]]
function KoptInterface:logReflowDuration(pageno, dur)
	local file = io.open("reflow_dur_log.txt", "a+")
	if file then
		if file:seek("end") == 0 then -- write the header only once
			file:write("PAGE\tDUR\n")
		end
		file:write(string.format("%s\t%s\n", pageno, dur))
		file:close()
	end
end

function KoptInterface:logMemoryUsage(pageno)
	local status_file = io.open("/proc/self/status", "r")
	local log_file = io.open("reflow_mem_log.txt", "a+")
	local data = -1
	if status_file then
		for line in status_file:lines() do
			local s, n
			s, n = line:gsub("VmData:%s-(%d+) kB", "%1")
			if n ~= 0 then data = tonumber(s) end
			if data ~= -1 then break end
		end
		status_file:close()
	end
	if log_file then
		if log_file:seek("end") == 0 then -- write the header only once
			log_file:write("PAGE\tMEM\n")
		end
		log_file:write(string.format("%s\t%s\n", pageno, data))
		log_file:close()
	end
end
