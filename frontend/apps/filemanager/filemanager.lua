local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local FileChooser = require("ui/widget/filechooser")
local VerticalSpan = require("ui/widget/verticalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local Font = require("ui/font")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local DocumentRegistry = require("document/documentregistry")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local _ = require("gettext")

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

	local file_chooser = FileChooser:new{
		-- remeber to adjust the height when new item is added to the group
		path = self.root_path,
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
end

function FileManager:onClose()
	UIManager:close(self)
	if self.onExit then
		self:onExit()
	end
	return true
end

return FileManager
