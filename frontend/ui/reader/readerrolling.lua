require "ui/reader/readerpanning"

ReaderRolling = InputContainer:new{
	old_doc_height = nil,
	current_pos = 0,
	doc_height = nil,
	panning_steps = ReaderPanning.panning_steps,
	show_overlap_enable = true,
	overlap = 20,
}

function ReaderRolling:init()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapForward = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = Screen:getWidth()/2,
						y = Screen:getHeight()/2,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			TapBackward = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, 
						y = Screen:getHeight()/2,
						w = Screen:getWidth()/2,
						h = Screen:getHeight()/2,
					}
				}
			}
		}
	else
		self.key_events = {
			GotoNextView = {
				{ Input.group.PgFwd },
				doc = "go to next view",
				event = "GotoViewRel", args = 1
			},
			GotoPrevView = {
				{ Input.group.PgBack },
				doc = "go to previous view",
				event = "GotoViewRel", args = -1
			},
			MoveUp = {
				{ "Up" },
				doc = "move view up",
				event = "Panning", args = {0, -1}
			},
			MoveDown = {
				{ "Down" },
				doc = "move view down",
				event = "Panning", args = {0,  1}
			},
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

	self.doc_height = self.ui.document.info.doc_height
	self.old_doc_height = self.doc_height
end

function ReaderRolling:onReadSettings(config)
	local soe = config:readSetting("show_overlap_enable")
	if not soe then
		self.show_overlap_enable = soe
	end
	self:gotoPercent(config:readSetting("last_percent") or 0)
end

function ReaderRolling:onCloseDocument()
	self.ui.doc_settings:saveSetting("last_percent", 
		10000 * self.current_pos / self.doc_height)
end

function ReaderRolling:onTapForward()
	self:onGotoViewRel(1)
	return true
end

function ReaderRolling:onTapBackward()
	self:onGotoViewRel(-1)
	return true
end

function ReaderRolling:onPosUpdate(new_pos)
	self.current_pos = new_pos
end

function ReaderRolling:onGotoPercent(percent)
	DEBUG("goto document offset in percent:", percent)
	self:gotoPercent(percent)
	return true
end

function ReaderRolling:onGotoViewRel(diff)
	DEBUG("goto relative screen:", diff)
	local pan_diff = diff * self.ui.dimen.h
	if self.ui.document.view_mode ~= "page" and self.show_overlap_enable then
		if pan_diff > self.overlap then
			pan_diff = pan_diff - self.overlap
		elseif pan_diff < -self.overlap then
			pan_diff = pan_diff + self.overlap
		end
	end
	self:gotoPos(self.current_pos + pan_diff)
	return true
end

function ReaderRolling:onPanning(args, key)
	local _, dy = unpack(args)
	DEBUG("key =", key)
	self:gotoPos(self.current_pos + dy * self.panning_steps.normal)
	return true
end

function ReaderRolling:onZoom()
	--@TODO re-read doc_height info after font or lineheight changes  05.06 2012 (houqp)
	self:onUpdatePos()
end

-- remember to signal this event the document has been zoomed,
-- font has been changed, or line height has been changed.
function ReaderRolling:onUpdatePos()
	-- reread document height
	self.ui.document:_readMetadata()
	-- update self.current_pos if the height of document has been changed.
	if self.old_doc_height ~= self.ui.document.info.doc_height then
		self:gotoPos(self.current_pos * 
			(self.ui.document.info.doc_height - self.dialog.dimen.h) / 
			(self.old_doc_height - self.dialog.dimen.h))
		self.old_doc_height = self.ui.document.info.doc_height
	end
	return true
end

function ReaderRolling:gotoPos(new_pos)
	if new_pos == self.current_pos then return end
	if new_pos < 0 then new_pos = 0 end
	if new_pos > self.doc_height then new_pos = self.doc_height end
	-- adjust dim_area according to new_pos
	if self.ui.document.view_mode ~= "page" and self.show_overlap_enable then
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

function ReaderRolling:gotoPercent(new_percent)
	self:gotoPos(new_percent * self.doc_height / 10000)
end


