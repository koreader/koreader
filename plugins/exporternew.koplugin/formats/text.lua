local TextExporter = require("formats/base"):new{
    name = "text",
}

function TextExporter:export(t)
    print("text export")
end

return TextExporter

