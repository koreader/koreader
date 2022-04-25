local util = require("ffi/util")
local T = util.template
local _ = require("gettext")

-- text exporter
local TextExporter = require("base"):new {
    name = "text",
    extension = "txt",
}

function TextExporter:export(t)
    -- Use wide_space to avoid crengine to treat it specially.
    local wide_space = "\227\128\128"
    local path = self:getFilePath(t)
    local file = io.open(path, "a")
    if not file then return false end
    for __, booknotes in ipairs(t) do
        if booknotes.title then
            file:write(wide_space .. booknotes.title .. "\n" .. wide_space .. "\n")
        end
        for ___, entry in ipairs(booknotes) do
            for ____, clipping in ipairs(entry) do
                if clipping.chapter then
                    file:write(wide_space .. clipping.chapter .. "\n" .. wide_space .. "\n")
                end
                local text = T(_("-- Page: %1, added on %2\n"), clipping.page, os.date("%c", clipping.time))
                file:write(wide_space .. wide_space .. text)
                if clipping.text then
                    file:write(clipping.text)
                end
                if clipping.note then
                    file:write("\n---\n" .. clipping.note)
                end
                if clipping.image then
                    file:write(_("<An image>"))
                end
                file:write("\n-=-=-=-=-=-\n")
            end
        end
        file:write("\n")
    end
    file:close()
    return true
end

return TextExporter
