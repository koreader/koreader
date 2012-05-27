ReaderToc = InputContainer:new{
	key_events = {
		ShowToc = { {"T"}, doc = "show Table of Content menu"},
	},
	dimen = Geom:new{ w = G_width-20, h = G_height-20},
}

function ReaderToc:cleanUpTocTitle(title)
	return title:gsub("\13", "")
end

function ReaderToc:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderToc:onShowToc()
	function callback(item)
		self.ui:handleEvent(Event:new("PageUpdate", item.page))
	end

	local items = self.ui.document:getToc()
	-- build menu items
	for _,v in ipairs(items) do
		v.text = ("        "):rep(v.depth-1)..self:cleanUpTocTitle(v.title)
	end
	toc_menu = Menu:new{
		title = "Table of Contents",
		item_table = items,
		width = self.dimen.w,
		height = self.dimen.h,
		on_select_callback = callback,
	}

	UIManager:show(toc_menu)
end

