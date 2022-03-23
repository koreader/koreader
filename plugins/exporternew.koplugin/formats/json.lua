local logger = require("logger")
local json = require("json")

local JsonExporter = require("formats/base"):new{
    name = "json",
    version = "json/1.0.0"
}

function JsonExporter:export(t, export_type, timestamp)
    local path
    if export_type == "single" then
        path = self:getFilePath(timestamp, t[1].title)
    else
        path = self:getFilePath(timestamp)
    end
    local file = io.open(path, "w")
    if file then
        local exportable
        if export_type == "single" then
            -- We will handle single document export here.
            exportable = self:prepareBooknotesForJSON(t[1])
            exportable.created_on = timestamp
            exportable.version = self.version
        else
            exportable = {
                created_on = timestamp,
                version = self.version,
                documents = {}
            }
            for _, booknotes in ipairs(t) do
                table.insert(exportable.documents, self:prepareBooknotesForJSON(booknotes))
            end
        end
        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

function JsonExporter:prepareBooknotesForJSON(booknotes)
    local exportable = {
            title = booknotes.title,
            author = booknotes.author,
            entries = {},
            exported = booknotes.exported,
            file = booknotes.file
    }
    for _, entry in ipairs(booknotes) do
        table.insert(exportable.entries, entry[1])
    end
    return exportable
end

function JsonExporter:getFilePath(timestamp, title)
    if title then
        return self.clipping_dir .. "/" .. timestamp .. "-" .. title .. ".json"
    else
        return self.clipping_dir .. "/" .. timestamp .. "-all-books.json"
    end
end

return JsonExporter
