require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/device"
require "ui/reader/readerconfig"

KoptInterface = {}

-- get reflow context
function KoptInterface:getKOPTContext(doc, pageno)
	local kc = KOPTContext.new()
	kc:setTrim(doc.configurable.trim_page)
	kc:setWrap(doc.configurable.text_wrap)
	kc:setIndent(doc.configurable.detect_indent)
	kc:setRotate(doc.configurable.screen_rotation)
	kc:setColumns(doc.configurable.max_columns)
	kc:setDeviceDim(doc.screen_size.w, doc.screen_size.h)
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
	local bbox = doc:getUsedBBox(pageno)
	kc:setBBox(bbox.x0, bbox.y0, bbox.x1, bbox.y1)
	return kc
end

-- calculates page dimensions
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
	-- check cached page size
	local hash = "kctx|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
	local cached = Cache:check(hash)
	if not cached then
		local kc = self:getKOPTContext(doc, pageno)
		local page = doc._document:openPage(pageno)
		-- reflow page
		page:reflow(kc, 0)
		page:close()
		local fullwidth, fullheight = kc:getPageDim()
		DEBUG("page::reflowPage:", "fullwidth:", fullwidth, "fullheight:", fullheight)
		local page_size = Geom:new{ w = fullwidth, h = fullheight }
		-- cache reflowed page size and kc
		Cache:insert(hash, CacheItem:new{ kctx = kc })
		return page_size
	end
	--DEBUG("Found cached koptcontex on page", pageno, cached)
	local fullwidth, fullheight = cached.kctx:getPageDim()
	local page_size = Geom:new{ w = fullwidth, h = fullheight }
	return page_size
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	doc.render_mode = render_mode
	local hash = "renderpg|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
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
		hash = "renderpg|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|').."|"..tostring(rect)
		size = rect
	end
	
	local cached = Cache:check(hash)
	if cached then return cached end

	-- prepare cache item with contained blitbuffer	
	local tile = CacheItem:new{
		size = size.w * size.h / 2 + 64, -- estimation
		excerpt = size,
		pageno = pageno,
		bb = Blitbuffer.new(size.w, size.h)
	}

	-- draw to blitbuffer
	local kc_hash = "kctx|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
	local page = doc._document:openPage(pageno)
	local cached = Cache:check(kc_hash)
	if cached then
		page:rfdraw(cached.kctx, tile.bb)
		page:close()
		DEBUG("cached hash", hash)
		if not Cache:check(hash) then
			Cache:insert(hash, tile)
		end
		return tile
	end
	DEBUG("Error: cannot render page before reflowing.")
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y, 
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end
