ReaderMenu = InputContainer:new{
	_name = "ReaderMenu",
	item_table = {},
	registered_widgets = {},
}

function ReaderMenu:init()
	self.item_table = {}
	self.registered_widgets = {}

	if Device:hasKeyboard() then
		self.key_events = {
			ShowMenu = { { "Menu" }, doc = "show menu" },
		}
	end
end

function ReaderMenu:initGesListener()
	self.ges_events = {
		TapShowMenu = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = Screen:getWidth()/8,
					y = 0,
					w = Screen:getWidth()*3/4,
					h = Screen:getHeight()/4,
				}
			}
		},
	}
end

function ReaderMenu:setUpdateItemTable()
	table.insert(self.item_table, {
		text = "Screen rotate",
		sub_item_table = {
			{
				text = "landscape",
				callback = function()
					self.ui:handleEvent(
						Event:new("SetScreenMode", "landscape"))
				end
			},
			{
				text = "portrait",
				callback = function()
					self.ui:handleEvent(
						Event:new("SetScreenMode", "portrait"))
				end
			},
		}
	})

	for _, widget in pairs(self.registered_widgets) do
		widget:addToMainMenu(self.item_table)
	end

	table.insert(self.item_table, {
		text = "Return to file manager",
		callback = function()
			self.ui:handleEvent(Event:new("RestoreScreenMode", 
				G_reader_settings:readSetting("screen_mode") or "portrait"))
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

	local menu_container = CenterContainer:new{
		ignore = "height",
		dimen = Screen:getSize(),
		main_menu,
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
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderMenu:onCloseDocument()
end

function ReaderMenu:registerToMainMenu(widget)
	table.insert(self.registered_widgets, widget)
end

