local json = require("json")

local JsonExporter = require("formats/base"):new {
    name = "json",
}

function JsonExporter:export(t)
    local path, exportable
    local timestamp = self.timestamp or os.time()
    if #t == 1 then
        path = self:getFilePath(t[1].title)
        exportable = t[1]
        exportable.created_on = timestamp
        exportable.version = self:getVersion()
    else
        path = self:getFilePath()
        exportable = {
            created_on = timestamp,
            version = self:getVersion(),
            documents = t
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
