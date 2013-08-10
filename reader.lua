#!./koreader-base

require "defaults"
package.path = "./frontend/?.lua"
package.cpath = "/usr/lib/lua/?.so"
require "ui/uimanager"
require "ui/widget/filechooser"
require "ui/widget/infomessage"
require "ui/readerui"
require "document/document"
require "settings"
require "dbg"
require "gettext"

Profiler = nil

HomeMenu = InputContainer:new{
	item_table = {},
	key_events = {
		TapShowMenu = { {"Home"}, doc = _("Show Home Menu")},
	},
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

function exitReader()
	if Profiler ~= nil then
		Profiler:stop()
		Profiler:dump("./profile.html")
	end

	G_reader_settings:close()

	input.closeAll()

	if util.isEmulated() == 0 then
		if Device:isKindle3() or (Device:getModel() == "KindleDXG") then
			-- send double menu key press events to trigger screen refresh
			os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")
		end
		if Device:isTouchDevice() and Device.survive_screen_saver then
			-- hack the swipe to unlock screen
			local dev = Device:getTouchInputDev()
			if dev then
				local width, height = Screen:getWidth(), Screen:getHeight()
				input.fakeTapInput(dev,
					math.min(width, height)/2,
					math.max(width, height)-30
				)
			end
		end
	end

	os.exit(0)
end

function HomeMenu:setUpdateItemTable()
	function readHistDir(order_arg, re)
		local pipe_out = io.popen("ls "..order_arg.." -1 ./history")
		for f in pipe_out:lines() do
			table.insert(re, {
				dir = DocSettings:getPathFromHistory(f),
				name = DocSettings:getNameFromHistory(f),
			})
		end
	end

	local hist_sub_item_table = {}
	local last_files = {}
	readHistDir("-c", last_files)
	for _,v in pairs(last_files) do
		table.insert(hist_sub_item_table, {
			text = v.name,
			callback = function()
				showReader(v.dir .. "/" .. v.name)
			end
		})
	end
	table.insert(self.item_table, {
		text = _("Last documents"),
		sub_item_table = hist_sub_item_table,
	})

	table.insert(self.item_table, {
		text = _("Exit"),
		callback = function()
			exitReader()
		end
	})
end

function HomeMenu:onTapShowMenu()
	self.item_table = {}
	self:setUpdateItemTable()

	local menu_container = CenterContainer:new{
		ignore = "height",
		dimen = Screen:getSize(),
	}

	local home_menu = Menu:new{
		show_parent = menu_container,
		title = _("Home menu"),
		item_table = self.item_table,
		width = Screen:getWidth() - 100,
	}

	menu_container[1] = home_menu

	home_menu.close_callback = function ()
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)

	return true
end


function showReader(file, pass)
	local document = DocumentRegistry:openDocument(file)
	if not document then
		UIManager:show(InfoMessage:new{
			text = _("No reader engine for this file")
		})
		return
	end

	G_reader_settings:saveSetting("lastfile", file)
	local reader = ReaderUI:new{
		dialog = readerwindow,
		dimen = Screen:getSize(),
		document = document,
		password = pass
	}
	UIManager:show(reader)
end

function showHomePage(path)
	local exclude_dirs = {"%.sdr$"}

	local HomePage = InputContainer:new{
	}

	local FileManager = FileChooser:new{
		show_parent = HomePage,
		title = _("FileManager"),
		path = path,
		width = Screen:getWidth(),
		height = Screen:getHeight(),
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

	table.insert(HomePage, FileManager)
	table.insert(HomePage, HomeMenu)

	function FileManager:onFileSelect(file)
		showReader(file)
		return true
	end

	function FileManager:onClose()
		exitReader()
		--UIManager:quit()
		return true
	end

	UIManager:show(HomePage)
end



-- option parsing:
longopts = {
	debug = "d",
	profile = "p",
	help = "h",
}

function showusage()
	print(_("usage: ./reader.lua [OPTION] ... path"))
	print(_("Read all the books on your E-Ink reader"))
	print("")
	print(_("-d               start in debug mode"))
	print(_("-p [rows]        enable Lua code profiling"))
	print(_("-h               show this usage help"))
	print("")
	print(_("If you give the name of a directory instead of a file path, a file"))
	print(_("chooser will show up and let you select a file"))
	print("")
	print(_("If you don't pass any path, the last viewed document will be opened"))
	print("")
	print(_("This software is licensed under the GPLv3."))
	print(_("See http://github.com/koreader/kindlepdfviewer for more info."))
	return
end

local argidx = 1
while argidx <= #ARGV do
	local arg = ARGV[argidx]
	argidx = argidx + 1
	if arg == "--" then break end
	-- parse longopts
	if arg:sub(1,2) == "--" then
		local opt = longopts[arg:sub(3)]
		if opt ~= nil then arg = "-"..opt end
	end
	-- code for each option
	if arg == "-h" then
		return showusage()
	elseif arg == "-d" then
		Dbg:turnOn()
	elseif arg == "-p" then
		require "lulip"
		Profiler = lulip:new()
		pcall(function()
			-- set maxrows only if the optional arg is numeric
			Profiler:maxrows(ARGV[argidx] + 0)
			argidx = argidx + 1
		end)
		Profiler:start()
	else
		-- not a recognized option, should be a filename
		argidx = argidx - 1
		break
	end
end

if not Dbg.is_on then
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


if ARGV[argidx] and ARGV[argidx] ~= "" then
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

exitReader()
