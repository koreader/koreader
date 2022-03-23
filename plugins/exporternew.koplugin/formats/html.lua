local logger = require("logger")

local slt2 = require('template/slt2')


local HtmlExporter = require("formats/base"):new{
    name = "html",
    version = "html/1.0.0",

}


function HtmlExporter:export(t, export_type, timestamp)
    local path, title
    if export_type == "single" then
        path = self:getFilePath(timestamp, t[1].title)
        title = t[1].title
    else
        path = self:getFilePath(timestamp)
        title = "All Books"
    end
    local file = io.open(path, "w")
    local template = slt2.loadfile(self.path .. "/template/note.tpl")
    if file then
        local content = slt2.render(template, {
            clippings = t,
            document_title = title,
        })
        file:write(content)
        file:close()
    end
end

function HtmlExporter:getFilePath(timestamp, title)
    if title then
        return self.clipping_dir .. "/" .. timestamp .. "-" .. title .. ".html"
    else
        return self.clipping_dir .. "/" .. timestamp .. "-all-books.html"
    end
end

return HtmlExporter

