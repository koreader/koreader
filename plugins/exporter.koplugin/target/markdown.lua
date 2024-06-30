local UIManager = require("ui/uimanager")
local md = require("template/md")
local _ = require("gettext")
local T = require("ffi/util").template

-- markdown exporter
local MarkdownExporter = require("base"):new {
    name = "markdown",
    extension = "md",
    mimetype = "text/markdown",

    init_callback = function(self, settings)
        local changed = false
        if not settings.formatting_options or settings.highlight_formatting == nil then
            settings.formatting_options = settings.formatting_options or {
                lighten = "italic",
                underscore = "underline_markdownit",
                strikeout = "strikethrough",
                invert = "bold",
            }
            settings.highlight_formatting = settings.highlight_formatting or true
            changed = true
        end
        return changed, settings
    end,
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

function MarkdownExporter:editFormatStyle(drawer_style, label, touchmenu_instance)
    local radio_buttons = {}
    for _idx, v in ipairs(formatter_buttons) do
        table.insert(radio_buttons, {
            {
                text = v[1],
                checked = self.settings.formatting_options[drawer_style] == v[2],
                provider = v[2],
            },
        })
    end
    UIManager:show(require("ui/widget/radiobuttonwidget"):new {
        title_text = T(_("Formatting style for %1"), label),
        width_factor = 0.8,
        radio_buttons = radio_buttons,
        callback = function(radio)
            self.settings.formatting_options[drawer_style] = radio.provider
            touchmenu_instance:updateItems()
        end,
    })
end

function MarkdownExporter:onInit()
    local changed = false
    if self.settings.formatting_options == nil then
        self.settings.formatting_options = {
            lighten = "italic",
            underscore = "underline_markdownit",
            strikeout = "strikethrough",
            invert = "bold",
        }
        changed = true
    end
    if self.settings.highlight_formatting == nil then
        self.settings.highlight_formatting = true
        changed = true
    end
    if changed then
        self:saveSettings()
    end
end

local highlight_style = {
    { _("Lighten"), "lighten" },
    { _("Underline"), "underscore" },
    { _("Strikeout"), "strikeout" },
    { _("Invert"), "invert" },
}

function MarkdownExporter:getMenuTable()
    local menu = {
        text = _("Markdown"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Export to Markdown"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Format highlights based on style"),
                checked_func = function() return self.settings.highlight_formatting end,
                callback = function() self.settings.highlight_formatting = not self.settings.highlight_formatting end,
            },
        }
    }

    for _idx, entry in ipairs(highlight_style) do
        table.insert(menu.sub_item_table, {
            text_func = function()
                return entry[1] .. ": " .. md.formatters[self.settings.formatting_options[entry[2]]].label
            end,
            enabled_func = function()
                return self.settings.highlight_formatting
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:editFormatStyle(entry[2], entry[1], touchmenu_instance)
            end,
        })
    end
    return menu
end

function MarkdownExporter:export(t)
    local path = self:getFilePath(t)
    local file = io.open(path, "w")
    if not file then return false end
    for idx, book in ipairs(t) do
        local tbl = md.prepareBookContent(book, self.settings.formatting_options, self.settings.highlight_formatting)
        file:write(table.concat(tbl, "\n"))
    end
    file:write("\n\n_Generated at: " .. self:getTimeStamp() .. "_")
    file:close()
    return true
end

function MarkdownExporter:share(t)
    local tbl = md.prepareBookContent(t, self.settings.formatting_options, self.settings.highlight_formatting)
    table.insert(tbl, "\n_Generated at: " .. self:getTimeStamp() .. "_")
    self:shareText(table.concat(tbl, "\n"))
end

return MarkdownExporter
