local json = require("json")
local logger = require("logger")

local JsonExporter = require("formats/base"):new{
    name = "json",
    version = "json/1.0.0"
}

function JsonExporter:export(t)
    local path, exportable
    local timestamp = self.timestamp or os.time()
    if #t == 1 then
        path = self:getFilePath(t[1].title)
        exportable = t[1]
        exportable.created_on = timestamp
        exportable.version = self.version
    else
        path = self:getFilePath()
        exportable = {
            created_on = timestamp,
            version = self.version,
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
