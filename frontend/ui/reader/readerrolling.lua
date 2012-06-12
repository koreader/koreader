require "ui/reader/readerpanning"

ReaderRolling = InputContainer:new{
	key_events = {
		GotoNextView = { {Input.group.PgFwd}, doc = "go to next view", event = "GotoViewRel", args = 1 },
		GotoPrevView = { {Input.group.PgBack}, doc = "go to previous view", event = "GotoViewRel", args = -1 },

		MoveUp = { {"Up"}, doc = "move view up", event = "Panning", args = {0, -1} },
		MoveDown = { {"Down"}, doc = "move view down", event = "Panning", args = {0,  1} },

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

	old_doc_height = nil,
	current_pos = 0,
	doc_height = nil,
	panning_steps = ReaderPanning.panning_steps,
}

function ReaderRolling:init()
	self.doc_height = self.ui.document.info.doc_height
	self.old_doc_height = self.doc_height
end

function ReaderRolling:onPosUpdate(new_pos)
	self.current_pos = new_pos
end

function ReaderRolling:gotoPos(new_pos)
	if new_pos == self.current_pos then return end
	if new_pos < 0 then new_pos = 0 end
	if new_pos > self.doc_height then new_pos = self.doc_height end
	self.ui:handleEvent(Event:new("PosUpdate", new_pos))
end

function ReaderRolling:gotoPercent(new_percent)
	self:gotoPos(new_percent * self.doc_height / 10000)
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

function ReaderRolling:onGotoPercent(percent)
	DEBUG("goto document offset in percent:", percent)
	self:gotoPercent(percent)
	return true
end

function ReaderRolling:onGotoViewRel(diff)
	DEBUG("goto relative screen:", diff)
	self:gotoPos(self.current_pos + diff * self.ui.dimen.h)
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
