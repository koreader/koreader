local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local _ = require("gettext")

local ClippingsExporter = require("base"):new{
    name = "myClippings",
    title = _("myClippings"),
    extension = "txt",
    mimetype = "text/plain",
    all_books_title = "myClippings",
}

function ClippingsExporter:genTargetSubMenu()
    return {
        self:genExportToMenuItem(),
        -- separator
        self:genCloudStorageMenuItem(),
        self:genDeleteFileMenuItem(),
        -- separator
        self:genToggleMenuItem(_("Overwrite export file"), "overwrite_export_file"),
        self:genToggleMenuItem(_("Use Kindle export file name"), "kindle_export_file"),
    }
end

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

function ClippingsExporter:getFilePath()
    if self.filepath then
        if self.settings.kindle_export_file then
            return ffiUtil.dirname(self.filepath) .. "/My Clippings.txt"
        end
        return self.filepath .. "." .. self.extension
    end
end

function ClippingsExporter:export(t)
    local path = self:getFilePath(t)
    local file = io.open(path, self.settings.overwrite_export_file and "w" or "a")
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
