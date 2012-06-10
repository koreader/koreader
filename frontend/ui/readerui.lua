require "ui/ui"
require "ui/reader/readerview"
require "ui/reader/readerzooming"
require "ui/reader/readerpanning"
require "ui/reader/readerrotation"
require "ui/reader/readerpaging"
require "ui/reader/readerrolling"
require "ui/reader/readertoc"
require "ui/reader/readermenu"

--[[
This is an abstraction for a reader interface

it works using data gathered from a document interface
]]--

ReaderUI = InputContainer:new{
	key_events = {
		Close = { {"Home"}, doc = "close document", event = "Close" },
		Back = { {"Back"}, doc = "close document", event = "Close" },
	},

	-- our own size
	dimen = Geom:new{ w = 400, h = 600 },
	-- if we have a parent container, it must be referenced for now
	dialog = nil,

	-- the document interface
	document = nil,
}

function ReaderUI:init()
	-- if we are not the top level dialog ourselves, it must be given in the table
	if not self.dialog then
		self.dialog = self
	end
	-- a view container (so it must be child #1!)
	self[1] = ReaderView:new{
		dialog = self.dialog,
		ui = self
	}
	-- rotation controller
	self[2] = ReaderRotation:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	}
	-- Toc menu controller
	self[3] = ReaderToc:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	}
	-- reader menu controller
	self[4] = ReaderMenu:new{
		view = self[1],
		ui = self
	}
	if self.document.info.has_pages then
		-- for page specific controller
		
		-- zooming controller
		local zoomer = ReaderZooming:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, zoomer)
		-- panning controller
		local panner = ReaderPanning:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, panner)
		-- if needed, insert a paging container
		local pager = ReaderPaging:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, pager)
		pager:gotoPage(1)
	else
		local roller = ReaderRolling:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, roller)
		roller:gotoPos(0)
	end
	-- notify childs of dimensions
	self:handleEvent(Event:new("SetDimensions", self.dimen))
end

function ReaderUI:onClose()
	DEBUG("closing reader")
	if self.document then
		self.document:close()
		self.document = false
	end
	UIManager:close(self.dialog)
	return true
end

