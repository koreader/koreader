local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local UIManager = require("ui/uimanager")
local DocSettings = require("docsettings")
local DEBUG = require("dbg")
local _ = require("gettext")

local FileManagerHistory = InputContainer:extend{
	hist_menu_title = _("History"),
}

function FileManagerHistory:init()
	self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:onSetDimensions(dimen)
	self.dimen = dimen
end

function FileManagerHistory:onShowHist()
	self:updateItemTable()

	local menu_container = CenterContainer:new{
		dimen = Screen:getSize(),
	}

	local hist_menu = Menu:new{
		title = _("History"),
		item_table = self.hist,
		ui = self.ui,
		width = Screen:getWidth()-50,
		height = Screen:getHeight()-50,
		show_parent = menu_container,
	}

	table.insert(menu_container, hist_menu)

	hist_menu.close_callback = function()
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)
	return true
end

function FileManagerHistory:addToMainMenu(tab_item_table)
	-- insert table to main reader menu
	table.insert(tab_item_table.main, {
		text = self.hist_menu_title,
		callback = function()
			self:onShowHist()
		end,
	})
end

function FileManagerHistory:updateItemTable()
	function readHistDir(re)
		local sorted_files = {}
		local history_dir = "./history/"
		for f in lfs.dir(history_dir) do
			local path = history_dir..f
			if lfs.attributes(path, "mode") == "file" then
				table.insert(sorted_files, {file = f, date = lfs.attributes(path, "modification")})
			end
		end
		table.sort(sorted_files, function(v1,v2) return v1.date > v2.date end)
		for _, v in pairs(sorted_files) do
			table.insert(re, {
				dir = DocSettings:getPathFromHistory(v.file),
				name = DocSettings:getNameFromHistory(v.file),
			})
		end
	end

	self.hist = {}
	local last_files = {}
	readHistDir(last_files)
	for _,v in pairs(last_files) do
		table.insert(self.hist, {
			text = v.name,
			callback = function()
				showReaderUI(v.dir .. "/" .. v.name)
			end
		})
	end
end

return FileManagerHistory