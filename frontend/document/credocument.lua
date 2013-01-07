require "ui/geometry"
require "ui/creoptions"

CreDocument = Document:new{
	-- this is defined in kpvcrlib/crengine/crengine/include/lvdocview.h
	SCROLL_VIEW_MODE = 0,
	PAGE_VIEW_MODE = 1,

	_document = false,
	engine_initilized = false,

	line_space_percent = 100,
	default_font = "Droid Sans Fallback",
	options = CreOptions,
	configurable = Configurable,
}

-- NuPogodi, 20.05.12: inspect the zipfile content
function CreDocument:zipContentExt(fname)
	local outfile = "./data/zip_content"
	local s = ""
	os.execute("unzip ".."-l \""..fname.."\" > "..outfile)
	local i = 1
	if io.open(outfile,"r") then
		for lines in io.lines(outfile) do
			if i == 4 then s = lines break else i = i + 1 end
		end
	end
	-- return the extention
	return string.lower(string.match(s, ".+%.([^.]+)"))
end

function CreDocument:engineInit()
	if not engine_initilized then
		-- initialize cache
		cre.initCache(1024*1024*64)
		
		-- we need to initialize the CRE font list
		local fonts = Font:getFontList()
		for _k, _v in ipairs(fonts) do
			if _v ~= "Dingbats.cff" and _v ~= "StandardSymL.cff" then
				local ok, err = pcall(cre.registerFont, Font.fontdir..'/'.._v)
				if not ok then
					DEBUG(err)
				end
			end
		end

		local default_font = G_reader_settings:readSetting("cre_font")
		if default_font then
			self.default_font = default_font
		end

		engine_initilized = true
	end
end

function CreDocument:init()
	self:engineInit()
	self.configurable:loadDefaults(self.options)

	local ok
	local file_type = string.lower(string.match(self.file, ".+%.([^.]+)"))
	if file_type == "zip" then
		-- NuPogodi, 20.05.12: read the content of zip-file
		-- and return extention of the 1st file
		file_type = self:zipContentExt(filename)
	end
	-- these two format use the same css file
	if file_type == "html" then
		file_type = "htm"
	end
	-- if native css-file doesn't exist, one needs to use default cr3.css
	if not io.open("./data/"..file_type..".css") then
		file_type = "cr3"
	end
	local style_sheet = "./data/"..file_type..".css"

	-- @TODO check the default view_mode to a global user configurable
	-- variable  22.12 2012 (houqp)
	ok, self._document = pcall(cre.openDocument, self.file, style_sheet,
				Screen:getWidth(), Screen:getHeight(), self.PAGE_VIEW_MODE)
	if not ok then
		self.error_message = self.doc -- will contain error message
		return
	end
	self.is_open = true
	self.info.has_pages = false
	self:_readMetadata()
	self.info.configurable = true

	-- @TODO read line_space_percent from setting file  12.06 2012 (houqp)
	--self._document:setDefaultInterlineSpace(self.line_space_percent)
end

function CreDocument:drawCurrentView(target, x, y, rect, pos)
	tile_bb = Blitbuffer.new(rect.w, rect.h)
	self._document:drawCurrentPage(tile_bb)
	target:blitFrom(tile_bb, x, y, 0, 0, rect.w, rect.h)
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
	self._document:gotoXPointer(xpointer)
end

function CreDocument:getXPointer()
	return self._document:getXPointer()
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

function Document:gotoPos(pos)
	self._document:gotoPos(pos)
end

function CreDocument:gotoPage(page)
	self._document:gotoPage(page)
end

function CreDocument:getCurrentPage()
	return self._document:getCurrentPage()
end

function CreDocument:setFontFace(new_font_face)
	if new_font_face then
		self._document:setFontFace(new_font_face)
	end
end

function CreDocument:getFontSize()
	return self._document:getFontSize()
end

function CreDocument:setFontSize(new_font_size)
	if new_font_size then
		self._document:setFontSize(new_font_size)
	end
end

function CreDocument:zoomFont(delta)
	self._document:zoomFont(delta)
end

function CreDocument:setInterlineSpacePercent(percent)
	self._document:setDefaultInterlineSpace(percent)
end

DocumentRegistry:addProvider("txt", "application/txt", CreDocument)
DocumentRegistry:addProvider("epub", "application/epub", CreDocument)
DocumentRegistry:addProvider("html", "application/html", CreDocument)
DocumentRegistry:addProvider("htm", "application/htm", CreDocument)
DocumentRegistry:addProvider("zip", "application/zip", CreDocument)
DocumentRegistry:addProvider("rtf", "application/rtf", CreDocument)
DocumentRegistry:addProvider("mobi", "application/mobi", CreDocument)
DocumentRegistry:addProvider("prc", "application/prc", CreDocument)
DocumentRegistry:addProvider("azw", "application/azw", CreDocument)
DocumentRegistry:addProvider("chm", "application/chm", CreDocument)
DocumentRegistry:addProvider("pdb", "application/pdb", CreDocument)
DocumentRegistry:addProvider("doc", "application/doc", CreDocument)
DocumentRegistry:addProvider("tcr", "application/tcr", CreDocument)
