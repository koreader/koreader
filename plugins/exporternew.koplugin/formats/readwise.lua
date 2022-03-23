local ReadwiseExporter = require("formats/base"):new{
    name = "readwise",
    is_remote = true,
}

function ReadwiseExporter:export(t)
    print("readwise export")
end

return ReadwiseExporter

