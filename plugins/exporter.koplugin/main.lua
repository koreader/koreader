--[[--
Export highlights to different targets.

Some conventions:

- Target: each local format or remote service this plugin can translate to.

Each new target should inherit from "formats/base" and implement *at least* an export function.

- Highlight: Text or image in document. Stored in "highlights" table of documents sidecar file.

Parser uses this table.
If highlight._._.text field is empty the parser uses highlight._._.pboxes field to get an image instead.

- Bookmarks: Data in bookmark explorer. Stored in "bookmarks" table of documents sidecar file.

Every field in bookmarks._ has "text" and "notes" fields.
When user edits a highlight or "renames" bookmark the text field is created or updated.
The parser looks to bookmarks._.text field for edited notes. bookmarks._.notes isn't used for exporting operations.

- Clippings: Parsed form of highlights. Single table for all documents.

- Booknotes: Every table in clippings table. clippings = {"title" = booknotes}

@module koplugin.exporter
--]]--

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local MyClipping = require("clip")
local NetworkMgr = require("ui/network/manager")
local Provider = require("provider")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local T = require("ffi/util").template
local logger = require("logger")
local _ = require("gettext")


-- migrate settings from old "evernote.koplugin" or from previous (monolithic) "exporter.koplugin"
local function migrateSettings()
    -- these are for legacy formats. Don't add new targets here.
    local formats = { "html", "joplin", "json", "readwise", "text" }

    local settings = G_reader_settings:readSetting("exporter")
    if not settings then
        settings = G_reader_settings:readSetting("evernote")
    end

    if type(settings) == "table" then
        for _, fmt in ipairs(formats) do
            if type(settings[fmt]) == "table" then return end
        end
        local new_settings = {}
        for _, fmt in ipairs(formats) do
            new_settings[fmt] = { enabled = false }
        end
        new_settings["joplin"].ip = settings.joplin_IP
        new_settings["joplin"].port = settings.joplin_port
        new_settings["joplin"].token = settings.joplin_token
        new_settings["readwise"].token = settings.readwise_token
        G_reader_settings:saveSetting("exporter", new_settings)
    end
end

-- update clippings from history clippings
local function updateHistoryClippings(clippings, new_clippings)
    for title, booknotes in pairs(new_clippings) do
        for chapter_index, chapternotes in ipairs(booknotes) do
            for note_index, note in ipairs(chapternotes) do
                if clippings[title] == nil or clippings[title][chapter_index] == nil
                    or clippings[title][chapter_index][note_index] == nil
                    or clippings[title][chapter_index][note_index].page ~= note.page
                    or clippings[title][chapter_index][note_index].time ~= note.time
                    or clippings[title][chapter_index][note_index].text ~= note.text
                    or clippings[title][chapter_index][note_index].note ~= note.note then
                    logger.dbg("found new notes in history", booknotes.title)
                    clippings[title] = booknotes
                end
            end
        end
    end
    return clippings
end

-- update clippings from Kindle annotation system
local function updateMyClippings(clippings, new_clippings)
    -- only new titles or new notes in My clippings are updated to clippings
    -- since appending is the only way to modify notes in My Clippings
    for title, booknotes in pairs(new_clippings) do
        if clippings[title] == nil or #clippings[title] < #booknotes then
            logger.dbg("found new notes in MyClipping", booknotes.title)
            clippings[title] = booknotes
        end
    end
    return clippings
end

local targets = {
    html = require("target/html"),
    joplin = require("target/joplin"),
    json = require("target/json"),
    markdown = require("target/markdown"),
    my_clippings = require("target/my_clippings"),
    nextcloud = require("target/nextcloud"),
    readwise = require("target/readwise"),
    text = require("target/text"),
    xmnote = require("target/xmnote"),
}

local function genExportersTable(path)
    local t = {}
    for k, v in pairs(targets) do
        t[k] = v
    end
    if Provider:size("exporter") > 0 then
        local tbl = Provider:getProvidersTable("exporter")
        for k, v in pairs(tbl) do
            t[k] = v
        end
    end
    for _, v in pairs(t) do
        v.path = path
    end
    return t
end

local Exporter = WidgetContainer:extend{
    name = "exporter",
}

function Exporter:init()
    migrateSettings()
    self.parser = MyClipping:new{}
    self.targets = genExportersTable(self.path)
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function Exporter:onDispatcherRegisterActions()
    Dispatcher:registerAction("export_current_notes",
        {category="none", event="ExportCurrentNotes", title=_("Export all notes in current book"), reader=true,})
    Dispatcher:registerAction("export_all_notes",
        {category="none", event="ExportAllNotes", title=_("Export all notes in all books in history"), reader=true, filemanager=true})
end

function Exporter:isReady()
    for k, v in pairs(self.targets) do
        if v:isEnabled() then
            return true
        end
    end
    return false
end

function Exporter:isDocReady()
    return self.ui.document and true or false
end

function Exporter:isReadyToExport()
    return self:isDocReady() and self:isReady()
end

function Exporter:requiresNetwork()
    for k, v in pairs(self.targets) do
        if v:isEnabled() then
            if v.is_remote then
                return true
            end
        end
    end
end

function Exporter:getDocumentClippings()
    return self.parser:parseCurrentDoc(self.view) or {}
end

--- Parse and export highlights from the currently opened document.
function Exporter:onExportCurrentNotes()
    if not self:isReadyToExport() then return end
    self.ui.annotation:updatePageNumbers(true)
    local clippings = self:getDocumentClippings()
    self:exportClippings(clippings)
end

--- Parse and export highlights from all the documents in History
-- and from the Kindle "My Clippings.txt".
function Exporter:onExportAllNotes()
    if not self:isReady() then return end
    local clippings = {}
    clippings = updateHistoryClippings(clippings, self.parser:parseHistory())
    if Device:isKindle() then
        clippings = updateMyClippings(clippings, self.parser:parseMyClippings())
    end
    for title, booknotes in pairs(clippings) do
        -- chapter number is zero
        if #booknotes == 0 then
            clippings[title] = nil
        end
    end
    self:exportClippings(clippings)
end

--- Parse and export highlights from selected documents.
-- @tparam table files list of files as a table of {[file_path] = true}
function Exporter:exportFilesNotes(files)
    local clippings = self.parser:parseFiles(files)
    for title, booknotes in pairs(clippings) do
        -- chapter number is zero
        if #booknotes == 0 then
            clippings[title] = nil
        end
    end
    self:exportClippings(clippings)
end

function Exporter:exportClippings(clippings)
    if type(clippings) ~= "table" then return end
    local exportables = {}
    for _title, booknotes in pairs(clippings) do
        table.insert(exportables, booknotes)
    end
    local export_callback = function()
        UIManager:nextTick(function()
            local timestamp = os.time()
            local statuses = {}
            for k, v in pairs(self.targets) do
                if v:isEnabled() then
                    v.timestamp = timestamp
                    local status = v:export(exportables)
                    if status then
                        if v.is_remote then
                            table.insert(statuses, T(_("%1: Exported successfully."), v.name))
                        else
                            table.insert(statuses, T(_("%1: Exported to %2."), v.name, v:getFilePath(exportables)))
                        end
                    else
                        table.insert(statuses, T(_("%1: Failed to export."), v.name))
                    end
                    v.timestamp = nil
                end
            end
            UIManager:show(InfoMessage:new{
                text = table.concat(statuses, "\n"),
                timeout = 3,
            })
        end)

        UIManager:show(InfoMessage:new{
            text = _("Exporting may take several seconds…"),
            timeout = 1,
        })
    end
    if self:requiresNetwork() then
        NetworkMgr:runWhenOnline(export_callback)
    else
        export_callback()
    end
end

function Exporter:addToMainMenu(menu_items)
    local formats_submenu, share_submenu, styles_submenu = {}, {}, {}
    for k, v in pairs(self.targets) do
        formats_submenu[#formats_submenu + 1] = v:getMenuTable()
        if v.shareable then
            share_submenu[#share_submenu + 1] = {
                text = T(_("Share as %1"), v.name),
                callback = function()
                    local clippings = self:getDocumentClippings()
                    local document
                    for _, notes in pairs(clippings) do
                        document = notes or {}
                    end
                    if #document > 0 then
                        v:share(document)
                    end
                end,
            }
        end
    end
    table.sort(formats_submenu, function(v1, v2)
        return v1.text < v2.text
    end)
    local settings = G_reader_settings:readSetting("exporter", {})
    for i, v in ipairs(ReaderHighlight.getHighlightStyles()) do
        local style = v[2]
        styles_submenu[i] = {
            text = v[1],
            checked_func = function() -- all styles checked by default
                return not (settings.highlight_styles and settings.highlight_styles[style] == false)
            end,
            callback = function()
                if settings.highlight_styles and settings.highlight_styles[style] == false then
                    settings.highlight_styles[style] = nil
                    if next(settings.highlight_styles) == nil then
                        settings.highlight_styles = nil
                    end
                else
                    settings.highlight_styles = settings.highlight_styles or {}
                    settings.highlight_styles[style] = false
                end
            end,
        }
    end
    local menu = {
        text = _("Export highlights"),
        sub_item_table = {
            {
                text = _("Export all notes in current book"),
                enabled_func = function()
                    return self:isReadyToExport()
                end,
                callback = function()
                    self:onExportCurrentNotes()
                end,
            },
            {
                text = _("Export all notes in all books in history"),
                enabled_func = function()
                    return self:isReady()
                end,
                callback = function()
                    self:onExportAllNotes()
                end,
                separator = #share_submenu == 0,
            },
            {
                text = _("Choose formats and services"),
                sub_item_table = formats_submenu,
            },
            {
                text = _("Choose highlight styles"),
                sub_item_table = styles_submenu,
                separator = true,
            },
            {
                text = _("Choose export folder"),
                keep_menu_open = true,
                callback = function()
                    self:chooseFolder()
                end,
            },
            {
                text = _("Use book folder for single export"),
                checked_func = function()
                    return settings.clipping_dir_book
                end,
                callback = function()
                    settings.clipping_dir_book = not settings.clipping_dir_book or nil
                end,
            },
        },
    }
    if #share_submenu > 0 then
        table.sort(share_submenu, function(v1, v2)
            return v1.text < v2.text
        end)
        table.insert(menu.sub_item_table, 3, {
            text = _("Share all notes in this book"),
            enabled_func = function()
                return self:isDocReady()
            end,
            sub_item_table = share_submenu,
            separator = true,
        })
    end
    menu_items.exporter = menu
end

function Exporter:chooseFolder()
    local settings = G_reader_settings:readSetting("exporter", {})
    local title_header = _("Current export folder:")
    local current_path = settings.clipping_dir
    local default_path = DataStorage:getFullDataDir() .. "/clipboard"
    local caller_callback = function(path)
        settings.clipping_dir = path
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
end

return Exporter
