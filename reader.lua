#!./kpdfview

package.path = "./frontend/?.lua"
require "ui/ui"
require "ui/readerui"
require "ui/filechooser"
require "ui/infomessage"
require "document/document"

function showReader(file, pass)
	local document = DocumentRegistry:openDocument(file)
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
		document = document,
		password = pass
	}

	readerwindow[1] = reader

	UIManager:show(readerwindow)
end

function showFileManager(path)
	local FileManager = FileChooser:new{
		path = path,
		dimen = Screen:getSize(),
		is_borderless = true,
		filter = function(filename) 
			if DocumentRegistry:getProvider(filename) then
				return true
			end
		end
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



-- option parsing:
longopts = {
	debug = "d",
	help = "h",
}

function showusage()
	print("usage: ./reader.lua [OPTION] ... path")
	print("Read all the books on your E-Ink reader")
	print("")
	print("-d               start in debug mode")
	print("-h               show this usage help")
	print("")
	print("If you give the name of a directory instead of a file path, a file")
	print("chooser will show up and let you select a file")
	print("")
	print("If you don't pass any path, the last viewed document will be opened")
	print("")
	print("This software is licensed under the GPLv3.")
	print("See http://github.com/hwhw/kindlepdfviewer for more info.")
	return
end

if ARGV[1] == "-h" then
	return showusage()
end

local argidx = 1
if ARGV[1] == "-d" then
	argidx = argidx + 1	
else
	DEBUG = function() end
end

if Device:hasNoKeyboard() then
	-- remove menu item shortcut for K4
	Menu.is_enable_shortcut = false
end

-- set up reader's setting: font
G_reader_settings = DocSettings:open(".reader")
fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
	Font.fontmap = fontmap
end
local last_file = G_reader_settings:readSetting("lastfile")

Screen:updateRotationMode()
Screen.native_rotation_mode = Screen.cur_rotation_mode

--@TODO we can read version here, refer to commit in master tree:   (houqp)
--87712cf0e43fed624f8a9f610be42b1fe174b9fe


if ARGV[argidx] then
	if lfs.attributes(ARGV[argidx], "mode") == "directory" then
		showFileManager(ARGV[argidx])
	elseif lfs.attributes(ARGV[argidx], "mode") == "file" then
		showReader(ARGV[argidx])
	end
	UIManager:run()
elseif last_file and lfs.attributes(last_file, "mode") == "file" then
	showReader(last_file)
	UIManager:run()
else
	return showusage()
end


-- @TODO dirty workaround, find a way to force native system poll
-- screen orientation and upside down mode 09.03 2012
Screen:setRotationMode(Screen.native_rotation_mode)

input.closeAll()
if util.isEmulated()==0 then
	os.execute("killall -cont cvm")
	-- send double menu key press events to trigger screen refresh
	os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")
end
