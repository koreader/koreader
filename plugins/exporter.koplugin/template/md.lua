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
    highlight_mark_tag = {
        formatter = "==%s==",
        label = _("Highlight (with <mark></mark> tags)")
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
    local tbl = {}
    local current_chapter = nil
    local author = book.author or _("N/A")
    table.insert(tbl, "# " .. book.title .. "( —" .. author:gsub("\n", ", ") .. ")\n")
    for _, note in ipairs(book) do
        local entry = note[1]
        if entry.chapter ~= current_chapter then
            current_chapter = entry.chapter
            table.insert(tbl, "\n## " .. current_chapter)
        end
        table.insert(tbl, "\n### Page " .. entry.page .. " @ " .. os.date("%d %B %Y %H:%M:%S", entry.time))
        if highlight_formatting then
            table.insert(tbl, "> " .. string.format(formatters[formatting_options[entry.drawer]].formatter, entry.text))
        else
            table.insert(tbl, "> " .. entry.text)
        end
        if entry.note then
            table.insert(tbl, entry.note)
        end
    end
    return tbl
end

return {
    prepareBookContent = prepareBookContent,
    formatters = formatters
}
