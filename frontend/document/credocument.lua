require "ui/geometry"

CreOptions = {
	prefix = 'copt',
	{
		icon = "resources/icons/appbar.transform.rotate.right.large.png",
		options = {
			{
				name = "screen_mode",
				name_text = "Screen Mode",
				toggle = {"portrait", "landscape"},
				args = {"portrait", "landscape"},
				default_arg = "portrait",
				current_func = function() return Screen:getScreenMode() end,
				event = "SetScreenMode",
			}
		}
	},
	{
		icon = "resources/icons/appbar.column.two.large.png",
		options = {
			{
				name = "line_spacing",
				name_text = "Line Spacing",
				item_text = {"decrease", "increase"},
				args = {"decrease", "increase"},
				default_arg = nil,
				event = "ChangeLineSpace",
			},
		}
	},
	{
		icon = "resources/icons/appbar.text.size.large.png",
		options = {
			{
				name = "font_size",
				item_text = {"Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Aa"},
				item_align_center = 1.0,
				spacing = 15,
				item_font_size = {18, 20, 22, 24, 29, 33, 39, 44},
				values = {18, 20, 22, 24, 29, 33, 39, 44},
				default_value = 22,
				args = {18, 20, 22, 24, 29, 33, 39, 44},
				event = "SetFontSize",
			},
		}
	},
	{
		icon = "resources/icons/appbar.grade.b.large.png",
		options = {
			{
				name = "font_weight",
				name_text = "Font weight",
				item_text = {"toggle bolder"},
				-- args is indeed not used, we put here just to keep the
				-- UI happy.
				args = {1},
				default_arg = nil,
				event = "ToggleFontBolder",
			},
			{
				name = "font_gamma",
				name_text = "Gamma",
				item_text = {"decrease", "increase"},
				args = {"decrease", "increase"},
				default_arg = nil,
				event = "ChangeFontGamma",
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "view_mode",
				name_text = "View mode",
				toggle = {"scroll", "page"},
				values = {1, 0},
				default_value = 0,
				args = {"scroll", "page"},
				default_arg = "page",
				event = "SetViewMode",
			},
			{
				name = "embedded_css",
				name_text = "Embedded style",
				toggle = {"on", "off"},
				values = {1, 0},
				default_value = 0,
				args = {1, 0},
				default_arg = nil,
				event = "ToggleEmbeddedStyleSheet",
			},
		},
	},
}

CreDocument = Document:new{
	-- this is defined in kpvcrlib/crengine/crengine/include/lvdocview.h
	SCROLL_VIEW_MODE = 0,
	PAGE_VIEW_MODE = 1,

	_document = false,
	engine_initilized = false,

	line_space_percent = 100,
	default_font = "Droid Sans Fallback",
	header_font = "Droid Sans Fallback",
	default_css = "./data/cr3.css",
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

		local header_font = G_reader_settings:readSetting("header_font")
		if header_font then
			self.header_font = header_font
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
		file_type = self:zipContentExt(self.file)
	end
	-- these two format use the same css file
	if file_type == "html" then
		file_type = "htm"
	end
	-- if native css-file doesn't exist, one needs to use default cr3.css
	if not io.open("./data/"..file_type..".css") then
		file_type = "cr3"
	end
	self.default_css = "./data/"..file_type..".css"

	-- @TODO check the default view_mode to a global user configurable
	-- variable  22.12 2012 (houqp)
	ok, self._document = pcall(cre.newDocView,
		Screen:getWidth(), Screen:getHeight(), self.PAGE_VIEW_MODE
	)
	if not ok then
		self.error_message = self.doc -- will contain error message
		return
	end
	self.is_open = true
	self.info.has_pages = false
	self:_readMetadata()
	self.info.configurable = true
end

function CreDocument:loadDocument()
	self._document:loadDocument(self.file)
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

function CreDocument:setViewMode(new_mode)
	if new_mode then
		if new_mode == "scroll" then
			self._document:setViewMode(self.SCROLL_VIEW_MODE)
		else
			self._document:setViewMode(self.PAGE_VIEW_MODE)
		end
	end
end

function CreDocument:setHeaderFont(new_font)
	if new_font then
		self._document:setHeaderFont(new_font)
	end
end

function CreDocument:zoomFont(delta)
	self._document:zoomFont(delta)
end

function CreDocument:setInterlineSpacePercent(percent)
	self._document:setDefaultInterlineSpace(percent)
end

function CreDocument:toggleFontBolder()
	self._document:toggleFontBolder()
end

function CreDocument:setGammaIndex(index)
	cre.setGammaIndex(index)
end

function CreDocument:setStyleSheet(new_css)
	self._document:setStyleSheet(new_css)
end

function CreDocument:setEmbeddedStyleSheet(toggle)
	self._document:setEmbeddedStyleSheet(toggle)
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
