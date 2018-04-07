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
        local cmd = "./dropbear -E -P SSH/dropbear.pid"
        cmd = cmd.." -r SSH/dropbear_rsa_host_key"
        cmd = cmd.." -p "..SSH_port
        if allow_blank_password then
            cmd =cmd.." -B"
        end
        os.execute("mkdir SSH")
        os.execute("./dropbearkey -t rsa -f SSH/dropbear_rsa_host_key")
        logger.dbg("[Network] Launching SSH server : "..cmd)
        if os.execute(cmd) == 0 then
            local info = InfoMessage:new{
                    text = "Port: "..SSH_port,
                    timeout = 5,
                    }
            UIManager:show(info)
        else
            local info = InfoMessage:new{
                    text = _("Error"),
                    timeout = 5,
                    }
            UIManager:show(info)
        end
    end

    local stop = function()
        os.execute("cat SSH/dropbear.pid | xargs kill")
        os.execute("rm  SSH/dropbear.pid")
    end

    local start_stop = function()
        print(util.pathExists("SSH/dropbear.pid"))
        if util.pathExists("SSH/dropbear.pid") then
            return  {
                text = _("Stop SSH server"),
                callback = stop,
            }
        else return {
                text = _("Start SSH server"),
                callback = start,
            }       end
    end
    menu_items.SSH = {
        text = _(_("SSH server")),
        sub_item_table = {
            start_stop(),
            {
                text = _("Change SSH port"),
                callback = function()
                    self.dialog = InputDialog:new{
                        title = _("Choose SSH port"),
                        input_type = "number",
                        input_hint = SSH_port,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    enabled = true,
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
                callback = function() allow_blank_password = not allow_blank_password end,
            },
       }
    }
end

return SSH
