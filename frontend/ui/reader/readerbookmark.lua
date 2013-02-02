require "ui/notification"

ReaderBookmark = InputContainer:new{
	bm_menu_title = "Bookmarks",
	bookmarks = nil,
}

function ReaderBookmark:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ShowToc = {
				{ "B" },
				doc = "show bookmarks" },
		}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderBookmark:initGesListener()
	self.ges_events = {
		AddBookmark = {
			GestureRange:new{
				ges = "double_tap",
				range = Geom:new{
					x = Screen:getWidth()/2, y = 0,
					w = Screen:getWidth()/2,
					h = Screen:getHeight()/2
				}
			}
		},
	}
end

function ReaderBookmark:onReadSettings(config)
	self.bookmarks = config:readSetting("bookmarks") or {}
end

function ReaderBookmark:onCloseDocument()
	self.ui.doc_settings:saveSetting("bookmarks", self.bookmarks)
end

function ReaderBookmark:onSetDimensions(dimen)
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderBookmark:onAddBookmark()
	local pn_or_xp = nil
	if self.ui.document.getXPointer then
		pn_or_xp = self.ui.document:getXPointer()
	else
		pn_or_xp = self.view.state.page
	end

	local noti_text = "Bookmark added."
	if not self:addBookmark(pn_or_xp) then
		noti_text = "Page already marked!"
	end
	UIManager:show(Notification:new{
		text = noti_text,
		timeout = 3
	})
	return true
end

function ReaderBookmark:onShowBookmark()
	-- build up item_table
	for k, v in	ipairs(self.bookmarks) do
		local page = v.page
		-- for CREngine, bookmark page is xpointer
		if type(page) == "string" then
			page = self.ui.document:getPageFromXPointer(v.page)
		end
		v.text = "Page "..page.." "..v.notes.." @ "..v.datetime
	end

	local bm_menu = Menu:new{
		title = "Bookmarks",
		item_table = self.bookmarks,
		width = Screen:getWidth()-20, 
		height = Screen:getHeight(),
	}
	-- buid up menu widget method as closure
	local doc = self.ui.document
	local sendEv = function(ev)
		self.ui:handleEvent(ev)
	end
	function bm_menu:onMenuChoice(item)
		if doc.info.has_pages then
			sendEv(Event:new("PageUpdate", item.page))
		elseif self.view.view_mode == "page" then
			sendEv(Event:new("PageUpdate", doc:getPageFromXPointer(item.page)))
		else
			sendEv(Event:new("PosUpdate", doc:getPosFromXPointer(item.page)))
		end
	end

	local menu_container = CenterContainer:new{
		dimen = Screen:getSize(),
		bm_menu,
	}
	bm_menu.close_callback = function() 
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)
	return true
end

function ReaderBookmark:addToMainMenu(item_table)
	-- insert table to main reader menu
	table.insert(item_table, {
		text = self.bm_menu_title,
		callback = function()
			self:onShowBookmark()
		end,
	})
end

--[[
return nil if page already marked, otherwise, return true
for CREngine, bookmark page is xpointer instead of page number
--]]
function ReaderBookmark:addBookmark(pn_or_xp)
	for k,v in ipairs(self.bookmarks) do
		if v.page == pn_or_xp then
			return nil
		end
	end
	-- build notes from TOC
	local notes = self.ui.toc:getTocTitleByPage(pn_or_xp)
	if notes ~= "" then
		notes = "in "..notes
	end
	mark_item = {
		page = pn_or_xp,
		datetime = os.date("%Y-%m-%d %H:%M:%S"),
		notes = notes,
	}
	table.insert(self.bookmarks, mark_item)
	table.sort(self.bookmarks, function(a,b)
		return self:isBookmarkInSequence(a, b)
	end)
	return true
end

function ReaderBookmark:isBookmarkInSequence(a, b)
	return a.page < b.page
end


