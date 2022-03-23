local BD = require("ui/bidi")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local JoplinExporter = require("formats/base"):new{
    name = "joplin",
    is_remote = true,
}

function JoplinExporter:isEnabled()
    return self.settings.enabled and self.settings.ip and self.settings.port and self.settings.token
end

function JoplinExporter:toggleEnabled()
    if not self.settings.ip or not self.settings.port or not self.settings.token then return end
    self.settings.enabled = not self.settings.enabled
    self:saveSettings()
end

function JoplinExporter:getMenuTable()
    return {
        text = _("Joplin") ,
        checked_func = function() return self:isEnabled() end,
        sub_item_table ={
            {
                text = _("Set Joplin IP and Port"),
                keep_menu_open = true,
                callback = function()
                    local MultiInputDialog = require("ui/widget/multiinputdialog")
                    local url_dialog
                    url_dialog = MultiInputDialog:new{
                        title = _("Set Joplin IP and port number"),
                        fields = {
                            {
                                text = self.settings.ip,
                                input_type = "string"
                            },
                            {
                                text = self.settings.port,
                                input_type = "number"
                            }
                        },
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(url_dialog)
                                    end
                                },
                                {
                                    text = _("OK"),
                                    callback = function()
                                        local fields = url_dialog:getFields()
                                        local ip = fields[1]
                                        local port = tonumber(fields[2])
                                        if ip ~= "" then
                                            if port and port < 65355 then
                                                self.settings.ip = ip
                                                self.settings.port = port
                                                self:saveSettings()
                                            end
                                        end
                                        UIManager:close(url_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(url_dialog)
                    url_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Set authorization token"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new{
                        title = _("Set authorization token for Joplin"),
                        input = self.settings.token,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(auth_dialog)
                                    end
                                },
                                {
                                    text = _("Set token"),
                                    callback = function()
                                        self.settings.token = auth_dialog:getInputText()
                                        self:saveSettings()
                                        UIManager:close(auth_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(auth_dialog)
                    auth_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Export to Joplin"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[You can enter your auth token on your computer by saving an empty token. Then quit KOReader, edit the exporter.joplin_token field in %1/settings.reader.lua after creating a backup, and restart KOReader once you're done.

To export to Joplin, you must forward the IP and port used by this plugin to the localhost:port on which Joplin is listening. This can be done with socat or a similar program. For example:

For Windows: netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=41185 connectaddress=localhost connectport=41184

For Linux: $socat tcp-listen:41185,reuseaddr,fork tcp:localhost:41184

For more information, please visit https://github.com/koreader/koreader/wiki/Highlight-export.]])
                            , BD.dirpath("example"))
                            })
                end
            }
        }
    }
end

function JoplinExporter:export(t)
    print("joplin export")
end


return JoplinExporter

