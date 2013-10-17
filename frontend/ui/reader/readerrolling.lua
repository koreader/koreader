require "ui/reader/readerpanning"

ReaderRolling = InputContainer:new{
	old_doc_height = nil,
	old_page = nil,
	current_pos = 0,
	-- only used for page view mode
	current_page= nil,
	doc_height = nil,
	panning_steps = ReaderPanning.panning_steps,
	show_overlap_enable = true,
	overlap = 20,
}

function ReaderRolling:init()
	if Device:hasKeyboard() then
		self.key_events = {
			GotoNextView = {
				{ Input.group.PgFwd },
				doc = _("go to next view"),
				event = "GotoViewRel", args = 1
			},
			GotoPrevView = {
				{ Input.group.PgBack },
				doc = _("go to previous view"),
				event = "GotoViewRel", args = -1
			},
			MoveUp = {
				{ "Up" },
				doc = _("move view up"),
				event = "Panning", args = {0, -1}
			},
			MoveDown = {
				{ "Down" },
				doc = _("move view down"),
				event = "Panning", args = {0,  1}
			},
			GotoFirst = {
				{"1"}, doc = _("go to start"), event = "GotoPercent", args = 0},
			Goto11 = {
				{"2"}, doc = _("go to 11%"), event = "GotoPercent", args = 11},
			Goto22 = {
				{"3"}, doc = _("go to 22%"), event = "GotoPercent", args = 22},
			Goto33 = {
				{"4"}, doc = _("go to 33%"), event = "GotoPercent", args = 33},
			Goto44 = {
				{"5"}, doc = _("go to 44%"), event = "GotoPercent", args = 44},
			Goto55 = {
				{"6"}, doc = _("go to 55%"), event = "GotoPercent", args = 55},
			Goto66 = {
				{"7"}, doc = _("go to 66%"), event = "GotoPercent", args = 66},
			Goto77 = {
				{"8"}, doc = _("go to 77%"), event = "GotoPercent", args = 77},
			Goto88 = {
				{"9"}, doc = _("go to 88%"), event = "GotoPercent", args = 88},
			GotoLast = {
				{"0"}, doc = _("go to end"), event = "GotoPercent", args = 100},
		}
	end

	table.insert(self.ui.postInitCallback, function()
		self.doc_height = self.ui.document.info.doc_height
		self.old_doc_height = self.doc_height
		self.old_page = self.ui.document.info.number_of_pages
	end)
end

-- This method will  be called in onSetDimensions handler
function ReaderRolling:initGesListener()
	self.ges_events = {
		TapForward = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = Screen:getWidth()/4,
					y = Screen:getHeight()/4,
					w = 3*Screen:getWidth()/4,
					h = 5*Screen:getHeight()/8,
				}
			}
		},
		TapBackward = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0,
					y = Screen:getHeight()/4,
					w = Screen:getWidth()/4,
					h = 5*Screen:getHeight()/8,
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
		Pan = {
			GestureRange:new{
				ges = "pan",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				},
				rate = 4.0,
			}
		},
	}
end

function ReaderRolling:onReadSettings(config)
	local soe = config:readSetting("show_overlap_enable")
	if not soe then
		self.show_overlap_enable = soe
	end
	local last_xp = config:readSetting("last_xpointer")
	if last_xp then
		table.insert(self.ui.postInitCallback, function()
			self:gotoXPointer(last_xp)
			-- we have to do a real jump in self.ui.document._document to
			-- update status information in CREngine.
			self.ui.document:gotoXPointer(last_xp)
		end)
	end
	-- we read last_percent just for backward compatibility
	if not last_xp then
		local last_per = config:readSetting("last_percent")
		if last_per then
			table.insert(self.ui.postInitCallback, function()
				self:gotoPercent(last_per)
				-- we have to do a real pos change in self.ui.document._document
				-- to update status information in CREngine.
				self.ui.document:gotoPos(self.current_pos)
			end)
		end
	end
	if self.view.view_mode == "page" then
		self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
	end
end

function ReaderRolling:onCloseDocument()
	-- remove last_percent config since its deprecated
	self.ui.doc_settings:saveSetting("last_percent", nil)
	self.ui.doc_settings:saveSetting("last_xpointer", self.ui.document:getXPointer())
	self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
end

function ReaderRolling:getLastPercent()
	if self.view.view_mode == "page" then
		return self.current_page / self.old_page
	else
		-- FIXME: the calculated percent is not accurate in "scroll" mode.
		return self.ui.document:getPosFromXPointer(
			self.ui.document:getXPointer()) / self.doc_height
	end
end

function ReaderRolling:onTapForward()
	self:onGotoViewRel(1)
	return true
end

function ReaderRolling:onTapBackward()
	self:onGotoViewRel(-1)
	return true
end

function ReaderRolling:onSwipe(arg, ges)
	if ges.direction == "west" or ges.direction == "north" then
		self:onGotoViewRel(1)
	elseif ges.direction == "east" or ges.direction == "south" then
		self:onGotoViewRel(-1)
	end
	return true
end

function ReaderRolling:onPan(arg, ges)
	if self.view.view_mode == "scroll" then
		if ges.direction == "north" then
			self:gotoPos(self.current_pos + ges.distance)
		elseif ges.direction == "south" then
			self:gotoPos(self.current_pos - ges.distance)
		end
	end
	return true
end

function ReaderRolling:onPosUpdate(new_pos)
	self.current_pos = new_pos
end

function ReaderRolling:onPageUpdate(new_page)
	self.current_page = new_page
end

function ReaderRolling:onGotoPercent(percent)
	DEBUG("goto document offset in percent:", percent)
	self:gotoPercent(percent)
	return true
end

function ReaderRolling:onGotoViewRel(diff)
	DEBUG("goto relative screen:", diff, ", in mode: ", self.view.view_mode)
	if self.view.view_mode == "scroll" then
		local pan_diff = diff * self.ui.dimen.h
		if self.show_overlap_enable then
			if pan_diff > self.overlap then
				pan_diff = pan_diff - self.overlap
			elseif pan_diff < -self.overlap then
				pan_diff = pan_diff + self.overlap
			end
		end
		self:gotoPos(self.current_pos + pan_diff)
	elseif self.view.view_mode == "page" then
		self:gotoPage(self.current_page + diff)
	end
	return true
end

function ReaderRolling:onPanning(args, key)
	--@TODO disable panning in page view_mode?  22.12 2012 (houqp)
	local _, dy = unpack(args)
	DEBUG("key =", key)
	self:gotoPos(self.current_pos + dy * self.panning_steps.normal)
	return true
end

function ReaderRolling:onZoom()
	--@TODO re-read doc_height info after font or lineheight changes  05.06 2012 (houqp)
	self:onUpdatePos()
end

--[[
	remember to signal this event when the document has been zoomed,
	font has been changed, or line height has been changed.
--]]
function ReaderRolling:onUpdatePos()
	-- reread document height
	self.ui.document:_readMetadata()
	-- update self.current_pos if the height of document has been changed.
	local new_height = self.ui.document.info.doc_height
	local new_page = self.ui.document.info.number_of_pages
	if self.old_doc_height ~= new_height or self.old_page ~= new_page then
		self:gotoXPointer(self.ui.document:getXPointer())
		self.old_doc_height = new_height
		self.old_page = new_page
		self.ui:handleEvent(Event:new("UpdateToc"))
	end
	return true
end

function ReaderRolling:onChangeViewMode()
	self.ui.document:_readMetadata()
	self.old_doc_height = self.ui.document.info.doc_height
	self.old_page = self.ui.document.info.number_of_pages
	self.ui:handleEvent(Event:new("UpdateToc"))
	self:gotoXPointer(self.ui.document:getXPointer())
	if self.view.view_mode == "scroll" then
		self.current_pos = self.ui.document:getCurrentPos()
	else
		self.current_page = self.ui.document:getCurrentPage()
	end
	return true
end

function ReaderRolling:onRedrawCurrentView()
	if self.view.view_mode == "page" then
		self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
	else
		self.ui:handleEvent(Event:new("PosUpdate", self.current_pos))
	end
	return true
end

function ReaderRolling:onSetDimensions()
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

--[[
	PosUpdate event is used to signal other widgets that pos has been changed.
--]]
function ReaderRolling:gotoPos(new_pos)
	if new_pos == self.current_pos then return end
	if new_pos < 0 then new_pos = 0 end
	if new_pos > self.doc_height then new_pos = self.doc_height end
	-- adjust dim_area according to new_pos
	if self.view.view_mode ~= "page" and self.show_overlap_enable then
		local panned_step = new_pos - self.current_pos
		self.view.dim_area.x = 0
		self.view.dim_area.h = self.ui.dimen.h - math.abs(panned_step)
		self.view.dim_area.w = self.ui.dimen.w
		if panned_step < 0 then
			self.view.dim_area.y = self.ui.dimen.h - self.view.dim_area.h
		elseif panned_step > 0 then
			self.view.dim_area.y = 0
		end
	end
	self.ui:handleEvent(Event:new("PosUpdate", new_pos))
end

function ReaderRolling:gotoPage(new_page)
	self.ui.document:gotoPage(new_page)
	self.ui:handleEvent(Event:new("PageUpdate", new_page))
end

function ReaderRolling:gotoXPointer(xpointer)
	if self.view.view_mode == "page" then
		self:gotoPage(self.ui.document:getPageFromXPointer(xpointer))
	else
		self:gotoPos(self.ui.document:getPosFromXPointer(xpointer))
	end
end

function ReaderRolling:gotoPercent(new_percent)
	self:gotoPos(new_percent * self.doc_height / 10000)
end

function ReaderRolling:onGotoPage(number)
	self:gotoPage(number)
	return true
end
