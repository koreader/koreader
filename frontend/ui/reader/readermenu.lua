require "ui/widget/menu"
require "ui/widget/touchmenu"

ReaderMenu = InputContainer:new{
	tab_item_table = nil,
	registered_widgets = {},
}

function ReaderMenu:init()
	self.tab_item_table = {
		main = {
			icon = "resources/icons/appbar.pokeball.png",
		},
		navi = {
			icon = "resources/icons/appbar.page.corner.bookmark.png",
		},
		typeset = {
			icon = "resources/icons/appbar.page.text.png",
		},
		home = {
			icon = "resources/icons/appbar.home.png",
			callback = function()
				self.ui:handleEvent(Event:new("RestoreScreenMode",
					G_reader_settings:readSetting("screen_mode") or "portrait"))
				UIManager:close(self.menu_container)
				self.ui:onClose()
			end,
		},
	}
	self.registered_widgets = {}

	if Device:hasKeyboard() then
		self.key_events = {
			ShowMenu = { { "Menu" }, doc = _("show menu") },
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
	for _, widget in pairs(self.registered_widgets) do
		widget:addToMainMenu(self.tab_item_table)
	end
	if Device:hasFrontlight() then
		table.insert(self.tab_item_table.main, {
			text = _("Frontlight settings"),
			callback = function()
				ReaderFrontLight:onShowFlDialog()
			end
		})
	end
	table.insert(self.tab_item_table.main, {
		text = _("Help"),
		callback = function()
			UIManager:show(InfoMessage:new{
				text = _("Please report bugs to https://github.com/koreader/ koreader/issues, Click at the bottom of the page for more options"),
			})
		end
	})
end

function ReaderMenu:onShowMenu()
	if #self.tab_item_table.main == 0 then
		self:setUpdateItemTable()
	end

	local menu_container = CenterContainer:new{
		ignore = "height",
		dimen = Screen:getSize(),
	}

	local main_menu = nil
	if Device:isTouchDevice() then
		main_menu = TouchMenu:new{
			width = Screen:getWidth(),
			tab_item_table = {
				self.tab_item_table.navi,
				self.tab_item_table.typeset,
				self.tab_item_table.main,
				self.tab_item_table.home,
			},
			show_parent = menu_container,
		}
	else
		main_menu = Menu:new{
			title = _("Document menu"),
			item_table = {},
			width = Screen:getWidth() - 100,
		}

		for _,item_table in pairs(self.tab_item_table) do
			for k,v in ipairs(item_table) do
				table.insert(main_menu.item_table, v)
			end
		end
	end

	main_menu.close_callback = function ()
		UIManager:close(menu_container)
	end

	menu_container[1] = main_menu
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

