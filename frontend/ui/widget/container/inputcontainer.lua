local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local DEBUG = require("dbg")

--[[
an InputContainer is an WidgetContainer that handles input events

an example for a key_event is this:

	PanBy20 = {
		{ "Shift", Input.group.Cursor },
		seqtext = "Shift+Cursor",
		doc = "pan by 20px",
		event = "Pan", args = 20, is_inactive = true,
	},
	PanNormal = {
		{ Input.group.Cursor },
		seqtext = "Cursor",
		doc = "pan by 10 px", event = "Pan", args = 10,
	},
	Quit = { {"Home"} },

it is suggested to reference configurable sequences from another table
and store that table as configuration setting
--]]
local InputContainer = WidgetContainer:new{
	vertical_align = "top",
}

function InputContainer:_init()
	-- we need to do deep copy here
	local new_key_events = {}
	if self.key_events then
		for k,v in pairs(self.key_events) do
			new_key_events[k] = v
		end
	end
	self.key_events = new_key_events

	local new_ges_events = {}
	if self.ges_events then
		for k,v in pairs(self.ges_events) do
			new_ges_events[k] = v
		end
	end
	self.ges_events = new_ges_events

	if not self.dimen then
		self.dimen = Geom:new{}
	end
end

function InputContainer:paintTo(bb, x, y)
	self.dimen.x = x
	self.dimen.y = y
	if self[1] then
		if self.vertical_align == "center" then
			local content_size = self[1]:getSize()
			self[1]:paintTo(bb, x, y + math.floor((self.dimen.h - content_size.h)/2))
		else
			self[1]:paintTo(bb, x, y)
		end
	end
end

--[[
the following handler handles keypresses and checks if they lead to a command.
if this is the case, we retransmit another event within ourselves
--]]
function InputContainer:onKeyPress(key)
	for name, seq in pairs(self.key_events) do
		if not seq.is_inactive then
			for _, oneseq in ipairs(seq) do
				if key:match(oneseq) then
					local eventname = seq.event or name
					return self:handleEvent(Event:new(eventname, seq.args, key))
				end
			end
		end
	end
end

function InputContainer:onGesture(ev)
	for name, gsseq in pairs(self.ges_events) do
		for _, gs_range in ipairs(gsseq) do
			--DEBUG("gs_range", gs_range)
			if gs_range:match(ev) then
				local eventname = gsseq.event or name
				return self:handleEvent(Event:new(eventname, gsseq.args, ev))
			end
		end
	end
end

return InputContainer
