local logger = require("logger")
local json = require("json")

local JsonExporter = require("formats/base"):new{
    name = "json",
    version = "json/1.0.0"
}

function JsonExporter:exportOne(t, timestamp)
    local path = self:getFilePath(timestamp, t.title)
    local file = io.open(path, "w")
    if file then
        t.created_on = timestamp
        t.version = self.version
        file:write(json.encode(t))
        file:write("\n")
        file:close()
    end
end

function JsonExporter:exportAll(t, timestamp)
    local path = self:getFilePath(timestamp)
    local file = io.open(path, "w")
    if file then
        local exportable = {
            created_on = timestamp,
            version = self.version,
            documents = t
        }

        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

return JsonExporter
