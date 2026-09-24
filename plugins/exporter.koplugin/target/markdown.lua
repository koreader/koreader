local ButtonSelector = require("ui/widget/buttonselector")
local InputDialog = require("ui/widget/inputdialog")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local UIManager = require("ui/uimanager")
local md = require("template/md")
local _ = require("gettext")
local T = require("ffi/util").template

local MarkdownExporter = require("base"):new{
    name = "markdown",
    title = _("Markdown"),
    extension = "md",
    mimetype = "text/markdown",
    default_settings = {
        highlight_formatting = true,
        formatting_options = {
            lighten    = "italic",
            underscore = "underline_markdownit",
            strikeout  = "strikethrough",
            invert     = "bold",
        },
    },
}

local formatter_buttons = {
    { _("None"), "none" },
    { _("Bold"), "bold" },
    { _("Bold italic"), "bold_italic" },
    { _("Highlight"), "highlight"},
    { _("Italic"), "italic" },
    { _("Strikethrough"), "strikethrough" },
    { _("Underline (Markdownit style, with ++)"), "underline_markdownit" },
    { _("Underline (with <u></u> tags)"), "underline_u_tag" },
}

function MarkdownExporter:genTargetSubMenu()
    local sub_item_table = {
        self:genExportToMenuItem(),
        -- separator
        self:genCloudStorageMenuItem(),
        self:genDeleteFileMenuItem(),
        -- separator
        self:genToggleMenuItem(_("Export backlinks"), "export_backlinks", true),
        -- separator
        self:genToggleMenuItem(_("Format highlights based on style"), "highlight_formatting"),
    }
    for __, entry in ipairs(ReaderHighlight.getHighlightStyles()) do
        local style_text, style = unpack(entry)
        table.insert(sub_item_table, {
            text_func = function()
                local value = self.settings.formatting_options[style]
                return T(_("%1: %2"), style_text, md.formatters[value] and md.formatters[value].label or value)
            end,
            enabled_func = function()
                return self.settings.highlight_formatting and true or false
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance) -- default formats
                UIManager:show(ButtonSelector:new{
                    width_factor = 0.8,
                    current_value = self.settings.formatting_options[style],
                    values = formatter_buttons,
                    callback = function(value)
                        self.settings.formatting_options[style] = value
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
            hold_callback = function(touchmenu_instance) -- custom format
                local value = self.settings.formatting_options[style]
                local formatter_dialog
                formatter_dialog = InputDialog:new{
                    title = T("Format for: %1", style_text),
                    input = md.formatters[value] and md.formatters[value].formatter or value,
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(formatter_dialog)
                                end,
                            },
                            {
                                text = _("Save"),
                                callback = function()
                                    local new_value = formatter_dialog:getInputValue()
                                    if new_value and new_value ~= "" and new_value ~= value then
                                        UIManager:close(formatter_dialog)
                                        self.settings.formatting_options[style] = new_value
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(formatter_dialog)
                formatter_dialog:onShowKeyboard()
            end,
        })
    end
    return sub_item_table
end

function MarkdownExporter:export(t)
    local path = self:getFilePath()
    local file = io.open(path, "w")
    if not file then return false end
    for idx, book in ipairs(t) do
        local tbl = md.prepareBookContent(book,
            self.settings.formatting_options, self.settings.highlight_formatting, self.settings.export_backlinks)
        file:write(table.concat(tbl, "\n"))
        if idx < #t then
            file:write("\n\n")
        end
    end
    file:write("\n## \n_" .. T("Generated at: %1", self:getTimeStamp()) .. "_")
    file:close()
    return true
end

function MarkdownExporter:share(t)
    local tbl = md.prepareBookContent(t, self.settings.formatting_options, self.settings.highlight_formatting)
    table.insert(tbl, "\n_Generated at: " .. self:getTimeStamp() .. "_")
    self:shareText(table.concat(tbl, "\n"))
end

return MarkdownExporter
