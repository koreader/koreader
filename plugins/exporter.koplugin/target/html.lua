local logger = require("logger")
local slt2 = require("template/slt2")

-- html exporter
local HtmlExporter = require("base"):new {
    name = "html",
    mimetype = "text/html",
}

local function format(booknotes)
    local chapters = {}
    local curr_chapter = nil
    for _, booknote in ipairs(booknotes) do
        if curr_chapter == nil then
            curr_chapter = {
                title = booknote[1].chapter,
                entries = {}
            }
        elseif curr_chapter.title ~= booknote[1].chapter then
            table.insert(chapters, curr_chapter)
            curr_chapter = {
                title = booknote[1].chapter,
                entries = {}
            }
        end
        table.insert(curr_chapter.entries, booknote[1])
    end
    if curr_chapter ~= nil then
        table.insert(chapters, curr_chapter)
    end
    booknotes.chapters = chapters
    booknotes.entries = nil
    return booknotes
end

function HtmlExporter:getRenderedContent(t)
    local title
    if #t == 1 then
        title = t[1].title
    else
        title = "All Books"
    end
    local template = slt2.loadfile(self.path .. "/template/note.tpl")
    local clipplings = {}
    for _, booknotes in ipairs(t) do
        table.insert(clipplings, format(booknotes))
    end
    local content = slt2.render(template, {
        clippings=clipplings,
        document_title = title,
        version = self:getVersion(),
        timestamp = self:getTimeStamp(),
        logger = logger
    })
    return content
end

function HtmlExporter:export(t)
    local path = self:getFilePath(t)
    local file = io.open(path, "w")
    if not file then return false end
    local content = self:getRenderedContent(t)
    file:write(content)
    file:close()
    return true
end

function HtmlExporter:share(t)
    local content = self:getRenderedContent({t})
    self:shareText(content)
end

return HtmlExporter
