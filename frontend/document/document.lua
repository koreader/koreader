require "../math"

--[[
This is a registry for document providers
]]--
DocumentRegistry = {
	providers = { }
}

function DocumentRegistry:addProvider(extension, mimetype, provider)
	table.insert(self.providers, { extension = extension, mimetype = mimetype, provider = provider })
end

function DocumentRegistry:getProvider(file)
	-- TODO: some implementation based on mime types?
	local extension = string.lower(string.match(file, ".+%.([^.]+)") or "")
	for _, provider in ipairs(self.providers) do
		if extension == provider.extension then
			return provider.provider
		end
	end
end

function DocumentRegistry:openDocument(file)
	return self:getProvider(file):new{file = file}
end


--[[
This is an abstract interface to a document
]]--
Document = {
	-- file name
	file = nil,

	info = {
		-- whether the document is pageable
		has_pages = false,
		-- whether words can be provided
		has_words = false,
		-- whether hyperlinks can be provided
		has_hyperlinks = false,
		-- whether (native to format) annotations can be provided
		has_annotations = false,

		-- whether pages can be rotated
		is_rotatable = false,

		number_of_pages = 0,
		-- if not pageable, length of the document in pixels
		doc_height = 0,
		
		-- other metadata
		title = "",
		author = "",
		date = ""
	},
	
	-- override bbox from orignal page's getUsedBBox
	bbox = {},
		
	-- flag to show whether the document was opened successfully
	is_open = false,
	error_message = nil,

	-- flag to show that the document needs to be unlocked by a password
	is_locked = false,
}

function Document:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	if o.init then o:init() end
	return o
end

-- override this method to open a document
function Document:init()
end

-- this might be overridden by a document implementation
function Document:unlock(password)
	-- return true instead when the password provided unlocked the document
	return false
end

-- this might be overridden by a document implementation
function Document:close()
	if self.is_open then
		self.is_open = false
		self._document:close()
	end
end

-- this might be overridden by a document implementation
function Document:getNativePageDimensions(pageno)
	local hash = "pgdim|"..self.file.."|"..pageno
	local cached = Cache:check(hash)
	if cached then
		return cached[1]
	end
	local page = self._document:openPage(pageno)
	local page_size_w, page_size_h = page:getSize(self.dc_null)
	local page_size = Geom:new{ w = page_size_w, h = page_size_h }
	Cache:insert(hash, CacheItem:new{ page_size })
	page:close()
	return page_size
end

function Document:_readMetadata()
	self.info.number_of_pages = self._document:getPages()
	if not self.info.has_pages then
		self.info.doc_height = self._document:getFullHeight()
	end
	return true
end

-- calculates page dimensions
function Document:getPageDimensions(pageno, zoom, rotation)
	local native_dimen = self:getNativePageDimensions(pageno):copy()
	if rotation == 90 or rotation == 270 then
		-- switch orientation
		native_dimen.w, native_dimen.h = native_dimen.h, native_dimen.w
	end
	native_dimen:scaleBy(zoom)
	DEBUG("dimen for pageno", pageno, "zoom", zoom, "rotation", rotation, "is", native_dimen)
	return native_dimen
end

function Document:getPageBBox(pageno)
	local bbox = self.bbox[pageno] -- exact
	local oddEven = math.oddEven(pageno)
	if bbox ~= nil then
		DEBUG("bbox from", pageno)
	else
		bbox = self.bbox[oddEven] -- odd/even
	end
	if bbox ~= nil then -- last used up to this page
		DEBUG("bbox from", oddEven)
	else
		for i = 0,pageno do
			bbox = self.bbox[ pageno - i ]
			if bbox ~= nil then
				DEBUG("bbox from", pageno - i)
				break
			end
		end
	end
	if bbox == nil then -- fallback bbox
		bbox = self:getUsedBBox(pageno)
		DEBUG("bbox from ORIGINAL page")
	end
	DEBUG("final bbox", bbox)
	return bbox
end

--[[
This method returns pagesize if bbox is corrupted
--]]
function Document:getUsedBBoxDimensions(pageno, zoom, rotation)
	local bbox = self:getPageBBox(pageno)
	local ubbox_dimen = nil
	if bbox.x0 < 0 or bbox.y0 < 0 or bbox.x1 < 0 or bbox.y1 < 0 then
		-- if document's bbox info is corrupted, we use the page size
		ubbox_dimen = self:getPageDimensions(pageno, zoom, rotation)
	else
		ubbox_dimen = Geom:new{
			x = bbox.x0,
			y = bbox.y0,
			w = bbox.x1 - bbox.x0,
			h = bbox.y1 - bbox.y0,
		}
		if zoom ~= 1 then
			ubbox_dimen:transformByScale(zoom)
		end
	end
	return ubbox_dimen
end

function Document:getToc()
	return self._document:getToc()
end

function Document:renderPage(pageno, rect, zoom, rotation, render_mode)
	local hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..render_mode
	local page_size = self:getPageDimensions(pageno, zoom, rotation)
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
		hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..render_mode.."|"..tostring(rect)
		size = rect
	end

	-- prepare cache item with contained blitbuffer	
	local tile = CacheItem:new{
		size = size.w * size.h / 2 + 64, -- estimation
		excerpt = size,
		pageno = pageno,
		bb = Blitbuffer.new(size.w, size.h)
	}

	-- create a draw context
	local dc = DrawContext.new()

	dc:setRotate(rotation)
	-- correction of rotation
	if rotation == 90 then
		dc:setOffset(page_size.w, 0)
	elseif rotation == 180 then
		dc:setOffset(page_size.w, page_size.h)
	elseif rotation == 270 then
		dc:setOffset(0, page_size.h)
	end
	dc:setZoom(zoom)

	-- render
	local page = self._document:openPage(pageno)
	page:draw(dc, tile.bb, size.x, size.y, render_mode)
	page:close()
	Cache:insert(hash, tile)

	return tile
end

-- a hint for the cache engine to paint a full page to the cache
-- TODO: this should trigger a background operation
function Document:hintPage(pageno, zoom, rotation, render_mode)
	local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..render_mode
	if not Cache:check(hash_full_page) then
		self:renderPage(pageno, nil, zoom, rotation, render_mode)
	end
end

--[[
Draw page content to blitbuffer.
1. find tile in cache
2. if not found, call renderPage

@target: target blitbuffer
@rect: visible_area inside document page
--]]
function Document:drawPage(target, x, y, rect, pageno, zoom, rotation, render_mode)
	local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..render_mode
	local hash_excerpt = hash_full_page.."|"..tostring(rect)
	local tile = Cache:check(hash_full_page)
	if not tile then
		tile = Cache:check(hash_excerpt)
		if not tile then
			DEBUG("rendering")
			tile = self:renderPage(pageno, rect, zoom, rotation, render_mode)
		end
	end
	DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y, 
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end

function Document:getPageText(pageno)
	-- is this worth caching? not done yet.
	local page = self._document:openPage(pageno)
	local text = page:getPageText()
	page:close()
	return text
end


-- load implementations:

require "document/pdfdocument"
require "document/djvudocument"
require "document/credocument"
