local ReadwiseClient = require("clients/ReadwiseClient")
local _ = require("gettext")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")


local ReadwiseExporter = require("formats/base"):new {
    name = "readwise",
    is_remote = true,
}

function ReadwiseExporter:isEnabled()
    return self.settings.enabled and self.settings.token
end

function ReadwiseExporter:getMenuTable()
    return {
        text = _("Readwise"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set authorization token"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new {
                        title = _("Set authorization token for Readwise"),
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
                text = _("Export to Readwise"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },

        }
    }
end

function ReadwiseExporter:export(t)
    if self.new_settings or not self.client then
        self.client = ReadwiseClient:new {
            auth_token = self.settings.token
        }
        self.new_settings = false
    end
    self.client:createHighlights(t)
end

return ReadwiseExporter
