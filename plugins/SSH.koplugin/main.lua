local Device =  require("device")
local InfoMessage = require("ui/widget/infomessage")  -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local SSH = WidgetContainer:new{
    name = 'SSH',
    is_doc_only = false,
}

function SSH:init()
    self.ui.menu:registerToMainMenu(self)
end

function SSH:addToMainMenu(menu_items)
    local SSH_port = G_reader_settings:readSetting("SSH_port") or "2222"
    local allow_blank_password = false
    local start = function(menu)
        local cmd = string.format("%s %s %s %s %s %s",
            "./dropbear",
            "-E", "-r SSH/dropbear_rsa_host_key",
            "-p", SSH_port,
            "-P /tmp/dropbear.pid")
         if allow_blank_password then
            cmd = string.format("%s %s", cmd, "-B")
        end
        os.execute("mkdir SSH")
        os.execute("./dropbearkey -t rsa -f SSH/dropbear_rsa_host_key")
        logger.dbg("[Network] Launching SSH server : ", cmd)
        if os.execute(cmd) == 0 then
            local info = InfoMessage:new{
                    timeout = 5,
                    text = string.format("%s %s \n %s",
                        "SSH port: ", SSH_port,
                        Device.retrieveNetworkInfo and Device:retrieveNetworkInfo() or _("Could not retrieve network info.")),
            }
            UIManager:show(info)
        else
            local info = InfoMessage:new{
                    timeout = 5,
                    text = _("Error"),
            }
            UIManager:show(info)
        end
    end

    local isRunning = function()
        return util.pathExists("/tmp/dropbear.pid")
    end

    local stop = function()
        os.execute("cat /tmp/dropbear.pid | xargs kill")
    end

    menu_items.SSH = {
        text = _(_("SSH server")),
        sub_item_table = {
            {
                text = _("Start SSH server"),
                callback = start,
                enabled_func = function() return not isRunning() end,
            },
            {
                text = _("Stop SSH server"),
                callback = stop,
                enabled_func = isRunning,
            },
            {
                text = _("Change SSH port"),
                enabled_func = function() return not isRunning() end,
                callback = function()
                    self.dialog = InputDialog:new{
                        title = _("Choose SSH port"),
                        input_type = "number",
                        input_hint = SSH_port,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(self.dialog)
                                    end,
                                },
                                {
                                    is_enter_default = true,
                                    text = _("Save"),
                                    callback = function()
                                        local value
                                        value  = tonumber(self.dialog:getInputText())
                                        if value then
                                            SSH_port = value
                                            G_reader_settings:saveSetting("SSH_port",SSH_port)
                                            UIManager:close(self.dialog)
                                        end
                                    end
                                },
                            },
                        },
                    }
                    UIManager:show(self.dialog)
                    self.dialog:onShowKeyboard()
                end
            },
            {
                text = _("Allow blank password"),
                checked_func = function() return allow_blank_password end,
                enabled_func = function() return not isRunning() end,
                callback = function() allow_blank_password = not allow_blank_password end,
            },
       }
    }
end

return SSH
