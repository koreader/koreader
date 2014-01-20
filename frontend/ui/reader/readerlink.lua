local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local Event = require("ui/event")
local DEBUG = require("dbg")

local ReaderLink = InputContainer:new{
	link_states = {}
}

function ReaderLink:init()
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderLink:initGesListener()
	if Device:isTouchDevice() then
		self.ges_events = {
			Tap = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			Swipe = {
				GestureRange:new{
					ges = "swipe",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			},
		}
	end
end

function ReaderLink:onSetDimensions(dimen)
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderLink:onTap(arg, ges)
	local function inside_box(pos, box)
		if pos then
			local x, y = pos.x, pos.y
			if box.x <= x and box.y <= y 
				and box.x + box.w >= x 
				and box.y + box.h >= y then
				return true
			end
		end
	end
	if self.ui.document.info.has_pages then
		local pos = self.view:screenToPageTransform(ges.pos)
		local page_links = self.ui.document:getPageLinks(pos.page)
		--DEBUG("page links", page_links)
		if page_links then
			for i = 1, #page_links do
				local link = page_links[i]
				-- enlarge tappable link box
				local lbox = Geom:new{
					x = link.x0 - Screen:scaleByDPI(15),
					y = link.y0 - Screen:scaleByDPI(15),
					w = link.x1 - link.x0 + Screen:scaleByDPI(30),
					h = link.y1 - link.y0 + Screen:scaleByDPI(30)
				}
				if inside_box(pos, lbox) and link.page then
					return self:onGotoLink(link)
				end
			end
		end
	else
		local link = self.ui.document:getLinkFromPosition(ges.pos)
		if link ~= "" then
			return self:onGotoLink(link)
		end
	end
end

function ReaderLink:onGotoLink(link)
	if self.ui.document.info.has_pages then
		table.insert(self.link_states, self.view.state.page)
		self.ui:handleEvent(Event:new("PageUpdate", link.page + 1))
	else
		table.insert(self.link_states, self.ui.document:getXPointer())
		self.document:gotoLink(link)
		self.ui:handleEvent(Event:new("UpdateXPointer"))
	end
	return true
end

function ReaderLink:onSwipe(arg, ges)
	if ges.direction == "east" then
		if self.ui.document.info.has_pages then
			local last_page = table.remove(self.link_states)
			if last_page then
				self.ui:handleEvent(Event:new("PageUpdate", last_page))
				return true
			end
		else
			local last_xp = table.remove(self.link_states)
			if last_xp then
				self.ui.document:gotoXPointer(last_xp)
				self.ui:handleEvent(Event:new("UpdateXPointer"))
				return true
			end
		end
	end
end

return ReaderLink
