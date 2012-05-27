ReaderToc = InputContainer:new{
	key_events = {
		ShowToc = { {"T"}, doc = "show Table of Content menu"},
	},
	dimen = Geom:new{ w = G_width-20, h = G_height-20},
	current_page = 0,
}

function ReaderToc:cleanUpTocTitle(title)
	return title:gsub("\13", "")
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

function ReaderToc:onPageUpdate(new_page_no)
	self.current_page = new_page_no
end


