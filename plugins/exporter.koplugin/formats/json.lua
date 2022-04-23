local json = require("json")
local logger = require("logger")

local JsonExporter = require("formats/base"):new {
    name = "json",
}

local function normalizeBookNotes(booknotes)
    local normalized = {
        title = booknotes.title,
        author = booknotes.author,
        entries = {},
        exported = booknotes.exported,
        file = booknotes.file
    }
    for _, entry in ipairs(booknotes) do
        table.insert(normalized.entries, entry[1])
    end
    return normalized
end

function JsonExporter:export(t)
    local path, exportable
    local timestamp = self.timestamp or os.time()
    logger.dbg("JsonExporter:export", t)
    if #t == 1 then
        path = self:getFilePath(t[1].title)
        exportable = normalizeBookNotes(t[1])
        exportable.created_on = timestamp
        exportable.version = self:getVersion()
    else
        path = self:getFilePath()
        local docmuents = {}
        for _, booknotes in ipairs(t) do
            table.insert(docmuents, normalizeBookNotes(booknotes))
        end
        exportable = {
            created_on = timestamp,
            version = self:getVersion(),
            documents = docmuents
        }
    end
    local file = io.open(path, "w")
    if file then
        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

return JsonExporter
