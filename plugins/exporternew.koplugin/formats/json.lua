local json = require("json")

local JsonExporter = require("formats/base"):new{
    name = "json",
    version = "json/1.0.0"
}

function JsonExporter:exportOne(t)
    local path = self:getFilePath(t.title)
    local file = io.open(path, "w")
    if file then
        t.created_on = self:getTimeStamp()
        t.version = self.version
        file:write(json.encode(t))
        file:write("\n")
        file:close()
    end
end

function JsonExporter:exportAll(t)
    local path = self:getFilePath()
    local file = io.open(path, "w")
    if file then
        local exportable = {
            created_on = self:getTimeStamp(),
            version = self.version,
            documents = t
        }

        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

return JsonExporter
