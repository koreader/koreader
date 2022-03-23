local _ = require("gettext")
local util = require("ffi/util")
local T = util.template

local TextExporter = require("formats/base"):new{
    name = "text",
    version = "text/1.0.0"
}

function TextExporter:export(t, export_type, timestamp)
    local path
    if export_type == "single" then
        path = self:getFilePath(timestamp, t[1].title)
    else
        path = self:getFilePath(timestamp)
    end
    local file = io.open(path, "w")
    if file then
        local wide_space = "\227\128\128"
        for _ignore, booknotes in ipairs(t) do
            for _ignore1, chapter in ipairs(booknotes) do
                if chapter.title then
                    file:write(wide_space .. chapter.title .. "\n" .. wide_space .. "\n")
                end
                for _ignore2, clipping in ipairs(chapter) do
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
        end
        file:write("\n")
        file:close()
    end
end


function TextExporter:getFilePath(timestamp, title)
    if title then
        return self.clipping_dir .. "/" .. timestamp .. "-" .. title .. ".txt"
    else
        return self.clipping_dir .. "/" .. timestamp .. "-all-books.txt"
    end
end

return TextExporter

