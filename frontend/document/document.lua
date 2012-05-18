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
			return provider.provider:new{file = file}
		end
	end
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
end

-- this might be overridden by a document implementation
function Document:getNativePageDimensions(pageno)
	return Geom:new{w=0, h=0}
end

-- calculates page dimensions
function Document:getPageDimensions(pageno, zoom, rotation)
	local native_dimen = Geom:copy(self:getNativePageDimensions(pageno))
	if rotation == 90 or rotation == 270 then
		-- switch orientation
		native_dimen.w, native_dimen.h = native_dimen.h, native_dimen.w
	end
	native_dimen:scaleBy(zoom)
	debug("dimen for pageno", pageno, "zoom", zoom, "rotation", rotation, "is", native_dimen)
	return native_dimen
end

-- load implementations:

require "document/pdfdocument"
