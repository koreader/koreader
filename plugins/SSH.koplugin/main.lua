local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device =  require("device")
local InfoMessage = require("ui/widget/infomessage")  -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

-- This plugin uses a patched dropbear that adds two things:
-- the -n option to bypass password checks
-- reads the authorized_keys file from the relative path: settings/SSH/authorized_keys

local path = DataStorage:getFullDataDir()
if not util.pathExists("dropbear") then
    return { disabled = true, }
end

local SSH = WidgetContainer:new{
    name = "SSH",
    is_doc_only = false,
}

function SSH:init()
    self.SSH_port = G_reader_settings:readSetting("SSH_port") or "2222"
    self.allow_no_password = false
    self.ui.menu:registerToMainMenu(self)
end

function SSH:start()
    local cmd = string.format("%s %s %s %s%s %s",
        "./dropbear",
        "-E",
        "-R",
        "-p", self.SSH_port,
        "-P /tmp/dropbear_koreader.pid")
     if self.allow_no_password then
        cmd = string.format("%s %s", cmd, "-n")
    end

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.SSH_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.SSH_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
    -- An SSH/telnet server of course needs to be able to manipulate pseudoterminals...
    -- Kobo's init scripts fail to set this up...
    if Device:isKobo() then
        os.execute([[if [ ! -d "/dev/pts" ] ; then
            mkdir -p /dev/pts
            mount -t devpts devpts /dev/pts
            fi]])
    end

    if not util.pathExists(path.."/settings/SSH/") then
        os.execute("mkdir "..path.."/settings/SSH")
    end
    logger.dbg("[Network] Launching SSH server : ", cmd)
    if os.execute(cmd) == 0 then
        local info = InfoMessage:new{
                timeout = 10,
                -- @translators: %1 is the SSH port, %2 is the network info.
                text = T(_("SSH port: %1\n%2"),
                    self.SSH_port,
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
    return util.pathExists("/tmp/dropbear_koreader.pid")
end

function SSH:stop()
    os.execute("cat /tmp/dropbear_koreader.pid | xargs kill")

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.SSH_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.SSH_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
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
    menu_items.ssh = {
        text = _("SSH server"),
        sub_item_table = {
            {
                text = _("Start SSH server"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:start()
                    -- sleeping might not be needed, but it gives the feeling
                    -- something has been done and feedback is accurate
                    ffiutil.sleep(1)
                    touchmenu_instance:updateItems()
                end,
                enabled_func = function() return not self:isRunning() end,
            },
            {
                text = _("Stop SSH server"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:stop()
                    -- sleeping might not be needed, but it gives the feeling
                    -- something has been done and feedback is accurate
                    ffiutil.sleep(1)
                    touchmenu_instance:updateItems()
                end,
                enabled_func = function() return self:isRunning() end,
            },
            {
                text = _("Change SSH port"),
                keep_menu_open = true,
                enabled_func = function() return not self:isRunning() end,
                callback = function() return self:show_port_dialog() end,
            },
            {
                text = _("Login without password (DANGEROUS)"),
                checked_func = function() return self.allow_no_password end,
                enabled_func = function() return not self:isRunning() end,
                callback = function() self.allow_no_password = not self.allow_no_password end,
            },
            {
                text = _("SSH public key"),
                keep_menu_open = true,
                callback = function()
                    local info = InfoMessage:new{
                        timeout = 60,
                        text = T(_("Put your public SSH keys in %1"), BD.filepath(path.."/settings/SSH/authorized_keys")),
                    }
                    UIManager:show(info)
                end,
            },
       }
    }
end

return SSH
