local _ = require("gettext")
local util = require("ffi/util")
local T = util.template

local TextExporter = require("formats/base"):new {
    name = "text",
    extension = "txt",
}

function TextExporter:getFilePath()
    return self.clipping_dir .. "/KOReaderClipping.txt"
end

function TextExporter:export(t)
    -- Use wide_space to avoid crengine to treat it specially.
    local wide_space = "\227\128\128"
    local path = self:getFilePath()
    local file = io.open(path, "a")
    if file then
        file:write(title .. "\n" .. wide_space .. "\n")
        for _ignore1, chapter in ipairs(t) do
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

        file:write("\n")
        file:close()
    end        
end

return TextExporter
