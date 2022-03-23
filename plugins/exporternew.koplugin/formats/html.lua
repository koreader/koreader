local logger = require("logger")

local slt2 = require('template/slt2')


local HtmlExporter = require("formats/base"):new{
    name = "html",
    version = "html/1.0.0",

}

function HtmlExporter:exportOne(t, timestamp)
    self:export({t}, "single", timestamp)
end

function HtmlExporter:exportAll(t, timestamp)
    self:export(t, "all", timestamp)
end

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
    logger.dbg("html", t)
    if file then
        local content = slt2.render(template, {
            clippings = t,
            document_title = title,
            version = self.version,
            timestamp = self:getFileTimeStamp(timestamp),
            logger = logger
        })
        file:write(content)
        file:close()
    end
end

return HtmlExporter

