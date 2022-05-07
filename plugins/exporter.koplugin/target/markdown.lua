local _ = require("gettext")
local UIManager = require("ui/uimanager")


local formatters = {
    none = "%s",
    bold = "**%s**",
    italic = "*%s*",
    bold_italic = "**_%s_**",
    underline_markdownit = "++%s++",
    underline_u_tag = "<u>%s</u>",
    strikethrough = "~~%s~~",
}

-- markdown exporter
local MarkdownExporter = require("base"):new {
    name = "markdown",
    extension = "md",
}


function MarkdownExporter:loadSettings()
    local plugin_settings = G_reader_settings:readSetting("exporter") or {}
    self.settings = plugin_settings[self.name] or {}
end


local formatter_buttons = {
    {_("None"), "none"},
    {_("Bold"), "bold"},
    {_("Bold Italic"), "bold_italic"},
    {_("Italic"), "italic"},
    {_("Strikethrough"), "strikethrough"},
    {_("Underline (Markdownit style, with ++)"), "underline_markdownit"},
    {_("Underline (with <u></u> tags)"), "underline_u_tag"},
}

function MarkdownExporter:editFormatStyle(drawer_style)
    local radio_buttons = {}
    for _, v in ipairs(formatter_buttons) do
        table.insert(radio_buttons, {
            {
                text = v[1],
                checked = self.settings.formatting_options[drawer_style] == v[2],
                provider = v[2],
            },
        })
    end
    UIManager:show(require("ui/widget/radiobuttonwidget"):new{
        title_text = _("Highlight style for " .. drawer_style),
        width_factor = 0.8,
        keep_shown_on_apply = true,
        radio_buttons = radio_buttons,
        callback = function(radio)
            self.settings.formatting_options[drawer_style] = radio.provider
        end,
    })
end

function MarkdownExporter:populateSettings()
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

function MarkdownExporter:getMenuTable()
    self:populateSettings()
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
                text = _("Lighten"),
                keep_menu_open = true,
                callback = function()
                    self:editFormatStyle("lighten")
                end,
            },
            {
                text = _("Strikeout"),
                keep_menu_open = true,
                callback = function()
                    self:editFormatStyle("strikeout")
                end,
            },
            {
                text = _("underscore"),
                keep_menu_open = true,
                callback = function()
                    self:editFormatStyle("underscore")
                end,
            },
            {
                text = _("Invert"),
                keep_menu_open = true,
                callback = function()
                    self:editFormatStyle("invert")
                end,
            },
        }
    }
end

function MarkdownExporter:export(t)
    self:populateSettings()
    local path = self:getFilePath(t)
    local file = io.open(path, "w")
    if not file then return false end
    for idx, book in ipairs(t) do
        local current_chapter = nil
        file:write("# " .. book.title .. "\n")
        file:write("##### " .. book.author:gsub("\n", ", ") .. "\n\n")
        for _, note in ipairs(book) do
            local entry = note[1]
            if entry.chapter ~= current_chapter then
                current_chapter = entry.chapter
                file:write("## " .. current_chapter .. "\n")
            end
            file:write("### " .. os.date("%d %B %Y %I:%M %p", entry.time) .. ", Page " .. entry.page .. "\n")
            if self.settings.highlight_formatting then
                file:write(string.format(formatters[self.settings.formatting_options[entry.drawer]], entry.text) .."\n")
            else
                file:write(entry.text .. "\n")
            end
            if entry.note then
                file:write("\n---\n" .. entry.note .. "\n")
            end
            file:write("\n")
        end
        if idx < #t then
            file:write("\n")
        end
    end
    file:write("\n\n_Generated at: " .. self:getTimeStamp() .. "_")
    file:close()
    return true
end

return MarkdownExporter
