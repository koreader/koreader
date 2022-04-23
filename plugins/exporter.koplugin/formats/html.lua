local logger = require("logger")

local slt2 = require('template/slt2')


local HtmlExporter = require("formats/base"):new {
    name = "html",
}

local function prepareBookNotesForExport(booknotes)
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

function HtmlExporter:export(t)
    local path, title
    if #t == 1 then
        path = self:getFilePath(t[1].title)
        title = t[1].title
    else
        path = self:getFilePath()
        title = "All Books"
    end
    local file = io.open(path, "w")
    local template = slt2.loadfile(self.path .. "/template/note.tpl")
    local clipplings = {}
    for _, booknotes in ipairs(t) do
        table.insert(clipplings, prepareBookNotesForExport(booknotes))
    end
    if file then
        local content = slt2.render(template, {
            clippings=clipplings,
            document_title = title,
            version = self:getVersion(),
            timestamp = self:getTimeStamp(),
            logger = logger
        })
        file:write(content)
        file:close()
    end
end

return HtmlExporter
