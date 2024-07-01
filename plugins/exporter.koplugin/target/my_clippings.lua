local util = require("ffi/util")
local T = util.template
local _ = require("gettext")

-- myClippings exporter
local ClippingsExporter = require("base"):new {
    name = "myClippings",
    extension = "txt",
    mimetype = "text/plain",
    all_books_title = "myClippings"
}

local function format(booknotes)
    local tbl = {}

    for ___, entry in ipairs(booknotes) do
        for ____, clipping in ipairs(entry) do
            if booknotes.title and clipping.text then
                local title_str = booknotes.title .. " (" .. (booknotes.author or "Unknown") .. ")"
                table.insert(tbl, title_str)
                local header = T(_("- Your highlight on page %1 | Added on %2"), clipping.page,
                    os.date("%A, %B %d, %Y %I:%M:%S %p", clipping.time))
                table.insert(tbl, header)
                table.insert(tbl, "")
                table.insert(tbl, clipping.text)
                table.insert(tbl, "==========")

                if clipping.note then
                    table.insert(tbl, title_str)
                    header = T(_("- Your note on page %1 | Added on %2"), clipping.page,
                        os.date("%A, %B %d, %Y %I:%M:%S %p", clipping.time))
                    table.insert(tbl, header)

                    table.insert(tbl, "")
                    table.insert(tbl, clipping.note)
                    table.insert(tbl, "==========")
                end
            end
        end
    end

    -- Ensure a newline after the last "=========="
    table.insert(tbl, "")
    return table.concat(tbl, "\n")
end

function ClippingsExporter:export(t)
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

function ClippingsExporter:share(t)
    local content = format(t)
    self:shareText(content)
end

return ClippingsExporter
