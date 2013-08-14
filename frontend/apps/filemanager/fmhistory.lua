FileManagerHistory = InputContainer:extend{
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
	function readHistDir(order_arg, re)
		local pipe_out = io.popen("ls "..order_arg.." -1 ./history")
		for f in pipe_out:lines() do
			table.insert(re, {
				dir = DocSettings:getPathFromHistory(f),
				name = DocSettings:getNameFromHistory(f),
			})
		end
	end

	self.hist = {}
	local last_files = {}
	readHistDir("-c", last_files)
	for _,v in pairs(last_files) do
		table.insert(self.hist, {
			text = v.name,
			callback = function()
				showReaderUI(v.dir .. "/" .. v.name)
			end
		})
	end
end


