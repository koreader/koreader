require "ui/widget/container"
require "ui/widget/inputdialog"


ReaderGoto = InputContainer:new{
	goto_menu_title = _("Go To"),
	goto_dialog_title = _("Go to Page or Location"),
}

function ReaderGoto:init()
	self.goto_dialog = InputDialog:new{
		title = self.goto_dialog_title,
		input_hint = "(1 - "..self.document.info.number_of_pages..")",
		buttons = {
			{	
				{
					text = _("Cancel"),
					enabled = true,
					callback = function()
						self:onClose()
					end,
				},
				{
					text = _("Page"),
					enabled = self.document.info.has_pages,
					callback = function()
						self:onGotoPage()
					end,
				},
				{
					text = _("Location"),
					enabled = not self.document.info.has_pages,
					callback = function()
						self:onGotoLocation()
					end,
				},
			},
		},
		input_type = "number",
		width = Screen:getWidth() * 0.8,
		height = Screen:getHeight() * 0.2,
	}
	self.ui.menu:registerToMainMenu(self)
end

function ReaderGoto:addToMainMenu(tab_item_table)
	-- insert goto command to main reader menu
	table.insert(tab_item_table.navi, {
		text = self.goto_menu_title,
		callback = function()
			self:onShowGotoDialog()
		end,
	})
end

function ReaderGoto:onShowGotoDialog()
	DEBUG("show goto dialog")
	self.goto_dialog:onShowKeyboard()
	UIManager:show(self.goto_dialog)
end

function ReaderGoto:onClose()
	self.goto_dialog:onClose()
	UIManager:close(self.goto_dialog)
end

function ReaderGoto:onGotoPage()
	local number = tonumber(self.goto_dialog:getInputText())
	if number then
		DEBUG("go to page", number)
		self.ui:handleEvent(Event:new("PageUpdate", number))
	end
	self:onClose()
	return true
end

function ReaderGoto:onGotoLocation()
	-- TODO: implement go to location
	self:onClose()
end
