local _ = require("gettext")

local formatters = {
    none = {
        formatter = "%s",
        label = _("None")
    },
    bold = {
        formatter = "**%s**",
        label = _("Bold")
    },
    highlight = {
        formatter = "==%s==",
        label = _("Highlight")
    },
    italic = {
        formatter = "*%s*",
        label = _("Italic")
    },
    bold_italic = {
        formatter = "**_%s_**",
        label = _("Bold italic")
    },
    underline_markdownit = {
        formatter = "++%s++",
        label = _("Underline (Markdownit style, with ++)")
    },
    underline_u_tag = {
        formatter = "<u>%s</u>",
        label = _("Underline (with <u></u> tags)")
    },
    strikethrough = {
        formatter = "~~%s~~",
        label = _("Strikethrough")
    },
}

local function prepareBookContent(book, formatting_options, highlight_formatting)
    local content = ""
    local current_chapter = nil
    content = content .. "# " .. book.title .. "\n"
    local author = book.author or _("N/A")
    content = content .. "##### " .. author:gsub("\n", ", ") .. "\n\n"
    for _, note in ipairs(book) do
        local entry = note[1]
        if entry.chapter ~= current_chapter then
            current_chapter = entry.chapter
            content = content .. "## " .. current_chapter .. "\n"
        end
        content = content .. "### Page " .. entry.page .. " @ " .. os.date("%d %B %Y %I:%M:%S %p", entry.time) .. "\n"
        if highlight_formatting then
            content = content .. string.format(formatters[formatting_options[entry.drawer]].formatter, entry.text) .."\n"
        else
            content = content .. entry.text .. "\n"
        end
        if entry.note then
            content = content .. "\n---\n" .. entry.note .. "\n"
        end
        content = content .. "\n"
    end
    return content
end

return {
    prepareBookContent = prepareBookContent,
    formatters = formatters
}
