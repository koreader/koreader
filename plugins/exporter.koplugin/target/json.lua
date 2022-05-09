local json = require("json")

-- json exporter
local JsonExporter = require("base"):new {
    name = "json",
}

local function format(booknotes)
    local t = {
        title = booknotes.title,
        author = booknotes.author,
        entries = {},
        exported = booknotes.exported,
        file = booknotes.file
    }
    for _, entry in ipairs(booknotes) do
        table.insert(t.entries, entry[1])
    end
    return t
end

function JsonExporter:export(t)
    local exportable
    local timestamp = self.timestamp or os.time()
    local path = self:getFilePath(t)
    if #t == 1 then
        exportable = format(t[1])
        exportable.created_on = timestamp
        exportable.version = self:getVersion()
    else
        local documents = {}
        for _, booknotes in ipairs(t) do
            table.insert(documents, format(booknotes))
        end
        exportable = {
            created_on = timestamp,
            version = self:getVersion(),
            documents = documents
        }
    end
    local file = io.open(path, "w")
    if not file then return false end
    file:write(json.encode(exportable))
    file:write("\n")
    file:close()
    return true
end

return JsonExporter
