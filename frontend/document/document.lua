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
	local extension = string.lower(string.match(file, ".+%.([^.]+)"))
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
		length = 0,

		-- other metadata
		title = "",
		author = "",
		date = ""
	},

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
	if self.info.has_pages then
		self.info.number_of_pages = self._document:getPages()
	else
		self.info.length = self._document:getFullHeight()
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

function Document:getToc()
	return self._document:getToc()
end

function Document:renderPage(pageno, rect, zoom, rotation)
	local hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation
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
		hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..tostring(rect)
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
	page:draw(dc, tile.bb, size.x, size.y)
	page:close()
	Cache:insert(hash, tile)

	return tile
end

-- a hint for the cache engine to paint a full page to the cache
-- TODO: this should trigger a background operation
function Document:hintPage(pageno, zoom, rotation)
	self:renderPage(pageno, nil, zoom, rotation)
end

function Document:drawPage(target, x, y, rect, pageno, zoom, rotation)
	local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation
	local hash_excerpt = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..tostring(rect)
	local tile = Cache:check(hash_full_page)
	if not tile then
		tile = Cache:check(hash_excerpt)
		if not tile then
			DEBUG("rendering")
			tile = self:renderPage(pageno, rect, zoom, rotation)
		end
	end
	DEBUG("now painting", tile)
	target:blitFrom(tile.bb, x, y, rect.x - tile.excerpt.x, rect.y - tile.excerpt.y, rect.w, rect.h)
end

function Document:drawCurrentView(target, x, y, rect, pos)
	self._document:gotoPos(pos)
	tile_bb = Blitbuffer.new(rect.w, rect.h)
	self._document:drawCurrentView(tile_bb)
	target:blitFrom(tile_bb, x, y, 0, 0, rect.w, rect.h)
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
