ReaderToc = InputContainer:new{
	toc_menu_title = "Table of contents",
}

function ReaderToc:init()
	if not Device:hasNoKeyboard() then
		self.key_events = {
			ShowToc = {
				{ "T" },
				doc = "show Table of Content menu" },
		}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderToc:cleanUpTocTitle(title)
	return (title:gsub("\13", ""))
end

function ReaderToc:onSetDimensions(dimen)
	self.dimen = dimen
end

--function ReaderToc:fillToc()
	--self.toc = self.doc:getToc()
--end

-- getTocTitleByPage wrapper, so specific reader
-- can tranform pageno according its need
function ReaderToc:getTocTitleByPage(pageno)
	return self:_getTocTitleByPage(pageno)
end

function ReaderToc:_getTocTitleByPage(pageno)
	if not self.toc then
	-- build toc when needed.
	self:fillToc()
	end

	-- no table of content
	if #self.toc == 0 then
		return ""
	end

	local pre_entry = self.toc[1]
	for _k,_v in ipairs(self.toc) do
		if _v.page > pageno then
			break
		end
		pre_entry = _v
	end
	return self:cleanUpTocTitle(pre_entry.title)
end

function ReaderToc:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.pageno)
end

function ReaderToc:onShowToc()
	local items = self.ui.document:getToc()
	-- build menu items
	for _,v in ipairs(items) do
		v.text = ("        "):rep(v.depth-1)..self:cleanUpTocTitle(v.title)
	end

	local toc_menu = Menu:new{
		title = "Table of Contents",
		item_table = items,
		ui = self.ui,
		width = Screen:getWidth()-20, 
		height = Screen:getHeight(),
	}
	function toc_menu:onMenuChoice(item)
		self.ui:handleEvent(Event:new("PageUpdate", item.page))
	end

	local menu_container = CenterContainer:new{
		dimen = Screen:getSize(),
		toc_menu,
	}
	toc_menu.close_callback = function() 
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)
end

function ReaderToc:addToMainMenu(item_table)
	-- insert table to main reader menu
	table.insert(item_table, {
		text = self.toc_menu_title,
		callback = function()
			self:onShowToc()
		end,
	})
end
