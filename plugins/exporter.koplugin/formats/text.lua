local _ = require("gettext")
local util = require("ffi/util")
local T = util.template

local TextExporter = require("formats/base"):new{
    name = "text",
    version = "text/1.0.0",
    extension = "txt",
}

function TextExporter:export(t)
    local path
    if #t == 1 then
        path = self:getFilePath(t[1].title)
    else
        path = self:getFilePath()
    end
    local file = io.open(path, "w")
    if file then
        local wide_space = "\227\128\128"
        for _ignore, booknotes in ipairs(t) do
            if booknotes.title then
                file:write(wide_space .. booknotes.title .. "\n" .. wide_space .. "\n")
            end
            for _ignore1, clipping in ipairs(booknotes.entries) do
                if clipping.chapter then
                    file:write(wide_space .. clipping.chapter .. "\n" .. wide_space .. "\n")
                end
                file:write(wide_space .. wide_space ..
                                T(_("-- Page: %1, added on %2\n"),
                                    clipping.page, os.date("%c", clipping.time)))
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
        file:close()
    end
end

return TextExporter

