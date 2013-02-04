#!./kpdfview

package.path = "./frontend/?.lua"
require "ui/ui"
require "ui/readerui"
require "ui/filechooser"
require "ui/infomessage"
require "ui/button"
require "document/document"



HomeMenu = InputContainer:new{
	item_table = {},
	ges_events = {
		TapShowMenu = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = 25,
				}
			}
		},
	},
}

function HomeMenu:setUpdateItemTable()
	table.insert(self.item_table, {
		text = "Exit",
		callback = function()
			os.exit(0)
		end
	})
end

function HomeMenu:onTapShowMenu()
	if #self.item_table == 0 then
		self:setUpdateItemTable()
	end

	local home_menu = Menu:new{
		title = "Home menu",
		item_table = self.item_table,
		width = Screen:getWidth() - 100,
	}

	local menu_container = CenterContainer:new{
		ignore = "height",
		dimen = Screen:getSize(),
		home_menu,
	}
	home_menu.close_callback = function () 
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)

	return true
end


function showReader(file, pass)
	local document = DocumentRegistry:openDocument(file)
	if not document then
		UIManager:show(InfoMessage:new{ text = "No reader engine for this file" })
		return
	end

	local reader = ReaderUI:new{
		dialog = readerwindow,
		dimen = Screen:getSize(),
		document = document,
		password = pass
	}
	UIManager:show(reader)
end

function showHomePage(path)
	local FileManager = FileChooser:new{
		title = "FileManager",
		path = path,
		width = Screen:getWidth(),
		height = Screen:getHeight(),
		is_borderless = true,
		has_close_button = false,
		filter = function(filename) 
			if DocumentRegistry:getProvider(filename) then
				return true
			end
		end
	}

	local HomePage = InputContainer:new{
			FileManager,
			HomeMenu,
	}

	function FileManager:onFileSelect(file)
		showReader(file)
		return true
	end

	function FileManager:onClose()
		--UIManager:quit()
		return true
	end

	UIManager:show(HomePage)
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


--@TODO we can read version here, refer to commit in master tree:   (houqp)
--87712cf0e43fed624f8a9f610be42b1fe174b9fe


if ARGV[argidx] then
	if lfs.attributes(ARGV[argidx], "mode") == "directory" then
		showHomePage(ARGV[argidx])
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

input.closeAll()

if util.isEmulated()==0 then
	if Device:isKindle3() or (Device:getModel() == "KindleDXG") then
		-- send double menu key press events to trigger screen refresh
		os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")
	end
end
