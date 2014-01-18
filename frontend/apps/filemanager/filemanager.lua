local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local DocumentRegistry = require("document/documentregistry")
local TextWidget = require("ui/widget/textwidget")
local FileChooser = require("ui/widget/filechooser")
local VerticalSpan = require("ui/widget/verticalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local Input = require("ui/input")
local Font = require("ui/font")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")

local FileDialog = InputContainer:new{
	buttons = nil,
	tap_close_callback = nil,
}

function FileDialog:init()
	if Device:hasKeyboard() then
		self.key_events = {
			AnyKeyPressed = { { Input.group.Any },
				seqtext = "any key", doc = _("close dialog") }
		}
	else
		self.ges_events.TapClose = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				}
			}
		}
	end
	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			ButtonTable:new{
				width = Screen:getWidth()*0.9,
				buttons = self.buttons,
			},
			background = 0,
			bordersize = 2,
			radius = 7,
			padding = 2,
		}
	}
end

function FileDialog:onTapClose()
	UIManager:close(self)
	if self.tap_close_callback then
		self.tap_close_callback()
	end
	return true
end

local FileManager = InputContainer:extend{
	title = _("FileManager"),
	width = Screen:getWidth(),
	height = Screen:getHeight(),
	root_path = lfs.currentdir(),
	-- our own size
	dimen = Geom:new{ w = 400, h = 600 },
	onExit = function() end,
}

function FileManager:init()
	local exclude_dirs = {"%.sdr$"}

	self.show_parent = self.show_parent or self

	self.banner = VerticalGroup:new{
		TextWidget:new{
			face = Font:getFace("tfont", 24),
			text = self.title,
		},
		VerticalSpan:new{ width = Screen:scaleByDPI(10) }
	}
	
	local g_show_hidden = G_reader_settings:readSetting("show_hidden")
	local show_hidden = g_show_hidden == nil and DSHOWHIDDENFILES or g_show_hidden
	local file_chooser = FileChooser:new{
		-- remeber to adjust the height when new item is added to the group
		path = self.root_path,
		show_parent = self.show_parent,
		show_hidden = show_hidden,
		height = Screen:getHeight() - self.banner:getSize().h,
		is_popout = false,
		is_borderless = true,
		has_close_button = true,
		dir_filter = function(dirname)
			for _, pattern in ipairs(exclude_dirs) do
				if dirname:match(pattern) then return end
			end
			return true
		end,
		file_filter = function(filename)
			if DocumentRegistry:getProvider(filename) then
				return true
			end
		end
	}
	self.file_chooser = file_chooser

	function file_chooser:onFileSelect(file)
		showReaderUI(file)
		return true
	end
	
	local copyFile = function(file) self:copyFile(file) end
	local pasteHere = function(file) self:pasteHere(file) end
	local cutFile = function(file) self:cutFile(file) end
	local deleteFile = function(file) self:deleteFile(file) end
	local fileManager = self
	
	function file_chooser:onFileHold(file)
		--DEBUG("hold file", file)
		self.file_dialog = FileDialog:new{
			buttons = {
				{
					{
						text = _("Copy"),
						callback = function()
							copyFile(file)
							UIManager:close(self.file_dialog)
						end,
					},
					{
						text = _("Paste"),
						enabled = fileManager.clipboard and true or false,
						callback = function()
							pasteHere(file)
							self:changeToPath(util.realpath(file):match("(.*/)"))
							UIManager:close(self.file_dialog)
						end,
					},
				},
				{
					{
						text = _("Cut"),
						callback = function()
							cutFile(file)
							UIManager:close(self.file_dialog)
						end,
					},
					{
						text = _("Delete"),
						callback = function()
							local path = util.realpath(file)
							deleteFile(file)
							self:changeToPath(path:match("(.*/)"))
							UIManager:close(self.file_dialog)
						end,
					},
				},
			},
		}
		UIManager:show(self.file_dialog)
		return true
	end

	self.layout = VerticalGroup:new{
		self.banner,
		file_chooser,
	}

	local fm_ui = FrameContainer:new{
		padding = 0,
		bordersize = 0,
		background = 0,
		self.layout,
	}

	self[1] = fm_ui

	self.menu = FileManagerMenu:new{
		ui = self
	}
	table.insert(self, self.menu)
	table.insert(self, FileManagerHistory:new{
		ui = self,
		menu = self.menu
	})

	self:handleEvent(Event:new("SetDimensions", self.dimen))
end

function FileManager:toggleHiddenFiles()
	self.file_chooser:toggleHiddenFiles()
	G_reader_settings:saveSetting("show_hidden", self.file_chooser.show_hidden)
end

function FileManager:onClose()
	UIManager:close(self)
	if self.onExit then
		self:onExit()
	end
	return true
end

function FileManager:copyFile(file)
	self.cutfile = false
	self.clipboard = file
end

function FileManager:cutFile(file)
	self.cutfile = true
	self.clipboard = file
end

function FileManager:pasteHere(file)
	if self.clipboard then
		local program = self.cutfile and "mv " or "cp -r "
		os.execute(program..util.realpath(self.clipboard).." "..util.realpath(file):match("(.*/)"))
	end
end

function FileManager:deleteFile(file)
	local program = "rm -r "
	os.execute(program..util.realpath(file))
end

return FileManager
