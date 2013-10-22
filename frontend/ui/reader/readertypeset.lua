local InputContainer = require("ui/widget/container/inputcontainer")
local Event = require("ui/event")
local _ = require("gettext")
-- lfs

local ReaderTypeset = InputContainer:new{
	css_menu_title = _("Set render style"),
	css = nil,
	internal_css = true,
}

function ReaderTypeset:init()
	self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
	self.css = config:readSetting("css")
	if self.css and self.css ~= "" then
		self.ui.document:setStyleSheet(self.css)
	else
		self.ui.document:setStyleSheet("")
		self.css = nil
	end

	self.embedded_css = config:readSetting("embedded_css")
	-- default to enable embedded css
	if self.embedded_css == nil then
		self.embedded_css = true
	end
	if not self.embedded_css then
		self.ui.document:setEmbeddedStyleSheet(0)
	end
end

function ReaderTypeset:onCloseDocument()
	self.ui.doc_settings:saveSetting("css", self.css)
	self.ui.doc_settings:saveSetting("embedded_css", self.embedded_css)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
	self:toggleEmbeddedStyleSheet(toggle)
	return true
end

function ReaderTypeset:genStyleSheetMenu()
	local file_list = {
		{
			text = _("clear all external styles"),
			callback = function()
				self:setStyleSheet(nil)
			end
		},
		{
			text = _("Auto"),
			callback = function()
				self:setStyleSheet(self.ui.document.default_css)
			end
		},
	}
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
		--DEBUG("setting css to ", new_css)
		self.css = new_css
		if new_css == nil then
			new_css = ""
		end
		self.ui.document:setStyleSheet(new_css)
		self.ui:handleEvent(Event:new("UpdatePos"))
	end
end

function ReaderTypeset:setEmbededStyleSheetOnly()
	if self.css ~= nil then
		-- clear applied css
		self.ui.document:setStyleSheet("")
		self.ui.document:setEmbeddedStyleSheet(1)
		self.css = nil
		self.ui:handleEvent(Event:new("UpdatePos"))
	end
end

function ReaderTypeset:toggleEmbeddedStyleSheet(toggle)
	if not toggle then
		self.ui.document:setEmbeddedStyleSheet(0)
		self.embedded_css = false
	else
		self.ui.document:setEmbeddedStyleSheet(1)
		self.embedded_css = true
	end
	self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:addToMainMenu(tab_item_table)
	-- insert table to main reader menu
	table.insert(tab_item_table.typeset, {
		text = self.css_menu_title,
		sub_item_table = self:genStyleSheetMenu(),
	})
end

return ReaderTypeset
