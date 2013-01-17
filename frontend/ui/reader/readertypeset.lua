ReaderTypeset = InputContainer:new{
	css_menu_title = "CSS Menu",
	css = nil,
}

function ReaderTypeset:init()
	self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
	self.css = config:readSetting("css")
	if not self.css then 
		self.css = self.ui.document.default_css
	end
	self.ui.document:setStyleSheet(self.css)
end

function ReaderTypeset:onCloseDocument()
	self.ui.doc_settings:saveSetting("css", self.css)
end

function ReaderTypeset:genStyleSheetMenu()
	local file_list = {}
	for f in lfs.dir("./data") do
		if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
			table.insert(file_list, {
				text = f,
				callback = function() 
					self:setStyleSheet("./data/"..f)
				end
			})
		end
	end
	return file_list
end

function ReaderTypeset:setStyleSheet(new_css)
	if new_css ~= self.css then
		self.ui.document:setStyleSheet(new_css)
		self.css = new_css
		self.ui:handleEvent(Event:new("UpdatePos"))
	end
end

function ReaderTypeset:addToMainMenu(item_table)
	-- insert table to main reader menu
	table.insert(item_table, {
		text = self.css_menu_title,
		sub_item_table = self:genStyleSheetMenu(),
	})
end


