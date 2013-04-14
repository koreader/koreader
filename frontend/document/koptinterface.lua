require "cache"
require "ui/geometry"
require "ui/device"
require "ui/reader/readerconfig"

KoptInterface = {
	bg_context = {
		contex = nil,
		pageno = nil,
		hash = nil,
		cached = false,
	},
}

function KoptInterface:waitForContext(kc)
	-- if koptcontext is being processed in background thread
	-- the isPreCache will return 1.
	while kc and kc:isPreCache() == 1 do
		DEBUG("waiting for background rendering")
		util.usleep(100000)
	end
end

function KoptInterface:consumeBgContext(doc)
	-- clear up background context
	self:waitForContext(self.bg_context.context)
	if self.bg_context.context and not self.bg_context.cached then
		self:makeCache(doc, self.bg_context.pageno, self.bg_context.hash)
		self.bg_context.cached = true
	end
end

-- get reflow context
function KoptInterface:getKOPTContext(doc, pageno, bbox)
	-- since libk2pdfopt only has one bitmap buffer that holds reflowed page
	-- we should consume background production before allocating new context.
	self:consumeBgContext(doc)
	local kc = KOPTContext.new()
	local screen_size = Screen:getSize()
	kc:setTrim(doc.configurable.trim_page)
	kc:setWrap(doc.configurable.text_wrap)
	kc:setIndent(doc.configurable.detect_indent)
	kc:setRotate(doc.configurable.screen_rotation)
	kc:setColumns(doc.configurable.max_columns)
	kc:setDeviceDim(screen_size.w, screen_size.h)
	kc:setDeviceDPI(doc.screen_dpi)
	kc:setStraighten(doc.configurable.auto_straighten)
	kc:setJustification(doc.configurable.justification)
	kc:setZoom(doc.configurable.font_size)
	kc:setMargin(doc.configurable.page_margin)
	kc:setQuality(doc.configurable.quality)
	kc:setContrast(doc.configurable.contrast)
	kc:setDefectSize(doc.configurable.defect_size)
	kc:setLineSpacing(doc.configurable.line_spacing)
	kc:setWordSpacing(doc.configurable.word_spacing)
	kc:setBBox(bbox.x0, bbox.y0, bbox.x1, bbox.y1)
	return kc
end

function KoptInterface:setTrimPage(doc, pageno)
	if doc.configurable.trim_page == 0 then return end
	local page_dimens = doc:getNativePageDimensions(pageno)
	--DEBUG("original page dimens", page_dimens)
	local orig_bbox = doc:getUsedBBox(pageno)
	--DEBUG("original bbox", orig_bbox)
	if orig_bbox.x1 - orig_bbox.x0 < page_dimens.w
		or orig_bbox.y1 - orig_bbox.y0 < page_dimens.h then
		doc.configurable.trim_page = 0
		--DEBUG("Set manual crop in koptengine")
	end
end

function KoptInterface:getContextHash(doc, pageno, bbox)
	local screen_size = Screen:getSize()
	local screen_size_hash = screen_size.w.."|"..screen_size.h
	local bbox_hash = bbox.x0.."|"..bbox.y0.."|"..bbox.x1.."|"..bbox.y1
	return doc.file.."|"..pageno.."|"..doc.configurable:hash("|").."|"..bbox_hash.."|"..screen_size_hash
end

function KoptInterface:logReflowDuration(pageno, dur)
	local file = io.open("reflowlog.txt", "a+")
	if file then
		if file:seek("end") == 0 then -- write the header only once
			file:write("PAGE\tDUR\n")
		end
		file:write(string.format("%s\t%s\n", pageno, dur))
		file:close()
	end
end

function KoptInterface:getAutoBBox(doc, pageno)
	local bbox = {
		x0 = 0, y0 = 0,
		x1 = 0, y1 = 0,
	}
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "autobbox|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local page = doc._document:openPage(pageno)
		local kc = self:getKOPTContext(doc, pageno, bbox)
		bbox.x0, bbox.y0, bbox.x1, bbox.y1 = page:getAutoBBox(kc)
		DEBUG("Auto detected bbox", bbox)
		page:close()
		Cache:insert(hash, CacheItem:new{ bbox = bbox })
		return bbox
	else
		return cached.bbox
	end
end

function KoptInterface:getReflowedDim(kc)
	self:waitForContext(kc)
	return kc:getPageDim()
end

-- calculates page dimensions
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
	self:setTrimPage(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "kctx|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local kc = self:getKOPTContext(doc, pageno, bbox)
		local page = doc._document:openPage(pageno)
		-- reflow page
		--local secs, usecs = util.gettime()
		page:reflow(kc, 0)
		--local nsecs, nusecs = util.gettime()
		--local dur = nsecs - secs + (nusecs - usecs) / 1000000
		--DEBUG("Reflow duration:", dur)
		--self:logReflowDuration(pageno, dur)
		page:close()
		local fullwidth, fullheight = kc:getPageDim()
		DEBUG("page::reflowPage:", "fullwidth:", fullwidth, "fullheight:", fullheight)
		local page_size = Geom:new{ w = fullwidth, h = fullheight }
		-- cache reflowed page size and kc
		Cache:insert(hash, CacheItem:new{ kctx = kc })
		return page_size
	end
	--DEBUG("Found cached koptcontex on page", pageno, cached)
	local fullwidth, fullheight = self:getReflowedDim(cached.kctx)
	local page_size = Geom:new{ w = fullwidth, h = fullheight }
	return page_size
end

function KoptInterface:makeCache(doc, pageno, context_hash)
	-- draw to blitbuffer
	local kc_hash = "kctx|"..context_hash
	local tile_hash = "renderpg|"..context_hash
	local page = doc._document:openPage(pageno)
	local cached = Cache:check(kc_hash)
	if cached then
		local fullwidth, fullheight = self:getReflowedDim(cached.kctx)
		-- prepare cache item with contained blitbuffer
		local tile = CacheItem:new{
			size = fullwidth * fullheight / 2 + 64, -- estimation
			excerpt = Geom:new{ w = fullwidth, h = fullheight },
			pageno = pageno,
			bb = Blitbuffer.new(fullwidth, fullheight)
		}
		page:rfdraw(cached.kctx, tile.bb)
		page:close()
		--DEBUG("cached hash", hash)
		if not Cache:check(tile_hash) then
			Cache:insert(tile_hash, tile)
		end
		return tile
	end
	DEBUG("Error: cannot render page before reflowing.")
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	self:setTrimPage(doc, pageno)
	doc.render_mode = render_mode
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "renderpg|"..context_hash
	local page_size = self:getPageDimensions(doc, pageno, zoom, rotation)
	-- this will be the size we actually render
	local size = page_size
	-- we prefer to render the full page, if it fits into cache
	if not Cache:willAccept(size.w * size.h / 2) then
		-- whole page won't fit into cache
		DEBUG("rendering only part of the page")
		-- TODO: figure out how to better segment the page
		if not rect then
			DEBUG("aborting, since we do not have a specification for that part")
			-- required part not given, so abort
			return
		end
		-- only render required part
		hash = "renderpg|"..doc.file.."|"..pageno.."|"..doc.configurable:hash("|").."|"..tostring(rect)
		size = rect
	end

	local cached = Cache:check(hash)
	if cached then
		return cached
	else
		return self:makeCache(doc, pageno, context_hash)
	end
end

function KoptInterface:hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
	self:setTrimPage(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local hash = "kctx|"..context_hash
	local cached = Cache:check(hash)
	if not cached then
		local kc = self:getKOPTContext(doc, pageno, bbox)
		local page = doc._document:openPage(pageno)
		kc:setPreCache()
		self.bg_context.context = kc
		self.bg_context.pageno = pageno
		self.bg_context.hash = context_hash
		self.bg_context.cached = false
		DEBUG("hinting page", pageno, "in background")
		-- will return immediately
		page:reflow(kc, 0)
		page:close()
		Cache:insert(hash, CacheItem:new{ kctx = kc })
	end
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	--DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y,
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end
