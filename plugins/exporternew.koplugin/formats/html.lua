local logger = require("logger")

local slt2 = require('template/slt2')


local HtmlExporter = require("formats/base"):new{
    name = "html",
    version = "html/1.0.0",
    settings_version = "1.0.0"

}

function HtmlExporter:migrateOrDiscardSettings(plugin_settings)
    if plugin_settings[self.name] == nil then
        if plugin_settings.html_export ~= nil then
            local settings = {
                version = self.settings_version,
                enabled = plugin_settings.html_export
            }
            plugin_settings.html_export = nil
            plugin_settings[self.name] = settings
            G_reader_settings:saveSetting(self.id, plugin_settings)
            return settings
        end
    end
    return plugin_settings[self.name]
end

function HtmlExporter:export(t)
    local path, title
    if #t == 1 then
        path = self:getFilePath(t[1].title)
        title = t[1].title
    else
        path = self:getFilePath()
        title = "All Books"
    end
    local file = io.open(path, "w")
    local template = slt2.loadfile(self.path .. "/template/note.tpl")
    logger.dbg("html", t)
    if file then
        local content = slt2.render(template, {
            clippings = t,
            document_title = title,
            version = self.version,
            timestamp = self:getTimeStamp(),
            logger = logger
        })
        file:write(content)
        file:close()
    end
end

return HtmlExporter

