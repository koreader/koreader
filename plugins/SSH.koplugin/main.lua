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
    self.SSH_port = G_reader_settings:readSetting("SSH_port") or "2222"
    self.allow_blank_password = false
    self.ui.menu:registerToMainMenu(self)
end

function SSH:start()
    local cmd = string.format("%s %s %s %s %s %s",
        "./dropbear",
        "-E", "-r SSH/dropbear_rsa_host_key",
        "-p", self.SSH_port,
        "-P /tmp/dropbear.pid")
     if self.allow_blank_password then
        cmd = string.format("%s %s", cmd, "-B")
    end
    os.execute("mkdir SSH")
    os.execute("./dropbearkey -t rsa -f SSH/dropbear_rsa_host_key")
    logger.dbg("[Network] Launching SSH server : ", cmd)
    if os.execute(cmd) == 0 then
        local info = InfoMessage:new{
                timeout = 5,
                text = string.format("%s %s \n %s",
                    "SSH port: ", self.SSH_port,
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

function SSH:isRunning()
    return util.pathExists("/tmp/dropbear.pid")
end

function SSH:stop()
    os.execute("cat /tmp/dropbear.pid | xargs kill")
end

function SSH:show_port_dialog()
    self.port_dialog = InputDialog:new{
        title = _("Choose SSH port"),
        input = self.SSH_port,
        input_type = "number",
        input_hint = self.SSH_port,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.port_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value  = tonumber(self.port_dialog:getInputText())
                        if value then
                            self.SSH_port = value
                            G_reader_settings:saveSetting("SSH_port", self.SSH_port)
                            UIManager:close(self.port_dialog)
                        end
                    end
                },
            },
        },
    }
    UIManager:show(self.port_dialog)
    self.port_dialog:onShowKeyboard()
end

function SSH:addToMainMenu(menu_items)
    menu_items.SSH = {
        text = _("SSH server"),
        sub_item_table = {
            {
                text = _("Start SSH server"),
                callback = function() return self:start() end,
                enabled_func = function() return not self:isRunning() end,
            },
            {
                text = _("Stop SSH server"),
                callback = self.stop,
                enabled_func = self.isRunning,
            },
            {
                text = _("Change SSH port"),
                enabled_func = function() return not self:isRunning() end,
                callback = function() return self:show_port_dialog() end,
            },
            {
                text = _("Allow blank password"),
                checked_func = function() return self.allow_blank_password end,
                enabled_func = function() return not self:isRunning() end,
                callback = function() self.allow_blank_password = not self.allow_blank_password end,
            },
       }
    }
end

return SSH
