require "ui/ui"
require "ui/reader/readerview"
require "ui/reader/readerzooming"
require "ui/reader/readerpanning"
require "ui/reader/readerrotation"
require "ui/reader/readerpaging"
require "ui/reader/readerrolling"
require "ui/reader/readertoc"
require "ui/reader/readerfont"
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

	-- initial page or percent inside document on opening
	start_pos = nil,
	-- password for document unlock
	password = nil,
}

function ReaderUI:init()
	-- if we are not the top level dialog ourselves, it must be given in the table
	if not self.dialog then
		self.dialog = self
	end

	self.doc_settings = DocSettings:open(self.document.file)

	-- a view container (so it must be child #1!)
	self[1] = ReaderView:new{
		dialog = self.dialog,
		dimen = self.dimen,
		ui = self,
		document = self.document,
	}
	-- rotation controller
	self[2] = ReaderRotation:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	}
	-- reader menu controller
	self[3] = ReaderMenu:new{
		view = self[1],
		ui = self
	}
	self.menu = self[3] -- hold reference to menu widget
	-- Toc menu controller
	self[4] = ReaderToc:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	}

	if self.document.info.has_pages then
		-- for page specific controller
		
		-- if needed, insert a paging container
		local pager = ReaderPaging:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, pager)
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
	else
		-- rolling controller
		local roller = ReaderRolling:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, roller)
		--if not self.start_pos then
			--self.start_pos = 0
		--end
		--roller:gotoPercent(self.start_pos)
		-- font menu
		local font_menu = ReaderFont:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, font_menu)
	end
	--DEBUG(self.doc_settings)
	-- we only read settings after all the widgets are initialized
	self:handleEvent(Event:new("ReadSettings", self.doc_settings))
	-- notify childs of dimensions
	self:handleEvent(Event:new("SetDimensions", self.dimen))
end

function ReaderUI:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderUI:onClose()
	DEBUG("closing reader")
	self:handleEvent(Event:new("CloseDocument"))
	self.doc_settings:flush()
	if self.document ~= nil then
		self.document:close()
		self.document = nil
		self.start_pos = nil
	end
	UIManager:close(self.dialog)
	return true
end

