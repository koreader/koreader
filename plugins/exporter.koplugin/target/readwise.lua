local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local ReadwiseExporter = require("base"):new{
    name = "readwise",
    title = _("Readwise"),
    is_remote = true,
}

function ReadwiseExporter:isReadyToExport()
    if self.settings.token then return true end
    return false
end

function ReadwiseExporter:genTargetSubMenu()
    local dialog_title = _("Set authorization token")
    return {
        self:genExportToMenuItem(),
        -- separator
        {
            text = dialog_title,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local auth_dialog
                auth_dialog = InputDialog:new{
                    title = dialog_title,
                    input = self.settings.token,
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(auth_dialog)
                                end,
                            },
                            {
                                text = _("Set token"),
                                callback = function()
                                    self.settings.token = auth_dialog:getInputText()
                                    UIManager:close(auth_dialog)
                                    touchmenu_instance:updateItems()
                                end,
                            },
                        },
                    }
                }
                UIManager:show(auth_dialog)
                auth_dialog:onShowKeyboard()
            end,
        },
    }
end

function ReadwiseExporter:createHighlights(booknotes)
    local highlights = {}

    local json_headers = {
        ["Authorization"] = "Token " .. self.settings.token,
    }

    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = {
                text = clipping.text,
                title = booknotes.title,
                author = booknotes.author ~= "" and booknotes.author:gsub("\n", ", ") or nil, -- optional author
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

    local result, err = self:makeJsonRequest("https://readwise.io/api/v2/highlights", "POST",
         { highlights = highlights }, json_headers)

    if not result then
        logger.warn("error creating highlights", err)
        return false
    end
    return true
end

function ReadwiseExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return ReadwiseExporter
