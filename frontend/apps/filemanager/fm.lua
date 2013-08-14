require "ui/widget/filechooser"
require "apps/filemanager/fmhistory"
require "apps/filemanager/fmmenu"


FileManager = InputContainer:extend{
	title = _("FileManager"),
	width = Screen:getWidth(),
	height = Screen:getHeight(),
	root_path = './',
	-- our own size
	dimen = Geom:new{ w = 400, h = 600 },
	onExit = function() end,
}

function FileManager:init()
	local exclude_dirs = {"%.sdr$"}

	self.show_parent = self.show_parent or self

	local file_chooser = FileChooser:new{
		_name = 'fuck',
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

	function file_chooser:onFileSelect(file)
		showReaderUI(file)
		return true
	end

	self.banner = FrameContainer:new{
		padding = 0,
		bordersize = 0,
		TextWidget:new{
			face = Font:getFace("tfont", 24),
			text = self.title,
		}
	}

	self.layout = VerticalGroup:new{
		_name = 'fm',
		self.banner,
		file_chooser,
	}

	local fm_ui = FrameContainer:new{
		padding = 0,
		bordersize = 0,
		padding = self.padding,
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


function FileManager:onClose()
	UIManager:close(self)
	if self.onExit then
		self:onExit()
	end
	return true
end
