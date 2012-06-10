package.path = "./frontend/?.lua"
require "ui/ui"
require "ui/readerui"
require "ui/filechooser"
require "ui/infomessage"
require "document/document"

function showReader(file)
	local document = DocumentRegistry:getProvider(file)
	if not document then
		UIManager:show(InfoMessage:new{ text = "No reader engine for this file" })
		return
	end

	local readerwindow = FrameContainer:new{
		dimen = Screen:getSize(),
		background = 0,
		margin = 0,
		padding = 0,
		bordersize = 0
	}
	local reader = ReaderUI:new{
		dialog = readerwindow,
		dimen = Screen:getSize(),
		document = document
	}
	readerwindow[1] = reader

	UIManager:show(readerwindow)
end

function showFileManager(path)
	local FileManager = FileChooser:new{
		path = path,
		dimen = Screen:getSize(),
		is_borderless = true
	}

	function FileManager:onFileSelect(file)
		showReader(file)
		return true
	end

	function FileManager:onClose()
		UIManager:quit()
		return true
	end

	UIManager:show(FileManager)
end

showFileManager(".")

UIManager:run()
