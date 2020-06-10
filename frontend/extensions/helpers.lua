local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local SQ3 = require("lua-ljsqlite3/init")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Font = require("ui/font")
local ConfirmBox = require("ui/widget/confirmbox")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

-- Plugin for global methods
-- Some modules don't use this, but communicate directly with each other by exchanging global variables by triggering events. For an example, search for variable AX_remaining_time.

-- for widgets use :extend instead of :new ?:
local Helpers = WidgetContainer:extend{

	debug_once_used = false,

	file_paths = {},

	garbage = nil,
}

function Helpers:init(ui)
	self.ui = ui
end

function Helpers:getHomeDir()

	local homedir = G_reader_settings:readSetting("home_dir")

	local current_ebook

	if homedir == nil then
		current_ebook = G_reader_settings:readSetting("lastfile")

		if current_ebook ~= nil then
			homedir = string.gsub(current_ebook, '/[- .,:;?!_A-Za-z0-9]+', '')
		end
    end

	return homedir
end

function Helpers:getKoreaderDir()

    local settings_dir = DataStorage:getSettingsDir()

    return string.gsub(settings_dir, '/settings', '')
end

-- use timeout = nil for second argument when calling for no timeout:
function Helpers:alertDebug(message, timeout, dismiss_callback)

	if dismiss_callback == nil then
		UIManager:show(InfoMessage:new { text = message, icon_file = 'resources/info-bug.png', timeout = timeout })

	else
		UIManager:show(InfoMessage:new { text = message, icon_file = 'resources/info-bug.png', timeout = timeout, dismiss_callback = dismiss_callback })
	end
end

function Helpers:alertDebugOnce(message, timeout, dismiss_callback)

	if not self.debug_once_used then

		self:alertDebug(message, timeout, dismiss_callback)

		self.debug_once_used = true
	end
end

-- use timeout = nil for second argument when calling for no timeout:
function Helpers:alertError(message, timeout, dismiss_callback)

	if dismiss_callback == nil then
		UIManager:show(InfoMessage:new { text = message, icon_file = 'resources/info-error.png', timeout = timeout })

	else
		UIManager:show(InfoMessage:new { text = message, icon_file = 'resources/info-error.png', timeout = timeout, dismiss_callback = dismiss_callback })
	end
end

-- use timeout = nil for second argument when calling for no timeout:
function Helpers:alertInfo(message, timeout, dismiss_callback)

	if dismiss_callback == nil then
		UIManager:show(InfoMessage:new { text = message, timeout = timeout })

	else
		UIManager:show(InfoMessage:new { text = message, timeout = timeout, dismiss_callback = dismiss_callback })
	end
end

-- use timeout = nil for second argument when calling for no timeout:
function Helpers:alertNoIcon(message, timeout)

	UIManager:show(InfoMessage:new { text = message, show_icon = false, timeout = timeout })
end

function Helpers:shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = math.random(i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	end
end

function Helpers:split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t, cap)
		end
		last_end = e + 1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

function Helpers:split_path(str)
	return self:split(str, '[\\/]+')
end

function Helpers:table_sort_by_text_prop(subject)

	table.sort(subject, function(v1, v2)
		return v1.text < v2.text
	end)
end

function Helpers:table_sort_alphabetically(subject)

	table.sort(subject, function(v1, v2)
		return v1 < v2
	end)
end

function Helpers:ucfirst(str)
	return (str:gsub("^%l", string.upper))
end

function Helpers:getMiddleDialogWidth()

	local orientation = Screen:getScreenMode()
	local iwidth = (Screen:getWidth() / 2) + 20

	if orientation == 'portrait' then
		iwidth = Screen:getWidth() - 80
	end

	return iwidth
end

function Helpers:getWideDialogWidth()

	local orientation = Screen:getScreenMode()
	local iwidth = Screen:getWidth() - 120

	if orientation == 'portrait' then
		iwidth = Screen:getWidth() - 80
	end

	return iwidth
end

function Helpers:round(x)

	if x % 2 ~= 0.5 then
		return math.floor(x + 0.5)
	end

	return x - 0.5
end

function Helpers:substrCount(subject, needle)
	return select(2, subject:gsub(needle, ""))
end

function Helpers:readSetting(options_file, setting, default)

	if not string.match(options_file, '[.]lua$') then
		options_file = options_file .. '.lua'
	end

	local path = self.file_paths[options_file] or DataStorage:getSettingsDir() .. "/" .. options_file

	self.file_paths[options_file] = path

	local file_handle = LuaSettings:open(path)

	return file_handle:readSetting(setting) or default
end

function Helpers:saveSetting(options_file, setting, value)

	if not string.match(options_file, '[.]lua$') then
		options_file = options_file .. '.lua'
	end

	local path = self.file_paths[options_file] or DataStorage:getSettingsDir() .. "/" .. options_file

	self.file_paths[options_file] = path

	local options_file_handle = LuaSettings:open(path)

	options_file_handle:saveSetting(setting, value)
	options_file_handle:flush()
end

function Helpers:listItemNumber(nr, title)

	return tostring(nr) .. '. ' .. self:removeListItemNumber(title)
end

function Helpers:removeListItemNumber(text)

	return string.gsub(text, '^[0-9]+[.][ ]*', '')
end

function Helpers:confirm(question, callback)

	UIManager:show(ConfirmBox:new {
		text = question,
		ok_text = _("Yes"),
		cancel_text = _("No"),
		ok_callback = function()
			callback()
		end,
	})
end

function Helpers:exists(path)
	return lfs.attributes(path) or false
end

function Helpers:file_get_contents(path)

	if (not self:exists(path)) then

		self:alertError('File ' .. path .. ' does not exist!', 3)

		return false
	end

	local file = io.open(path, "r")

	local content = file:read("*all")
	file:close()

	return content
end

function Helpers:file_put_contents(path, content)

	local target = io.open(path, "w")

	if target then
		target:write(content)
		target:close()
	else
		self:alertError('File ' .. path .. ' does not exist!', 3)
	end
end

return Helpers
