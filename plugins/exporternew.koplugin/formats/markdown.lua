local MarkdownExporter = require("formats/base"):new{
    name = "markdown",
    version = "markdown/1.0.0",
    extension = "md"
}

function MarkdownExporter:exportOne(t, timestamp)
    self:export({t}, "single", timestamp)
end

function MarkdownExporter:exportAll(t, timestamp)
    self:export(t, "all", timestamp)
end

function MarkdownExporter:export(t, export_type, timestamp)
    local path
    if export_type == "single" then
        path = self:getFilePath(timestamp, t[1].title)
    else
        path = self:getFilePath(timestamp)
    end
    local file = io.open(path, "w")
    if file then
        for _ignore, booknotes in ipairs(t) do

            -- logger.dbg("booknotes", booknotes.title)
            file:write(string.format("# %s\n", booknotes.title))
            file:write(string.format("##### %s\n", booknotes.author))
            local current_chapter
            for _ignore1, clipping in ipairs(booknotes.entries) do
                if current_chapter ~= clipping.chapter then
                    file:write(string.format("\n## %s\n", clipping.chapter))
                    current_chapter = clipping.chapter
                end
                file:write(string.format("\n### %s\n", os.date("%d %b %Y %X", clipping.time)))
                if clipping.text then
                    local text = clipping.text
                    if clipping.drawer == 'lighten' then
                        text = string.format("**%s**", text)
                    elseif clipping.drawer == 'underscore' then
                        text = string.format("<u>%s</u>", text)
                    elseif clipping.drawer == 'strikeout' then
                        text = string.format("~~%s~~", text)
                    elseif clipping.drawer == 'invert' then
                        text = string.format("_%s_", text)
                    end
                    file:write(string.format("%s\n", text))
                end
                if clipping.note then
                    file:write("\n---\n" .. clipping.note)
                end
            end
            file:write("\n\n")
        end
        file:write(string.format("\n_Generated on: %s, Version: %s_\n", timestamp, self.version))
        file:write("\n")
        file:close()
    end
end

return MarkdownExporter

