ReaderPaging = InputContainer:new{
	key_events = {
		GotoNextPage = { {Input.group.PgFwd}, doc = "go to next page", event = "GotoPageRel", args = 1 },
		GotoPrevPage = { {Input.group.PgBack}, doc = "go to previous page", event = "GotoPageRel", args = -1 },

		GotoFirst = { {"1"}, doc = "go to start", event = "GotoPercent", args = 0},
		Goto11 = { {"2"}, doc = "go to 11%", event = "GotoPercent", args = 11},
		Goto22 = { {"3"}, doc = "go to 22%", event = "GotoPercent", args = 22},
		Goto33 = { {"4"}, doc = "go to 33%", event = "GotoPercent", args = 33},
		Goto44 = { {"5"}, doc = "go to 44%", event = "GotoPercent", args = 44},
		Goto55 = { {"6"}, doc = "go to 55%", event = "GotoPercent", args = 55},
		Goto66 = { {"7"}, doc = "go to 66%", event = "GotoPercent", args = 66},
		Goto77 = { {"8"}, doc = "go to 77%", event = "GotoPercent", args = 77},
		Goto88 = { {"9"}, doc = "go to 88%", event = "GotoPercent", args = 88},
		GotoLast = { {"0"}, doc = "go to end", event = "GotoPercent", args = 100},
	},
	current_page = 0,
	number_of_pages = 0
}

function ReaderPaging:init()
	self.number_of_pages = self.ui.document.info.number_of_pages
end

-- wrapper for bounds checking
function ReaderPaging:gotoPage(number)
	if number == self.current_page then
		return true
	end
	if number > self.number_of_pages
	or number < 1 then
		return false
	end
	DEBUG("going to page number", number)

	-- this is an event to allow other controllers to be aware of this change
	self.ui:handleEvent(Event:new("PageUpdate", number))

	return true
end

function ReaderPaging:onPageUpdate(new_page_no)
	self.current_page = new_page_no
end

function ReaderPaging:onGotoPercent(percent)
	DEBUG("goto document offset in percent:", percent)
	local dest = math.floor(self.number_of_pages * percent / 100)
	if dest < 1 then dest = 1 end
	if dest > self.number_of_pages then
		dest = self.number_of_pages
	end
	self:gotoPage(dest)
	return true
end

function ReaderPaging:onGotoPageRel(diff)
	DEBUG("goto relative page:", diff)
	self:gotoPage(self.current_page + diff)
	return true
end
