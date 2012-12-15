ReaderMenu = InputContainer:new{
	item_table = {},
	registered_widgets = {},
}

function ReaderMenu:init()
	self.item_table = {}
	self.registered_widgets = {}

	if Device:isTouchDevice() then
		self.ges_events = {
			TapShowMenu = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()/2
					}
				}
			},
		}
	else
		self.key_events = {
			ShowMenu = { { "Menu" }, doc = "show menu" },
		}
	end
end

function ReaderMenu:setUpdateItemTable()
	table.insert(self.item_table, {
		text = "Screen rotate",
		sub_item_table = {
			{
				text = "rotate 90 degree clockwise",
				callback = function()
					Screen:screenRotate("clockwise")
					self.ui:handleEvent(
						Event:new("SetDimensions", Screen:getSize()))
				end
			},
			{
				text = "rotate 90 degree anticlockwise",
				callback = function()
					Screen:screenRotate("anticlockwise")
					self.ui:handleEvent(
						Event:new("SetDimensions", Screen:getSize()))
				end
			},
		}
	})

	for _, widget in pairs(self.registered_widgets) do
		widget:addToMainMenu(self.item_table)
	end

	table.insert(self.item_table, {
		text = "Return to file browser",
		callback = function()
			UIManager:close(self.menu_container)
			self.ui:onClose()
		end
	})
end

function ReaderMenu:onShowMenu()
	if #self.item_table == 0 then
		self:setUpdateItemTable()
	end

	local main_menu = Menu:new{
		title = "Document menu",
		item_table = self.item_table,
		width = Screen:getWidth() - 100,
	}
	function main_menu:onMenuChoice(item)
		if item.callback then
			item.callback()
		end
	end

	local menu_container = CenterContainer:new{
		main_menu,
		dimen = Screen:getSize(),
	}
	main_menu.close_callback = function () 
		UIManager:close(menu_container)
	end
	-- maintain a reference to menu_container
	self.menu_container = menu_container

	UIManager:show(menu_container)

	return true
end

function ReaderMenu:onTapShowMenu()
	self:onShowMenu()
	return true
end

function ReaderMenu:onSetDimensions(dimen)
	-- @TODO  update gesture listenning range according to new screen
	-- orientation 15.12 2012 (houqp)
end

function ReaderMenu:onCloseDocument()
end

function ReaderMenu:addToMainMenuCallback(widget)
	table.insert(self.registered_widgets, widget)
end

