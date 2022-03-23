local HtmlExporter = require("formats/base"):new{
    name = "html",
}

function HtmlExporter:export(t)
    print("html export")
end

return HtmlExporter

