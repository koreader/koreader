
local md = require("template/md")
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local T = util.template
local _ = require("gettext")

-- markdown exporter
local MarkdownExporter = require("base"):new {
    name = "markdown",
    extension = "md",
}

local formatter_buttons = {
    {_("None"), "none"},
    {_("Bold"), "bold"},
    {_("Bold Italic"), "bold_italic"},
    {_("Italic"), "italic"},
    {_("Strikethrough"), "strikethrough"},
    {_("Underline (Markdownit style, with ++)"), "underline_markdownit"},
    {_("Underline (with <u></u> tags)"), "underline_u_tag"},
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
    UIManager:show(require("ui/widget/radiobuttonwidget"):new{
        title_text = T(_("Formatting style for %1"), _(label)),
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

function MarkdownExporter:getFormatterLabel(header, drawer_style)
    return T("%1: %2", header, md.formatters[self.settings.formatting_options[drawer_style]].label)
end

function MarkdownExporter:getMenuTable()
    return {
        text = _("Markdown"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Export to Markdown"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Format Highlights based on style"),
                checked_func = function() return self.settings.highlight_formatting end,
                callback = function() self.settings.highlight_formatting = not self.settings.highlight_formatting end,
            },
            {
                text_func = function ()
                    return self:getFormatterLabel(_("Lighten"), "lighten")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editFormatStyle("lighten", "Lighten", touchmenu_instance)
                end,
            },
            {
                text_func = function ()
                    return self:getFormatterLabel(_("Strikeout"), "strikeout")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editFormatStyle("strikeout", "Strikeout", touchmenu_instance)
                end,
            },
            {
                text_func = function ()
                    return self:getFormatterLabel(_("Underline"), "underscore")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editFormatStyle("underscore", "Underline", touchmenu_instance)
                end,
            },
            {
                text_func = function ()
                    return self:getFormatterLabel(_("Invert"), "invert")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editFormatStyle("invert", "Invert", touchmenu_instance)
                end,
            },
        }
    }
end



function MarkdownExporter:export(t)
    local path = self:getFilePath(t)
    local file = io.open(path, "w")
    if not file then return false end
    for idx, book in ipairs(t) do
        file:write(md.prepareBookContent(book, self.settings.formatting_options, self.settings.highlight_formatting))
        if idx < #t then
            file:write("\n")
        end
    end
    file:write("\n\n_Generated at: " .. self:getTimeStamp() .. "_")
    file:close()
    return true
end

return MarkdownExporter
