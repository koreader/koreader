local util = require("ffi/util")
local T = util.template
local _ = require("gettext")

-- text exporter
local TextExporter = require("base"):new {
    name = "text",
    extension = "txt",
    mimetype = "text/plain",
}

local function format(booknotes)
    local tbl = {}

    -- Use wide_space to avoid crengine to treat it specially.
    local wide_space = "\227\128\128"

    if booknotes.title then
        table.insert(tbl, wide_space .. booknotes.title)
        table.insert(tbl, wide_space)
    end
    for ___, entry in ipairs(booknotes) do
        for ____, clipping in ipairs(entry) do
            if clipping.chapter then
                table.insert(tbl, wide_space .. clipping.chapter)
                table.insert(tbl, wide_space)
            end
            local text = T(_("-- Page: %1, added on %2\n"), clipping.page, os.date("%c", clipping.time))
            table.insert(tbl, wide_space .. wide_space .. text)
            if clipping.text then
                table.insert(tbl, clipping.text)
            end
            if clipping.note then
                table.insert(tbl, "\n---\n" .. clipping.note)
            end
            if clipping.image then
                table.insert(tbl, _("<An image>"))
            end
            table.insert(tbl, "-=-=-=-=-=-")
        end
    end
    return tbl
end

function TextExporter:export(t)
    local path = self:getFilePath(t)
    local file = io.open(path, "a")
    if not file then return false end
    for __, booknotes in ipairs(t) do
        local tbl = format(booknotes)
        file:write(table.concat(tbl, "\n"))
    end
    file:close()
    return true
end

function TextExporter:share(t)
    local content = format(t)
    self:shareText(content)
end

return TextExporter
