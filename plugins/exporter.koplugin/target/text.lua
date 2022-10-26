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
    local wide_space = "\227\128\128"
    local content = ""
    if booknotes.title then
        content = content .. wide_space .. booknotes.title .. "\n" .. wide_space .. "\n"
    end
    for ___, entry in ipairs(booknotes) do
        for ____, clipping in ipairs(entry) do
            if clipping.chapter then
                content = content .. wide_space .. clipping.chapter .. "\n" .. wide_space .. "\n"
            end
            local text = T(_("-- Page: %1, added on %2\n"), clipping.page, os.date("%c", clipping.time))
            content = content .. wide_space .. wide_space .. text
            if clipping.text then
                content = content .. clipping.text
            end
            if clipping.note then
                content = content .. "\n---\n" .. clipping.note
            end
            if clipping.image then
                content = content .. _("<An image>")
            end
            content = content .. "\n-=-=-=-=-=-\n"
        end
    end
    content = content .. "\n"
    return content
end

function TextExporter:export(t)
    -- Use wide_space to avoid crengine to treat it specially.

    local path = self:getFilePath(t)
    local file = io.open(path, "a")
    if not file then return false end
    for __, booknotes in ipairs(t) do
        local content = format(booknotes)
        file:write(content)
    end
    file:close()
    return true
end

function TextExporter:share(t)
    local content = format(t)
    self:shareText(content)
end

return TextExporter
