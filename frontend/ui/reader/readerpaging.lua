ReaderPaging = InputContainer:new{
	current_page = 0,
	number_of_pages = 0,
	visible_area = nil,
	page_area = nil,
	show_overlap_enable = true,
	overlap = 20,
}

function ReaderPaging:init()
	if Device:isTouchDevice() then
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
			}
		}
	else
		self.key_events = {
			GotoNextPage = { 
				{Input.group.PgFwd}, doc = "go to next page",
				event = "GotoPageRel", args = 1 },
			GotoPrevPage = { 
				{Input.group.PgBack}, doc = "go to previous page",
				event = "GotoPageRel", args = -1 },

			GotoFirst = { 
				{"1"}, doc = "go to start", event = "GotoPercent", args = 0},
			Goto11 = { 
				{"2"}, doc = "go to 11%", event = "GotoPercent", args = 11},
			Goto22 = { 
				{"3"}, doc = "go to 22%", event = "GotoPercent", args = 22},
			Goto33 = { 
				{"4"}, doc = "go to 33%", event = "GotoPercent", args = 33},
			Goto44 = { 
				{"5"}, doc = "go to 44%", event = "GotoPercent", args = 44},
			Goto55 = { 
				{"6"}, doc = "go to 55%", event = "GotoPercent", args = 55},
			Goto66 = { 
				{"7"}, doc = "go to 66%", event = "GotoPercent", args = 66},
			Goto77 = { 
				{"8"}, doc = "go to 77%", event = "GotoPercent", args = 77},
			Goto88 = { 
				{"9"}, doc = "go to 88%", event = "GotoPercent", args = 88},
			GotoLast = { 
				{"0"}, doc = "go to end", event = "GotoPercent", args = 100},
		}
	end
	self.number_of_pages = self.ui.document.info.number_of_pages
end

function ReaderPaging:onReadSettings(config)
	self:gotoPage(config:readSetting("last_page") or 1)
	local soe = config:readSetting("show_overlap_enable")
	if not soe then
		self.show_overlap_enable = soe
	end
end

function ReaderPaging:onCloseDocument()
	self.ui.doc_settings:saveSetting("last_page", self.current_page)
	self.ui.doc_settings:saveSetting("percent_finished", self.current_page/self.number_of_pages)
end

function ReaderPaging:onTapForward()
	self:onGotoPageRel(1)
	return true
end

function ReaderPaging:onTapBackward()
	self:onGotoPageRel(-1)
	return true
end

-- wrapper for bounds checking
function ReaderPaging:gotoPage(number)
	if number == self.current_page then
		return true
	end
	if number > self.number_of_pages
	or number < 1 then
		DEBUG("wrong page number: "..number.."!")
		return false
	end
	DEBUG("going to page number", number)

	-- this is an event to allow other controllers to be aware of this change
	self.ui:handleEvent(Event:new("PageUpdate", number))

	return true
end

function ReaderPaging:onZoomModeUpdate(new_mode)
	-- we need to remember zoom mode to handle page turn event
	self.zoom_mode = new_mode
end

function ReaderPaging:onPageUpdate(new_page_no)
	self.current_page = new_page_no
end

function ReaderPaging:onViewRecalculate(visible_area, page_area)
	-- we need to remember areas to handle page turn event
	self.visible_area = visible_area:copy()
	self.page_area = page_area
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
	local new_va = self.visible_area:copy()
	local x_pan_off, y_pan_off = 0, 0

	if self.zoom_mode:find("width") then
		y_pan_off = self.visible_area.h * diff
	elseif self.zoom_mode:find("height") then
		x_pan_off = self.visible_area.w * diff
	else
		-- must be fit content or page zoom mode
		if self.visible_area.w == self.page_area.w then
			y_pan_off = self.visible_area.h * diff
		else
			x_pan_off = self.visible_area.w * diff
		end
	end
	-- adjust offset to help with page turn decision
	-- we dont take overlap into account here yet, otherwise new_va will
	-- always intersect with page_area
	x_pan_off = math.roundAwayFromZero(x_pan_off)
	y_pan_off = math.roundAwayFromZero(y_pan_off)
	new_va.x = math.roundAwayFromZero(self.visible_area.x+x_pan_off)
	new_va.y = math.roundAwayFromZero(self.visible_area.y+y_pan_off)

	if new_va:notIntersectWith(self.page_area) then
		-- view area out of page area, do a page turn
		self:gotoPage(self.current_page + diff)
		-- if we are going back to previous page, reset
		-- view area to bottom of previous page
		if x_pan_off < 0 then
			self.view:PanningUpdate(self.page_area.w, 0)
		elseif y_pan_off < 0 then
			self.view:PanningUpdate(0, self.page_area.h)
		end
		-- reset dim_area
		--self.view.dim_area.h = 0
		--self.view.dim_area.w = 0
		--
	else
		-- not end of page yet, goto next view
		-- adjust panning step according to overlap
		if self.show_overlap_enable then
			if x_pan_off > self.overlap then
				-- moving to next view, move view
				x_pan_off = x_pan_off - self.overlap
			elseif x_pan_off < -self.overlap then
				x_pan_off = x_pan_off + self.overlap
			end
			if y_pan_off > self.overlap then
				y_pan_off = y_pan_off - self.overlap
			elseif y_pan_off < -self.overlap then
				y_pan_off = y_pan_off + self.overlap
			end
			-- we have to calculate again to count into overlap
			new_va.x = math.roundAwayFromZero(self.visible_area.x+x_pan_off)
			new_va.y = math.roundAwayFromZero(self.visible_area.y+y_pan_off)
		end
		-- fit new view area into page area
		new_va:offsetWithin(self.page_area, 0, 0)
		-- calculate panning offsets
		local panned_x = new_va.x - self.visible_area.x
		local panned_y = new_va.y - self.visible_area.y
		-- adjust for crazy float point overflow...
		if math.abs(panned_x) < 1 then
			panned_x = 0
		end
		if math.abs(panned_y) < 1 then
			panned_y = 0
		end
		-- singal panning update
		self.view:PanningUpdate(panned_x, panned_y)
		-- update dime area in ReaderView
		if self.show_overlap_enable then
			self.view.dim_area.h = new_va.h - math.abs(panned_y)
			self.view.dim_area.w = new_va.w - math.abs(panned_x)
			if panned_y < 0 then
				self.view.dim_area.y = new_va.y - panned_y
			else
				self.view.dim_area.y = 0
			end
			if panned_x < 0 then
				self.view.dim_area.x = new_va.x - panned_x
			else
				self.view.dim_area.x = 0
			end
		end
		-- update self.visible_area
		self.visible_area = new_va
	end

	return true
end

function ReaderPaging:onRedrawCurrentPage()
	self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
end
