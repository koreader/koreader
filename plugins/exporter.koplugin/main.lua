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
local InfoMessage = require("ui/widget/infomessage")
local MyClipping = require("clip")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local logger = require("logger")
local _ = require("gettext")


-- migrate settings from old "evernote.koplugin" or from previous (monolithic) "exporter.koplugin"
local function migrateSettings()
    local formats = { "html", "joplin", "json", "memos", "my_clippings", "readwise", "text" }

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

local Exporter = WidgetContainer:extend{
    name = "exporter",
    targets = {
        html = require("target/html"),
        joplin = require("target/joplin"),
        json = require("target/json"),
        markdown = require("target/markdown"),
        readwise = require("target/readwise"),
        text = require("target/text"),
        memos = require("target/memos"),
        my_clippings = require("target/my_clippings"),
    },
}

function Exporter:init()
    migrateSettings()
    self.parser = MyClipping:new {
        history_dir = DataStorage:getDataDir() .. "/history",
    }
    for k, _ in pairs(self.targets) do
        self.targets[k].path = self.path
    end
    self.ui.menu:registerToMainMenu(self)
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
    return self.ui and self.ui.document and self.view or false
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
function Exporter:exportCurrentNotes()
    local clippings = self:getDocumentClippings()
    self:exportClippings(clippings)
end

--- Parse and export highlights from all the documents in History
-- and from the Kindle "My Clippings.txt".
function Exporter:exportAllNotes()
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

        UIManager:show(InfoMessage:new {
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
    local submenu = {}
    local sharemenu = {}
    for k, v in pairs(self.targets) do
        submenu[#submenu + 1] = v:getMenuTable()
        if v.shareable then
            sharemenu[#sharemenu + 1] = { text = T(_("Share as %1."), v.name), callback = function()
                local clippings = self:getDocumentClippings()
                local document
                for _, notes in pairs(clippings) do
                    document = notes or {}
                end

                if #document > 0 then
                    v:share(document)
                end
            end
            }
        end
    end
    table.sort(submenu, function(v1, v2)
        return v1.text < v2.text
    end)
    local menu = {
        text = _("Export highlights"),
        sub_item_table = {
            {
                text = _("Export all notes in this book"),
                enabled_func = function()
                    return self:isReadyToExport()
                end,
                callback = function()
                    self:exportCurrentNotes()
                end,
            },
            {
                text = _("Export all notes in your library"),
                enabled_func = function()
                    return self:isReady()
                end,
                callback = function()
                    self:exportAllNotes()
                end,
                separator = #sharemenu == 0,
            },
            {
                text = _("Choose formats and services"),
                sub_item_table = submenu,
            },
            {
                text = _("Choose export folder"),
                keep_menu_open = true,
                callback = function()
                    self:chooseFolder()
                end,
            },
        }
    }
    if #sharemenu > 0 then
        table.sort(sharemenu, function(v1, v2)
            return v1.text < v2.text
        end)
        table.insert(menu.sub_item_table, 3, {
            text = _("Share all notes in this book"),
            enabled_func = function()
                return self:isDocReady()
            end,
            sub_item_table = sharemenu,
            separator = true,
        })
    end
    menu_items.exporter = menu
end

function Exporter:chooseFolder()
    local function set_targets_clipping_dir(dir)
        for k in pairs(self.targets) do
            self.targets[k].clipping_dir = dir
        end
    end
    local clipping_dir_default = DataStorage:getFullDataDir() .. "/clipboard"
    local settings = G_reader_settings:readSetting("exporter") or {}
    local clipping_dir = settings.clipping_dir or clipping_dir_default
    local MultiConfirmBox = require("ui/widget/multiconfirmbox")
    local confirm_box = MultiConfirmBox:new{
        text = T(_("Export folder is set to:\n%1\n\nChoose new export folder?"), clipping_dir),
        choice1_text = _("Use default"),
        choice1_callback = function()
            settings.clipping_dir = nil
            G_reader_settings:saveSetting("exporter", settings)
            set_targets_clipping_dir(clipping_dir_default)
        end,
        choice2_text = _("Choose folder"),
        choice2_callback = function()
            local PathChooser = require("ui/widget/pathchooser")
            local path_chooser = PathChooser:new{
                select_file = false,
                show_files = false,
                path = clipping_dir,
                onConfirm = function(new_path)
                    settings.clipping_dir = new_path
                    G_reader_settings:saveSetting("exporter", settings)
                    set_targets_clipping_dir(new_path)
                end
            }
            UIManager:show(path_chooser)
        end,
    }
    UIManager:show(confirm_box)
end

return Exporter
