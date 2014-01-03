local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local _ = require("gettext")

local ReaderBookmark = InputContainer:new{
	bm_menu_title = _("Bookmarks"),
	bookmarks = nil,
}

function ReaderBookmark:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ShowToc = {
				{ "B" },
				doc = _("show bookmarks") },
		}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderBookmark:onReadSettings(config)
	self.bookmarks = config:readSetting("bookmarks") or {}
end

function ReaderBookmark:onSaveSettings()
	self.ui.doc_settings:saveSetting("bookmarks", self.bookmarks)
end

function ReaderBookmark:onToggleBookmark()
	local pn_or_xp = nil
	if self.ui.document.getXPointer then
		pn_or_xp = self.ui.document:getXPointer()
	else
		pn_or_xp = self.view.state.page
	end
	self:toggleBookmark(pn_or_xp)
	self.view.dogear_visible = not self.view.dogear_visible
	UIManager:setDirty(self.view.dialog, "partial")
	return true
end

function ReaderBookmark:setDogearVisibility(pn_or_xp)
	if self:isBookmarked(pn_or_xp) then
		self.ui:handleEvent(Event:new("SetDogearVisibility", true))
	else
		self.ui:handleEvent(Event:new("SetDogearVisibility", false))
	end
end

function ReaderBookmark:onPageUpdate(pageno)
	self:setDogearVisibility(pageno)
end

function ReaderBookmark:onPosUpdate(pos)
	-- TODO: cannot check if this pos is bookmarked or not.
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
	
	local menu_container = CenterContainer:new{
		dimen = Screen:getSize(),
	}

	local bm_menu = Menu:new{
		title = "Bookmarks",
		item_table = self.bookmarks,
		width = Screen:getWidth()-50,
		height = Screen:getHeight()-50,
		show_parent = menu_container,
	}
	
	table.insert(menu_container, bm_menu)
	
	-- buid up menu widget method as closure
	local doc = self.ui.document
	local view = self.view
	local sendEv = function(ev)
		self.ui:handleEvent(ev)
	end
	function bm_menu:onMenuChoice(item)
		if doc.info.has_pages then
			sendEv(Event:new("PageUpdate", item.page))
		elseif view.view_mode == "page" then
			sendEv(Event:new("PageUpdate", doc:getPageFromXPointer(item.page)))
		else
			sendEv(Event:new("PosUpdate", doc:getPosFromXPointer(item.page)))
		end
	end

	bm_menu.close_callback = function()
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)
	return true
end

function ReaderBookmark:addToMainMenu(tab_item_table)
	-- insert table to main reader menu
	table.insert(tab_item_table.navi, {
		text = self.bm_menu_title,
		callback = function()
			self:onShowBookmark()
		end,
	})
end

function ReaderBookmark:isBookmarked(pn_or_xp)
	for k,v in ipairs(self.bookmarks) do
		if v.page == pn_or_xp then
			return true
		end
	end
	return false
end

function ReaderBookmark:addBookmark(pn_or_xp)
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

function ReaderBookmark:toggleBookmark(pn_or_xp)
	for k,v in ipairs(self.bookmarks) do
		if v.page == pn_or_xp then
			table.remove(self.bookmarks, k)
			return
		end
	end
	self:addBookmark(pn_or_xp)
end

function ReaderBookmark:getPreviousBookmarkedPage(pn_or_xp)
	for i = #self.bookmarks, 1, -1 do
		if pn_or_xp > self.bookmarks[i].page then
			return self.bookmarks[i].page
		end
	end
end

function ReaderBookmark:getNextBookmarkedPage(pn_or_xp)
	for i = 1, #self.bookmarks do
		if pn_or_xp < self.bookmarks[i].page then
			return self.bookmarks[i].page
		end
	end
end

function ReaderBookmark:onGotoPreviousBookmark(pn_or_xp)
	self:GotoBookmark(self:getPreviousBookmarkedPage(pn_or_xp))
	return true
end

function ReaderBookmark:onGotoNextBookmark(pn_or_xp)
	self:GotoBookmark(self:getNextBookmarkedPage(pn_or_xp))
	return true
end

function ReaderBookmark:GotoBookmark(pn_or_xp)
	if type(pn_or_xp) == "string" then
		if self.view.view_mode == "page" then
			self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getPageFromXPointer(pn_or_xp)))
		else
			self.ui:handleEvent(Event:new("PosUpdate", self.ui.document:getPosFromXPointer(pn_or_xp)))
		end
	elseif type(pn_or_xp) == "number" then
		self.ui:handleEvent(Event:new("PageUpdate", pn_or_xp))
	end
end

return ReaderBookmark
