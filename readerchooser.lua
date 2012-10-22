require "font"
require "keys"
require "settings"
require "pdfreader"
require "djvureader"
require "koptreader"
require "picviewer"
require "crereader"

registry = {
	-- registry format:
	-- reader_name = {reader_object, supported_formats, priority}
	PDFReader  = {PDFReader, ";pdf;xps;cbz;", 1},
	DJVUReader = {DJVUReader, ";djvu;", 1},
	KOPTReader = {KOPTReader, ";djvu;pdf;", 2},
	CREReader  = {CREReader, ";epub;txt;rtf;htm;html;mobi;prc;azw;fb2;chm;pdb;doc;tcr;zip;", 1},
	PICViewer = {PICViewer, ";jpg;jpeg;", 1},
	-- seems to accept pdb-files for PalmDoc only
}

ReaderChooser = {
	-- UI constants
	title_H = 35,	-- title height
	title_bar_H = 15, -- title bar height
	options_H = 35, -- options height
	options_bar_T = 2, -- options bar thickness
	spacing = 35,	-- spacing between lines
	margin_H = 120,	-- horisontal margin
	margin_V = 300, -- vertical margin
	margin_I = 50,  -- reader item margin
	margin_O = 10,  -- option margin
	
	-- options text
	OPTION_TYPE = "Remember this type(T)",
	OPTION_FILE = "Remember this file(F)",
	
	-- data variables
	readers = {},
	final_choice = nil,
	last_item = 0,
	current_item = 1,
	-- state variables
	dialogdirty = true,
	markerdirty = false,
	optiondirty = true,
	remember_default = false,
	remember_last = false,
}

function GetRegisteredReaders(ftype)
	local s = ";"
	local readers = {}
	for key,value in pairs(registry) do
		if string.find(value[2],s..ftype..s) then
			table.insert(readers,key)
		end
	end
	table.sort(readers, function(a,b) return registry[a][3]<registry[b][3] end)
	return readers
end

-- find the first reader registered with this file type
function ReaderChooser:getReaderByType(ftype)
	local readers = GetRegisteredReaders(ftype)
	if #readers >= 1 then
		return registry[readers[1]][1]
	else
		return nil
	end
end

function ReaderChooser:getReaderByName(filename)
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)"))
	local readers = GetRegisteredReaders(file_type)
	if #readers > 1 then -- more than one reader are registered with this file type
		local default_readers = G_reader_settings:readSetting("default_readers")
		
		if default_readers then
			default_reader = default_readers[file_type]
			if default_reader then
				return registry[default_reader][1]
			end
		end
		
		local file_settings = DocSettings:open(filename)
		local last_reader = file_settings:readSetting("last_reader")
		Debug("Reading saved preference:", last_reader)
		if last_reader then
			file_settings:close()
			return registry[last_reader][1]
		else
			local name = self:choose(readers)
			if name then
				if self.remember_default then
					if not default_readers then
						default_readers = {}
					end
					default_readers[file_type] = name
					G_reader_settings:saveSetting("default_readers", default_readers)
				end
				if self.remember_last then
					Debug("Saving last reader:", name)
					file_settings:saveSetting("last_reader", name)
				end
				file_settings:close()
				return registry[name][1]
			else
				file_settings:close()
				return nil
			end
		end
	elseif #readers == 1 then
		return registry[readers[1]][1]
	else
		return nil
	end
end

function ReaderChooser:drawBox(xpos, ypos, w, h, bgcolor, bdcolor)
	-- draw dialog border
	local r = 6  -- round corners
	fb.bb:paintRect(xpos, ypos+r, w, h - r, bgcolor)
	blitbuffer.paintBorder(fb.bb, xpos, ypos, w, r, r, bdcolor, r)
	blitbuffer.paintBorder(fb.bb, xpos+2, ypos + 2, w - 4, r, r, bdcolor, r)
end

function ReaderChooser:drawTitle(text, xpos, ypos, w, font_face)
	-- draw title text
	renderUtf8Text(fb.bb, xpos+10, ypos+self.title_H, font_face, text, true)
	-- draw title bar
	fb.bb:paintRect(xpos, ypos+self.title_H+self.title_bar_H, w, 3, 5)
	
end

function ReaderChooser:drawReaderItem(name, xpos, ypos, cface)
	-- draw reader name
	renderUtf8Text(fb.bb, xpos+self.margin_I, ypos, cface, name, true)
	return sizeUtf8Text(0, G_width, cface, name, true).x
end

function ReaderChooser:drawOptions(xpos, ypos, barcolor, bgcolor, cface)
	local width, height = fb.bb:getWidth()-2*self.margin_H, fb.bb:getHeight()-2*self.margin_V
	local optbar_T = self.options_bar_T
	-- draw option border
	fb.bb:paintRect(xpos, ypos, width, self.options_bar_T, barcolor)
	fb.bb:paintRect(xpos+(width-optbar_T)/2, ypos, optbar_T, self.options_H, barcolor)
	-- draw option cell
	fb.bb:paintRect(xpos, ypos+self.options_bar_T, (width-optbar_T)/2, self.options_H-optbar_T, bgcolor+3*(self.remember_default and 1 or 0))
	fb.bb:paintRect(xpos+(width+optbar_T)/2, ypos+2, (width-optbar_T)/2, self.options_H-optbar_T, bgcolor+3*(self.remember_last and 1 or 0))
	-- draw option text
	renderUtf8Text(fb.bb, xpos+self.margin_O, ypos+self.options_H/2+8, cface, self.OPTION_TYPE, true)
	renderUtf8Text(fb.bb, xpos+width/2+self.margin_O, ypos+self.options_H/2+8, cface, self.OPTION_FILE, true)
	fb:refresh(1, xpos, ypos, width, self.options_H-optbar_T)
end

function ReaderChooser:choose(readers)
	self.readers = {}
	self.final_choice = nil
	self.readers = readers
	self.dialogdirty = true
	self.markerdirty = false
	self.optiondirty = true
	self:addAllCommands()
	
	local tface = Font:getFace("tfont", 23)
	local cface = Font:getFace("cfont", 20)
	local fface = Font:getFace("ffont", 16)
	
	local topleft_x, topleft_y = self.margin_H, self.margin_V
	local width, height = fb.bb:getWidth()-2*self.margin_H, fb.bb:getHeight()-2*self.margin_V
	local botleft_x, botleft_y = self.margin_H, topleft_y+height
	
	Debug("Drawing box")
	self:drawBox(topleft_x, topleft_y, width, height, 3, 3)
	Debug("Drawing title")
	self:drawTitle("Complete action using", topleft_x, topleft_y, width, tface)
	
	local reader_text_width = {}
	for index,name in ipairs(self.readers) do
		Debug("Drawing reader:",index,name)
		reader_text_width[index] = self:drawReaderItem(name, topleft_x, topleft_y+self.title_H+self.spacing*index+10, cface)
	end
	
	fb:refresh(1, topleft_x, topleft_y, width, height)
	
	-- paint first reader marker
	local xmarker = topleft_x + self.margin_I
	local ymarker = topleft_y + self.title_H + self.title_bar_H
	fb.bb:paintRect(xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3, 15)
	fb:refresh(1, xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3)
	
	local ev, keydef, command, ret_code
	while true do
		if self.markerdirty then
			fb.bb:paintRect(xmarker, ymarker+self.spacing*self.last_item, reader_text_width[self.last_item], 3, 3)
			fb:refresh(1, xmarker, ymarker+self.spacing*self.last_item, reader_text_width[self.last_item], 3)
			fb.bb:paintRect(xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3, 15)
			fb:refresh(1, xmarker, ymarker+self.spacing*self.current_item, reader_text_width[self.current_item], 3)
			self.markerdirty = false
		end
		
		if self.optiondirty then
			self:drawOptions(botleft_x, botleft_y-self.options_H, 5, 3, fface)
			self.optiondirty = false
		end
			
		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			Debug("key pressed: "..tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				Debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				Debug("command not found: "..tostring(command))
			end
			if ret_code == "break" then
				ret_code = nil
				if self.final_choice then
					return self.readers[self.final_choice]
				else
					return nil
				end
			end
		end -- if
	end -- while
end

-- add available commands
function ReaderChooser:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"next item",
		function(self)
			self.last_item = self.current_item
			self.current_item = (self.current_item + #self.readers + 1)%#self.readers
			if self.current_item == 0 then
				self.current_item = self.current_item + #self.readers
			end
			Debug("Last item:", self.last_item, "Current item:", self.current_item, "N items:", #self.readers)
			self.markerdirty = true
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"previous item",
		function(self)
			self.last_item = self.current_item
			self.current_item = (self.current_item + #self.readers - 1)%#self.readers
			if self.current_item == 0 then
				self.current_item = self.current_item + #self.readers
			end
			Debug("Last item:", self.last_item, "Current item:", self.current_item, "N items:", #self.readers)
			self.markerdirty = true
		end
	)
	
	self.commands:add(KEY_T, nil, "T",
		"remember reader choice for this type",
		function(self)
			self.remember_default = not self.remember_default
			self.optiondirty = true
		end
	)
	
	self.commands:add(KEY_F, nil, "F",
		"remember reader choice for this file",
		function(self)
			self.remember_last = not self.remember_last
			self.optiondirty = true
		end
	)
	
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"choose reader",
		function(self)
			self.final_choice = self.current_item
			return "break"
		end
	)
	self.commands:add({KEY_BACK, KEY_HOME}, nil, "Back, Home",
		"back",
		function(self)
			return "break"
		end
	)
end
