local Device = require("device")
local rapidjson = require("rapidjson")
local _ = require("gettext")
local md5 = require("ffi/MD5")

-- json exporter
local JsonExporter = require("base"):new {
    name = "json",
    shareable = Device:canShareText(),
    init_callback = function(self, settings)
        local changed = false
        if settings.bookChecksum == nil then
            settings.bookChecksum = false
        end
        changed = true
        return changed, settings
    end
}

function JsonExporter:getMenuTable()
    local menu = {
        text = _("Json"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Export to Json"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Show book checksum in export"),
                checked_func = function() return self.settings.bookChecksum end,
                callback = function()
                    self.settings.bookChecksum = not self.settings.bookChecksum 
                    self:saveSettings()
                end,
            }
        }
    }

    return menu
end

local function format(booknotes, settings)
    local t = {
        title = booknotes.title,
        author = booknotes.author,
        entries = {},
        exported = booknotes.exported,
        file = booknotes.file,
        number_of_pages = booknotes.number_of_pages
    }
    if settings.bookChecksum then
        t.file_md5sum = md5.sumFile(booknotes.file)

    end
    for _, entry in ipairs(booknotes) do
        table.insert(t.entries, entry[1])
    end
    return t
end

function JsonExporter:export(t)
    local exportable
    local timestamp = self.timestamp or os.time()
    local path = self:getFilePath(t)
    if #t == 1 then
        exportable = format(t[1], self.settings)
        exportable.created_on = timestamp
        exportable.version = self:getVersion()
    else
        local documents = {}
        for _, booknotes in ipairs(t) do
            table.insert(documents, format(booknotes, self.settings))
        end
        exportable = {
            created_on = timestamp,
            version = self:getVersion(),
            documents = documents
        }
    end
    local file = io.open(path, "w")
    if not file then return false end
    file:write(rapidjson.encode(exportable, {pretty = true}))
    file:write("\n")
    file:close()
    return true
end

function JsonExporter:share(t)
    local content = format(t)
    content.created_on = self.timestamp or os.time()
    content.version = self:getVersion()
    Device:doShareText(rapidjson.encode(content, {pretty = true}))
end

return JsonExporter
