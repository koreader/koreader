local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local common_exit_menu = {}

function common_exit_menu.table(app)
	local exit_settings = {}
	exit_settings.exit_menu = {
		text = _("Exit"),
		-- submenu entries will be appended by xyz_menu_order_lua
	}
	exit_settings.exit = {
		text = _("Exit"),
		callback = function()
			app:exitOrRestart()
		end,
	}
	exit_settings.restart_koreader = {
		text = _("Restart KOReader"),
		callback = function()
			app:exitOrRestart(function()
				UIManager:restartKOReader()
			end)
		end,
	}
	if not Device:canRestart()  then
		exit_settings.exit_menu = exit_settings.exit
		exit_settings.exit = nil
		exit_settings.restart_koreader = nil
	end

	if Device:canSuspend() then
		exit_settings.sleep = {
			text = _("Sleep"),
			callback = function()
				UIManager:suspend()
			end,
		}
	end
	if Device:canReboot() then
		exit_settings.reboot = {
			text = _("Reboot the device"),
			keep_menu_open = true,
			callback = function()
				UIManager:broadcastEvent(Event:new("Reboot"))
			end
		}
	end
	if Device:canPowerOff() then
		exit_settings.poweroff = {
			text = _("Power off"),
			keep_menu_open = true,
			callback = function()
				UIManager:broadcastEvent(Event:new("PowerOff"))
			end
		}
	end

	return exit_settings
end

return common_exit_menu
