require "cache"
require "ui/geometry"
require "ui/device"
require "ui/reader/readerconfig"

KoptInterface = {}

function KoptInterface:waitForContext(kc)
	-- if koptcontext is being processed in background thread
	-- the isPreCache will return 1.
	while kc and kc:isPreCache() == 1 do
		DEBUG("waiting for background rendering")
		util.usleep(100000)
	end
end

-- get reflow context
function KoptInterface:getKOPTContext(doc, pageno, bbox)
	-- Now koptcontext keeps track of its dst bitmap reflowed by libk2pdfopt.
	-- So there is no need to check background context when creating new context.
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

-- get reflowed page dimension from a cached context. wait for background thread
-- if necessary.
function KoptInterface:getReflowedDim(kctx)
	self:waitForContext(kctx)
	return kctx:getPageDim()
end

-- get cached koptcontext for centain page. if context doesn't exist in cache make
-- new context and reflow the src page immediatly.
function KoptInterface:getCachedContext(doc, pageno)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	if not cached then
		-- If kctx is not cached, create one and get reflowed bmp in foreground.
		local kc = self:getKOPTContext(doc, pageno, bbox)
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
		Cache:insert(kctx_hash, CacheItem:new{ kctx = kc })
		return kc
	else
		return cached.kctx
	end
end

-- get reflowed page dimensions
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
	local kctx = self:getCachedContext(doc, pageno)
	local fullwidth, fullheight = self:getReflowedDim(kctx)
	return Geom:new{ w = fullwidth, h = fullheight }
end

-- inherited from common document interface
-- render reflowed page into tile cache. 
function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	doc.render_mode = render_mode
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local renderpg_hash = "renderpg|"..context_hash

	local cached = Cache:check(renderpg_hash)
	if not cached then
		-- do the real reflowing if kctx is not been cached yet
		local kctx = self:getCachedContext(doc, pageno)
		local fullwidth, fullheight = self:getReflowedDim(kctx)
		if not Cache:willAccept(fullwidth * fullheight / 2) then
			-- whole page won't fit into cache
			error("aborting, since we don't have enough cache for this page")
		end
		local page = doc._document:openPage(pageno)
		-- prepare cache item with contained blitbuffer
		local tile = CacheItem:new{
			size = fullwidth * fullheight / 2 + 64, -- estimation
			excerpt = Geom:new{ w = fullwidth, h = fullheight },
			pageno = pageno,
			bb = Blitbuffer.new(fullwidth, fullheight)
		}
		page:rfdraw(kctx, tile.bb)
		page:close()
		-- free dst bitmap in kctx as soon as we draw the bitmap to blitbuffer
		kctx:free()
		Cache:insert(renderpg_hash, tile)
		return tile
	else
		return cached
	end
end

-- inherited from common document interface
-- render reflowed page into cache in background thread. this method returns immediatly
-- leaving the precache flag on in context. subsequent usage of this context should 
-- wait for the precache flag off by calling self:waitForContext(kctx)
function KoptInterface:hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
	local bbox = doc:getPageBBox(pageno)
	local context_hash = self:getContextHash(doc, pageno, bbox)
	local kctx_hash = "kctx|"..context_hash
	local cached = Cache:check(kctx_hash)
	if not cached then
		local kc = self:getKOPTContext(doc, pageno, bbox)
		local page = doc._document:openPage(pageno)
		DEBUG("hinting page", pageno, "in background")
		-- reflow will return immediately and running in background thread
		kc:setPreCache()
		page:reflow(kc, 0)
		page:close()
		Cache:insert(kctx_hash, CacheItem:new{ kctx = kc })
	end
end

-- inherited from common document interface
-- draw cached tile pixels into target blitbuffer
function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	--DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y,
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end
