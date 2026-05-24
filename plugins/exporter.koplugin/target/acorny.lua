local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local AcornyExporter = require("base"):new {
    name = "acorny",
    is_remote = true,
}

function AcornyExporter:isReadyToExport()
    if self.settings.token then return true end
    return false
end

function AcornyExporter:getMenuTable()
    return {
        text = _("Acorny"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set authorization token"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new {
                        title = _("Set authorization token for Acorny"),
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
                text = _("Export to Acorny"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new {
                        text = _([[To export highlights to Acorny, sign in to Acorny and open Settings > Import API tokens. Create a token, copy it immediately, then paste it into KOReader with "Set authorization token".]])
                    })
                end
            },
        }
    }
end

function AcornyExporter:createHighlights(booknotes)
    local highlights = {}
    local author = booknotes.author

    local json_headers = {
        ["Authorization"] = "Token " .. self.settings.token,
    }

    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = {
                text = clipping.text,
                title = booknotes.title,
                author = author and author ~= "" and author:gsub("\n", ", ") or nil,
                source_type = "koreader",
                category = "books",
                note = clipping.note,
                location = clipping.page,
                location_type = "order",
                highlighted_at = os.date("!%Y-%m-%dT%TZ", clipping.time),
            }
            table.insert(highlights, highlight)
        end
    end

    local result, err = self:makeJsonRequest("https://acorny.io/api/v2/highlights/", "POST",
         { highlights = highlights }, json_headers)

    if not result then
        logger.warn("error creating highlights", err)
        return false
    end
    return true
end

function AcornyExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return AcornyExporter
