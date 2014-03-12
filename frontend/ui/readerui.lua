local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderView = require("ui/reader/readerview")
local ReaderZooming = require("ui/reader/readerzooming")
local ReaderPanning = require("ui/reader/readerpanning")
local ReaderRotation = require("ui/reader/readerrotation")
local ReaderPaging = require("ui/reader/readerpaging")
local ReaderRolling = require("ui/reader/readerrolling")
local ReaderToc = require("ui/reader/readertoc")
local ReaderBookmark = require("ui/reader/readerbookmark")
local ReaderFont = require("ui/reader/readerfont")
local ReaderTypeset = require("ui/reader/readertypeset")
local ReaderMenu = require("ui/reader/readermenu")
local ReaderGoto = require("ui/reader/readergoto")
local ReaderConfig = require("ui/reader/readerconfig")
local ReaderCropping = require("ui/reader/readercropping")
local ReaderKoptListener = require("ui/reader/readerkoptlistener")
local ReaderCoptListener = require("ui/reader/readercoptlistener")
local ReaderHinting = require("ui/reader/readerhinting")
local ReaderHighlight = require("ui/reader/readerhighlight")
local ReaderScreenshot = require("ui/reader/readerscreenshot")
local ReaderFrontLight = require("ui/reader/readerfrontlight")
local ReaderDictionary = require("ui/reader/readerdictionary")
local ReaderHyphenation = require("ui/reader/readerhyphenation")
local ReaderActivityIndicator = require("ui/reader/readeractivityindicator")
local ReaderLink = require("ui/reader/readerlink")

--[[
This is an abstraction for a reader interface

it works using data gathered from a document interface
]]--

local ReaderUI = InputContainer:new{
	key_events = {
		Close = { { "Home" },
			doc = _("close document"), event = "Close" },
	},
	active_widgets = {},

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

	postInitCallback = nil,
}

function ReaderUI:init()
	self.postInitCallback = {}
	-- if we are not the top level dialog ourselves, it must be given in the table
	if not self.dialog then
		self.dialog = self
	end

	if Device:hasKeyboard() then
		self.key_events.Back = {
			{ "Back" }, doc = _("close document"),
			event = "Close" }
	end

	self.doc_settings = DocSettings:open(self.document.file)

	-- a view container (so it must be child #1!)
	self[1] = ReaderView:new{
		dialog = self.dialog,
		dimen = self.dimen,
		ui = self,
		document = self.document,
	}
	-- reader menu controller
	-- hold reference to menu widget
	self.menu = ReaderMenu:new{
		view = self[1],
		ui = self
	}
	-- link
	table.insert(self, ReaderLink:new{
		dialog = self.dialog,
		view = self[1],
		ui = self,
		document = self.document,
	})
	-- text highlight
	table.insert(self, ReaderHighlight:new{
		dialog = self.dialog,
		view = self[1],
		ui = self,
		document = self.document,
	})
	-- menu widget should be registered after link widget and highlight widget
	-- so that taps on link and highlight areas won't popup reader menu
	table.insert(self, self.menu)
	-- rotation controller
	table.insert(self, ReaderRotation:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	})
	-- Table of content controller
	-- hold reference to bm widget
	self.toc = ReaderToc:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	}
	table.insert(self, self.toc)
	-- bookmark controller
	table.insert(self, ReaderBookmark:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	})
	-- reader goto controller
	table.insert(self, ReaderGoto:new{
		dialog = self.dialog,
		view = self[1],
		ui = self,
		document = self.document,
	})
	-- dictionary
	table.insert(self, ReaderDictionary:new{
		dialog = self.dialog,
		view = self[1],
		ui = self,
		document = self.document,
	})
	-- screenshot controller
	table.insert(self.active_widgets, ReaderScreenshot:new{
		dialog = self.dialog,
		view = self[1],
		ui = self
	})
	-- frontlight controller
	if Device:hasFrontlight() then
		table.insert(self, ReaderFrontLight:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
	end
	-- configuable controller
	if self.document.info.configurable then
		-- config panel controller
		table.insert(self, ReaderConfig:new{
			configurable = self.document.configurable,
			options = self.document.options,
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
		if not self.document.info.has_pages then
			-- cre option controller
			table.insert(self, ReaderCoptListener:new{
				dialog = self.dialog,
				view = self[1],
				ui = self,
				document = self.document,
			})
		end
	end
	-- for page specific controller
	if self.document.info.has_pages then
		-- cropping controller
		table.insert(self, ReaderCropping:new{
			dialog = self.dialog,
			view = self[1],
			ui = self,
			document = self.document,
		})
		-- paging controller
		table.insert(self, ReaderPaging:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
		-- zooming controller
		local zoom = ReaderZooming:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, zoom)
		-- panning controller
		table.insert(self, ReaderPanning:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
		-- hinting controller
		table.insert(self, ReaderHinting:new{
			dialog = self.dialog,
			zoom = zoom,
			view = self[1],
			ui = self,
			document = self.document,
		})
	else
		-- make sure we load document first before calling any callback
		table.insert(self.postInitCallback, function()
			self.document:loadDocument()
		end)
		-- typeset controller
		table.insert(self, ReaderTypeset:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
		-- font menu
		self.font = ReaderFont:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, self.font) -- hold reference to font menu
		-- hyphenation menu
		self.hyphenation = ReaderHyphenation:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		}
		table.insert(self, self.hyphenation) -- hold reference to hyphenation menu
		-- rolling controller
		table.insert(self, ReaderRolling:new{
			dialog = self.dialog,
			view = self[1],
			ui = self
		})
	end
	-- configuable controller
	if self.document.info.configurable then
		if self.document.info.has_pages then
			-- kopt option controller
			table.insert(self, ReaderKoptListener:new{
				dialog = self.dialog,
				view = self[1],
				ui = self,
				document = self.document,
			})
		end
		-- activity indicator
		table.insert(self, ReaderActivityIndicator:new{
			dialog = self.dialog,
			view = self[1],
			ui = self,
			document = self.document,
		})
	end
	--DEBUG(self.doc_settings)
	-- we only read settings after all the widgets are initialized
	self:handleEvent(Event:new("ReadSettings", self.doc_settings))

	for _,v in ipairs(self.postInitCallback) do
		v()
	end
end

function ReaderUI:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderUI:saveSettings()
	self:handleEvent(Event:new("SaveSettings"))
	self.doc_settings:flush()
end

function ReaderUI:onClose()
	DEBUG("closing reader")
	self:saveSettings()
	if self.document ~= nil then
		self.document:close()
		self.document = nil
		self.start_pos = nil
	end
	UIManager:close(self.dialog)
	return true
end

return ReaderUI
